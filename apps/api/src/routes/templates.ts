/**
 * GET /templates — каталог опублікованих шаблонів.
 *
 * Поки повертає лише `is_published = true`. У майбутньому додамо
 * пейджинг + фільтри (по матеріалу/категорії) — поки 5 шаблонів MVP
 * сорт-результат на клієнті.
 */
import { TemplateListResponseSchema } from "@flatcraft/types";
import { schema } from "@flatcraft/db";
import { eq } from "drizzle-orm";
import type { FastifyPluginAsyncZod } from "fastify-type-provider-zod";

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
};
