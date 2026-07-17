/**
 * POST /feedback/:exportId — виробничий фідбек з форми /f/{export_id}.
 *
 * Phase 3.4, ADR-032 §feedback / R-01 mitigation 4:
 * Мобільна форма без auth: 3 поля (outcome / deviation / comment). Записує
 * рядок у `export_feedback` і подію `feedback_submitted` у `events`.
 *
 * Rate-limit: IP-based 20/hour (більше за export, бо це коротка форма
 * і можуть відправляти кілька раз при поганому UX).
 *
 * 404 — на невідомий export_id (щоб не дати ознакомитись з валідністю UUID).
 */
import { schema, type DatabaseClient } from "@flatcraft/db";
import { DEFAULT_PROCESS } from "@flatcraft/types";
import { eq } from "drizzle-orm";
import type { RateLimitOptions } from "@fastify/rate-limit";
import type { FastifyPluginAsyncZod } from "fastify-type-provider-zod";
import { z } from "zod";

import { sessionHash } from "../lib/session-hash.js";
import { createTelemetry, type Telemetry, NOOP_TELEMETRY } from "../lib/telemetry.js";

const OUTCOMES = ["made", "deviations", "failed"] as const;
const LOCALES = ["uk", "en"] as const;

// Довільна форма з UX-текстами з `docs/promts/inputs/c4-feedback-copy.md`.
// Обмеження довжин — щоб не сховати XSS-payload / spam-flood.
const FeedbackBodySchema = z
  .object({
    outcome: z.enum(OUTCOMES),
    deviation_description: z.string().trim().max(500).optional(),
    comment: z.string().trim().max(1000).optional(),
    locale: z.enum(LOCALES).default("uk"),
  })
  .superRefine((body, ctx) => {
    // outcome=failed → comment обов'язковий (за UX-специфікацією C4).
    if (body.outcome === "failed" && (!body.comment || body.comment.length === 0)) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["comment"],
        message: "Коментар обов'язковий, якщо деталь не вийшла.",
      });
    }
  });

const ParamsSchema = z.object({
  exportId: z.string().uuid(),
});

const ResponseSchema = z.object({
  status: z.literal("received"),
});

const NotFoundSchema = z.object({
  error: z.literal("export_not_found"),
});

export const FEEDBACK_RATE_LIMIT: RateLimitOptions = {
  max: 20,
  timeWindow: "1 hour",
  keyGenerator: (req) => req.ip,
  errorResponseBuilder: (_req, context) => {
    const minutes = Math.max(1, Math.ceil(context.ttl / 60_000));
    return {
      type: "https://flatcraft.io/errors/rate-limit",
      title: "Rate limit exceeded",
      status: 429,
      detail: `Забагато відгуків з вашої IP-адреси. Спробуйте через ${minutes} хв.`,
      instance: "/feedback",
    };
  },
};

interface Options {
  telemetry?: Telemetry;
}

export function buildFeedbackRoutes(options: Options = {}): FastifyPluginAsyncZod {
  return async function feedbackRoutes(app) {
    // `app.db` декорований `dbPlugin` (див. server.ts). Може бути undefined
    // у unit-тестах без БД. Коли options.telemetry передано явно (unit-режим) —
    // не робимо DB-запитів; телеметрія і валідація все одно проганяються.
    const db: DatabaseClient["db"] | undefined = options.telemetry
      ? undefined
      : (app as unknown as { db?: DatabaseClient["db"] }).db;
    const telemetry: Telemetry =
      options.telemetry ?? (db ? createTelemetry(db, app.log) : NOOP_TELEMETRY);

    app.post(
      "/feedback/:exportId",
      {
        config: { rateLimit: FEEDBACK_RATE_LIMIT },
        schema: {
          params: ParamsSchema,
          body: FeedbackBodySchema,
          response: {
            200: ResponseSchema,
            404: NotFoundSchema,
          },
        },
      },
      async (request, reply) => {
        const { exportId } = request.params;
        const body = request.body;

        // 404-check: чи існує такий export_id. Без auth — це єдиний спосіб
        // не дати створити фідбек на неіснуючий job.
        if (db) {
          const found = await db
            .select({ id: schema.exports.id, templateSlug: schema.exports.templateSlug })
            .from(schema.exports)
            .where(eq(schema.exports.id, exportId))
            .limit(1);

          if (found.length === 0) {
            return reply.code(404).send({ error: "export_not_found" as const });
          }

          const templateSlug = found[0]?.templateSlug ?? null;
          const session = sessionHash(request.ip);

          // Insert feedback row. Best-effort — якщо DB не встигне (rare),
          // юзер побачить помилку і повторить.
          await db.insert(schema.exportFeedback).values({
            exportId,
            outcome: body.outcome,
            deviationDescription: body.deviation_description ?? null,
            comment: body.comment ?? null,
            locale: body.locale,
            sessionHash: session,
          });

          // Аналітична подія (агрегат, БЕЗ вмісту коментаря — GDPR/ADR-032).
          await telemetry.writeEvent({
            event_type: "feedback_submitted",
            template_slug: templateSlug,
            process: DEFAULT_PROCESS,
            session_hash: session,
            params: {
              outcome: body.outcome,
              has_deviation_description: !!body.deviation_description,
              has_comment: !!body.comment,
              locale: body.locale,
            },
          });
        } else {
          // Unit-режим без БД — просто телеметрія (для тестів SSE-flow не діє).
          await telemetry.writeEvent({
            event_type: "feedback_submitted",
            template_slug: null,
            process: DEFAULT_PROCESS,
            session_hash: null,
            params: {
              outcome: body.outcome,
              has_deviation_description: !!body.deviation_description,
              has_comment: !!body.comment,
              locale: body.locale,
            },
          });
        }

        return reply.code(200).send({ status: "received" as const });
      },
    );
  };
}
