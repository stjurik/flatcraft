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
  ExportJobAcceptedSchema,
  ExportJobEventSchema,
  ExportRequestSchema,
  ExportResponseSchema,
} from "@flatcraft/types";
import type { FastifyPluginAsyncZod } from "fastify-type-provider-zod";
import { z } from "zod";

import { env } from "../env.js";
import type { ExportJob } from "../lib/job-store.js";
import { JobStore } from "../lib/job-store.js";
import { EXPORT_RATE_LIMIT } from "../plugins/rate-limit.js";
import {
  buildProblem,
  getBendSpec,
  ProblemDetailsSchema,
  validateExportBends,
  validateExportPerforation,
  validateExportProfile,
} from "../lib/validate-export.js";

const NotFoundSchema = z.object({ error: z.literal("job_not_found") });

const PARAMS = z.object({ id: z.string().uuid() });

/**
 * Видаляє `material_code` з payload перед форвардом у cad-worker.
 * Body уже провалідовано ExportRequestSchema (discriminatedUnion з обов'язковим
 * material_code), тож типобезпека гарантується на rest-стороні.
 */
function stripMaterialCode(body: unknown): unknown {
  if (body === null || typeof body !== "object") return body;
  const { material_code: _unused, ...rest } = body as Record<string, unknown>;
  return rest;
}

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

async function runJob(store: JobStore, jobId: string, body: unknown): Promise<void> {
  store.update(jobId, { status: "running", progress: 10 });
  try {
    // ADR-018: web→api приймає material_code, але cad-worker Pydantic має
    // extra="forbid" — strip перед форвардом. material_code знадобиться при
    // drafts-persistence (Phase 3+); поки лише доходить до API.
    const cadBody = stripMaterialCode(body);
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
      return;
    }
    store.update(jobId, { status: "running", progress: 80 });
    const data = await upstream.json();
    const result = ExportResponseSchema.parse(data);
    store.update(jobId, { status: "done", progress: 100, result });
  } catch (err) {
    store.update(jobId, {
      status: "failed",
      progress: 0,
      error: err instanceof Error ? err.message : "unknown error",
    });
  }
}

export interface ExportRoutesOptions {
  readonly store?: JobStore;
}

export function buildExportRoutes(options: ExportRoutesOptions = {}): FastifyPluginAsyncZod {
  const store = options.store ?? new JobStore();

  return async (app) => {
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
        const errors = [
          ...validateExportProfile(req.body),
          ...validateExportBends(req.body, spec),
          ...validateExportPerforation(req.body),
        ];
        if (errors.length > 0) {
          return reply.code(422).send(buildProblem(errors, "/exports"));
        }
        const job = store.create();
        // background: не await — щоб клієнт одразу отримав jobId.
        void runJob(store, job.id, req.body);
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
