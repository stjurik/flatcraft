/**
 * POST /exports          — створює async job, повертає 202 + jobId.
 * GET  /exports/:id      — поточний стан job (для retries/refresh).
 * GET  /exports/:id/events — SSE: стрім {status, progress, result?, error?}.
 *
 * Flow: API ставить job у in-memory store → background fetch до Python
 * /export → update store з результатом → SSE-listener шле події клієнту.
 *
 * Persistence + distributed scaling — Phase 5 (BullMQ + Redis). Зараз
 * in-memory достатньо для одного API-replica MVP.
 */
import {
  DEFAULT_PROCESS,
  ExportJobAcceptedSchema,
  ExportJobEventSchema,
  ExportRequestSchema,
  ExportResponseSchema,
} from "@flatcraft/types";
import type { FastifyPluginAsyncZod } from "fastify-type-provider-zod";
import { randomUUID } from "node:crypto";
import { z } from "zod";

import { env } from "../env.js";
import type { ExportJob } from "../lib/job-store.js";
import { JobStore } from "../lib/job-store.js";
import {
  createMaterialDensityLookup,
  type MaterialDensityLookup,
} from "../lib/material-density.js";
import { sessionHash } from "../lib/session-hash.js";
import { createTelemetry, type Telemetry } from "../lib/telemetry.js";
import { EXPORT_RATE_LIMIT } from "../plugins/rate-limit.js";
import {
  buildProblem,
  getBendSpec,
  ProblemDetailsSchema,
  validateExportBends,
  validateExportHoles,
  validateExportPerforation,
  validateExportProfile,
  validateExportSheet,
} from "../lib/validate-export.js";

const NotFoundSchema = z.object({ error: z.literal("job_not_found") });

const PARAMS = z.object({ id: z.string().uuid() });

function toEvent(job: ExportJob) {
  const base = {
    id: job.id,
    status: job.status,
    progress: job.progress,
  } as const;
  if (job.status === "done" && job.result) {
    return { ...base, result: job.result };
  }
  if (job.status === "failed" && job.error) {
    return { ...base, error: job.error };
  }
  return base;
}

/** Контекст телеметрії, який тягнеться крізь фонову обробку job'а (ADR-032). */
interface JobContext {
  readonly telemetry: Telemetry;
  readonly templateSlug: string;
  readonly sessionHash: string | null;
  /** `Date.now()` моменту прийому запиту — для повної тривалості export_*. */
  readonly requestStart: number;
}

async function runJob(
  store: JobStore,
  jobId: string,
  body: unknown,
  ctx: JobContext,
): Promise<void> {
  const { telemetry, templateSlug, sessionHash: sh, requestStart } = ctx;
  store.update(jobId, { status: "running", progress: 10 });

  // D3 (план PR 2): api вимірює worker-round-trip; worker без змін.
  const cadStart = Date.now();
  await telemetry.writeEvent({
    event_type: "cad_started",
    template_slug: templateSlug,
    process: DEFAULT_PROCESS,
    session_hash: sh,
  });

  try {
    // Рішення yurii 2026-10-06 («матеріал передаємо у воркер»; раніше воркер
    // його не отримував), обов'язковість закріплена рішенням Архітектора
    // 2026-10-13 (ADR-043): material_code форвардиться у cad-worker — воркеру
    // потрібен коефіцієнт матеріалу для parity-перевірки відстані отворів від
    // гиба (hole_to_bend_distance). cad-worker Pydantic ExportRequest приймає
    // поле `material_code` ОБОВ'ЯЗКОВИМ (ADR-043) — без нього 422.
    // Issue #70: export_id = jobId (== persisted exports.id) — worker вживає
    // його для QR-permalink {BASE_URL}/f/{export_id} у PDF замість fallback
    // непрацюючого flatcraft:// scheme.
    const cadBody = {
      ...(body as Record<string, unknown>),
      export_id: jobId,
    };
    const upstream = await fetch(`${env.CAD_WORKER_URL}/export`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify(cadBody),
    });
    if (!upstream.ok) {
      const detail = (await upstream.text().catch(() => "")).slice(0, 256);
      store.update(jobId, {
        status: "failed",
        progress: 0,
        error: `cad-worker ${upstream.status}: ${detail || "no detail"}`,
      });
      await telemetry.completeExport(jobId, {
        status: "failed",
        errorMessage: `cad-worker ${upstream.status}`,
      });
      await telemetry.writeEvent({
        event_type: "export_failed",
        template_slug: templateSlug,
        process: DEFAULT_PROCESS,
        session_hash: sh,
        error_code: `CAD_WORKER_${upstream.status}`,
        duration_ms: Date.now() - requestStart,
      });
      return;
    }
    await telemetry.writeEvent({
      event_type: "cad_completed",
      template_slug: templateSlug,
      process: DEFAULT_PROCESS,
      session_hash: sh,
      duration_ms: Date.now() - cadStart,
    });
    store.update(jobId, { status: "running", progress: 80 });
    const data = await upstream.json();
    const result = ExportResponseSchema.parse(data);
    store.update(jobId, { status: "done", progress: 100, result });
    await telemetry.completeExport(jobId, {
      status: "done",
      r2Keys: { dxf: result.artifacts.dxf.s3_key, pdf: result.artifacts.pdf.s3_key },
    });
    await telemetry.writeEvent({
      event_type: "export_completed",
      template_slug: templateSlug,
      process: DEFAULT_PROCESS,
      session_hash: sh,
      duration_ms: Date.now() - requestStart,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "unknown error";
    store.update(jobId, { status: "failed", progress: 0, error: message });
    await telemetry.completeExport(jobId, { status: "failed", errorMessage: message });
    await telemetry.writeEvent({
      event_type: "export_failed",
      template_slug: templateSlug,
      process: DEFAULT_PROCESS,
      session_hash: sh,
      error_code: "CAD_ERROR",
      duration_ms: Date.now() - requestStart,
    });
  }
}

export interface ExportRoutesOptions {
  readonly store?: JobStore;
  /** Override для тестів (NOOP/recording). Дефолт — drizzle через app.db. */
  readonly telemetry?: Telemetry;
  /**
   * Override джерела густини матеріалу (issue #261). Дефолт —
   * `createMaterialDensityLookup(app.db)` (таблиця `materials`, лише
   * `is_active = true`).
   */
  readonly materialDensity?: MaterialDensityLookup;
}

export function buildExportRoutes(options: ExportRoutesOptions = {}): FastifyPluginAsyncZod {
  const store = options.store ?? new JobStore();

  return async (app) => {
    // Best-effort телеметрія (ADR-032). За замовчуванням — drizzle через app.db
    // (декорований dbPlugin, зареєстрованим раніше у server.ts).
    const telemetry = options.telemetry ?? createTelemetry(app.db, app.log);
    // Issue #261: густина матеріалу з бази — одне джерело істини для маси у
    // PDF (замість фіксованого 7850 у cad-worker для будь-якого матеріалу).
    const materialDensity = options.materialDensity ?? createMaterialDensityLookup(app.db);

    app.post(
      "/exports",
      {
        // Phase X.1 A (ADR-020): IP-based 30/год + burst-ban. Override
        // глобального 100/хв для саме цього маршруту.
        config: { rateLimit: EXPORT_RATE_LIMIT },
        schema: {
          description: "Async export: створює job, виконує у фоні, returns 202 + jobId.",
          tags: ["exports"],
          body: ExportRequestSchema,
          response: { 202: ExportJobAcceptedSchema, 422: ProblemDetailsSchema },
        },
      },
      async (req, reply) => {
        // ADR-019: серверний gate ПЕРЕД створенням job/forward. Невалідний гиб
        // (напр. R недопустимий для товщини) → 422 RFC 9457, жодного артефакта.
        const spec = await getBendSpec();
        // ADR-026: геометрична валідність профілю (плече >= товщина+радіус) —
        // та сама validateProfile, що й render-gate у браузері.
        // validateExportPerforation: grid отворів перфо-панелі (pitch > розмір
        // отвору) — інакше отвори зливаються у проріз.
        // validateExportSheet: габарит розгортки vs можливості верстата
        // (CLAUDE.md §7 п.4). validateExportHoles: відстань отворів від лінії
        // гиба — від краю отвору (докладніше у export-gate.ts).
        const errors = [
          ...validateExportProfile(req.body),
          ...validateExportBends(req.body, spec),
          ...validateExportPerforation(req.body),
          ...validateExportSheet(req.body, spec),
          ...validateExportHoles(req.body, spec),
        ];
        // Телеметрія (ADR-032): session_hash з IP+добовий salt — сирий IP не
        // зберігається. params — знімок геометрії (не PII).
        const sh = sessionHash(req.ip);
        const templateSlug = req.body.template_slug;
        const params = req.body.parameters as Record<string, unknown>;
        if (errors.length > 0) {
          // Issue #215: одна подія на кожен УНІКАЛЬНИЙ код (не лише errors[0]) —
          // інакше digest/топ-кодів бачить тільки першу знайдену причину, а не
          // всі. attempt_id — спільний для цих подій ідентифікатор спроби;
          // crypto.randomUUID() на запит, НЕ похідний від IP/session_hash
          // (яких і не можна відновити назад з UUID) — колонку не додаємо,
          // живе лише в params (JSONB), поруч із геометрією.
          const attemptId = randomUUID();
          const rejectedParams = { ...params, attempt_id: attemptId };
          const uniqueCodes = [...new Set(errors.map((e) => e.code))];
          for (const code of uniqueCodes) {
            await telemetry.writeEvent({
              event_type: "validation_rejected",
              template_slug: templateSlug,
              process: DEFAULT_PROCESS,
              session_hash: sh,
              params: rejectedParams,
              error_code: code,
            });
          }
          return reply.code(422).send(buildProblem(errors, "/exports"));
        }
        // Issue #261: густина — з бази (materials, is_active=true), не з
        // клієнтського тіла (ExportRequestSchema такого поля навіть не має).
        // Невідомий/неактивний матеріал → 422 ДО створення job/telemetry —
        // так само, як геометричні помилки вище: жодного запису, жодного
        // forward у cad-worker.
        const density = await materialDensity(req.body.material_code);
        if (density === null) {
          const attemptId = randomUUID();
          const rejectedParams = { ...params, attempt_id: attemptId };
          await telemetry.writeEvent({
            event_type: "validation_rejected",
            template_slug: templateSlug,
            process: DEFAULT_PROCESS,
            session_hash: sh,
            params: rejectedParams,
            error_code: "MATERIAL_NOT_FOUND",
          });
          return reply.code(422).send(
            buildProblem(
              [
                {
                  field: "material_code",
                  code: "MATERIAL_NOT_FOUND",
                  value: req.body.material_code,
                  message: `Матеріал «${req.body.material_code}» не знайдено або він неактивний.`,
                },
              ],
              "/exports",
            ),
          );
        }
        const job = store.create();
        await telemetry.insertExport({
          id: job.id,
          templateSlug,
          sessionHash: sh,
          formats: ["dxf", "pdf"],
        });
        await telemetry.writeEvent({
          event_type: "export_requested",
          template_slug: templateSlug,
          process: DEFAULT_PROCESS,
          session_hash: sh,
          params,
        });
        // background: не await runJob — щоб клієнт одразу отримав jobId.
        // density_kg_m3 — з бази (вище), перемагає будь-яке однойменне поле,
        // яке клієнт міг би додати в тіло (ExportRequestSchema його не
        // форвардить, але тут — явна гарантія).
        void runJob(
          store,
          job.id,
          { ...(req.body as Record<string, unknown>), density_kg_m3: density },
          {
            telemetry,
            templateSlug,
            sessionHash: sh,
            requestStart: Date.now(),
          },
        );
        return reply.code(202).send({ id: job.id, status: job.status });
      },
    );

    app.get(
      "/exports/:id",
      {
        schema: {
          params: PARAMS,
          response: { 200: ExportJobEventSchema, 404: NotFoundSchema },
        },
      },
      async (req, reply) => {
        const job = store.get(req.params.id);
        if (!job) return reply.code(404).send({ error: "job_not_found" as const });
        return toEvent(job);
      },
    );

    app.get(
      "/exports/:id/events",
      {
        schema: { params: PARAMS },
      },
      async (req, reply) => {
        const job = store.get(req.params.id);
        if (!job) {
          return reply.code(404).send({ error: "job_not_found" as const });
        }

        reply.raw.writeHead(200, {
          "Content-Type": "text/event-stream",
          "Cache-Control": "no-cache, no-transform",
          Connection: "keep-alive",
          // CORS — Fastify already встановив через @fastify/cors на основі
          // origin header; SSE також потребує цих заголовків (cors plugin
          // не зачіпає reply.raw напряму).
          "Access-Control-Allow-Origin": req.headers.origin ?? env.APP_BASE_URL,
          "Access-Control-Allow-Credentials": "true",
        });

        const send = (j: ExportJob) => {
          reply.raw.write(`data: ${JSON.stringify(toEvent(j))}\n\n`);
        };

        // Поточний стан → одразу.
        send(job);
        if (job.status === "done" || job.status === "failed") {
          reply.raw.end();
          return reply;
        }

        const unsubscribe = store.subscribe(job.id, (updated) => {
          send(updated);
          if (updated.status === "done" || updated.status === "failed") {
            unsubscribe();
            reply.raw.end();
          }
        });

        req.raw.on("close", () => {
          unsubscribe();
        });

        return reply;
      },
    );
  };
}
