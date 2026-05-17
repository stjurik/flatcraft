/**
 * POST /exports — синхронний експорт DXF (Phase 2.7).
 *
 * Flow: web → api (валідація + forward) → cad-worker (DXF gen + S3 upload)
 * → presigned URL → клієнт скачує.
 *
 * Async BullMQ-шлях — Phase 2.8 (status polling/SSE). Цей endpoint
 * лишиться як sync-fallback для дрібних виробів (<3 секунди).
 */
import { ExportRequestSchema, ExportResponseSchema } from "@flatcraft/types";
import type { FastifyPluginAsyncZod } from "fastify-type-provider-zod";
import { z } from "zod";

import { env } from "../env.js";

const UpstreamErrorSchema = z.object({
  error: z.literal("cad_worker_failed"),
  status: z.number().int(),
  detail: z.string().optional(),
});

export const exportRoutes: FastifyPluginAsyncZod = async (app) => {
  app.post(
    "/exports",
    {
      schema: {
        description: "Sync export: forward до cad-worker, повертає presigned URL з S3/R2.",
        tags: ["exports"],
        body: ExportRequestSchema,
        response: {
          200: ExportResponseSchema,
          502: UpstreamErrorSchema,
        },
      },
    },
    async (req, reply) => {
      const upstream = await fetch(`${env.CAD_WORKER_URL}/export`, {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json" },
        body: JSON.stringify(req.body),
      }).catch((err: unknown) => {
        app.log.error({ err }, "cad-worker fetch failed");
        return null;
      });

      if (!upstream) {
        return reply
          .code(502)
          .send({ error: "cad_worker_failed" as const, status: 0, detail: "unreachable" });
      }

      if (!upstream.ok) {
        const text = await upstream.text().catch(() => "");
        return reply.code(502).send({
          error: "cad_worker_failed" as const,
          status: upstream.status,
          detail: text.slice(0, 256),
        });
      }

      const data = await upstream.json();
      // Zod validate response — захищає клієнта від рассинхрону схеми
      // worker'а (тип-сейф контракт між сервісами через @flatcraft/types).
      return ExportResponseSchema.parse(data);
    },
  );
};
