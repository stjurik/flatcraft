/**
 * Шаблони:
 *   GET /templates         — каталог опублікованих.
 *   GET /templates/:slug   — деталі (з default_parameters для редактора).
 *
 * Тільки опубліковані повертаються — заглушка контролю доступу до часу,
 * поки не буде admin-режиму превʼю чорнового шаблону.
 */
import { TemplateDetailSchema, TemplateListResponseSchema } from "@flatcraft/types";
import { schema } from "@flatcraft/db";
import { and, eq } from "drizzle-orm";
import type { FastifyPluginAsyncZod } from "fastify-type-provider-zod";
import { z } from "zod";

export const templateRoutes: FastifyPluginAsyncZod = async (app) => {
  app.get(
    "/templates",
    {
      schema: {
        description: "Каталог опублікованих шаблонів.",
        tags: ["templates"],
        response: { 200: TemplateListResponseSchema },
      },
    },
    async () => {
      const rows = await app.db
        .select({
          id: schema.templates.id,
          slug: schema.templates.slug,
          nameUk: schema.templates.nameUk,
          nameEn: schema.templates.nameEn,
          descriptionUk: schema.templates.descriptionUk,
          descriptionEn: schema.templates.descriptionEn,
          version: schema.templates.version,
          previewImageUrl: schema.templates.previewImageUrl,
          isPublished: schema.templates.isPublished,
          createdAt: schema.templates.createdAt,
          updatedAt: schema.templates.updatedAt,
        })
        .from(schema.templates)
        .where(eq(schema.templates.isPublished, true))
        .orderBy(schema.templates.slug);

      return {
        items: rows.map((r) => ({
          ...r,
          createdAt: r.createdAt.toISOString(),
          updatedAt: r.updatedAt.toISOString(),
        })),
      };
    },
  );

  const NotFoundSchema = z.object({ error: z.literal("template_not_found") });

  app.get(
    "/templates/:slug",
    {
      schema: {
        description: "Деталі шаблону з default_parameters.",
        tags: ["templates"],
        params: z.object({
          slug: z
            .string()
            .min(1)
            .max(64)
            // slug-формат збігається з seed: lowercase + underscore.
            .regex(/^[a-z][a-z0-9_]*$/),
        }),
        response: {
          200: TemplateDetailSchema,
          404: NotFoundSchema,
        },
      },
    },
    async (req, reply) => {
      const [row] = await app.db
        .select()
        .from(schema.templates)
        .where(
          and(eq(schema.templates.slug, req.params.slug), eq(schema.templates.isPublished, true)),
        )
        .limit(1);

      if (!row) {
        return reply.code(404).send({ error: "template_not_found" as const });
      }

      return {
        ...row,
        createdAt: row.createdAt.toISOString(),
        updatedAt: row.updatedAt.toISOString(),
        // drizzle повертає jsonb як unknown → нормалізуємо у Record для Zod.
        defaultParameters: (row.defaultParameters as Record<string, unknown> | null) ?? {},
      };
    },
  );
};
