/**
 * Продукти (Phase 3.0, ADR-027):
 *   GET /products         — каталог опублікованих виробів (Summary).
 *   GET /products/:slug   — детальна сторінка з resolved base_template (Detail).
 *
 * Listing маскує fixed_parameters / user_editable_fields — ці поля з'являються
 * лише у detail. Це не security-сенсетивно (preset видно з product-сторінки
 * клієнтом), але робить response listing'у тонким (Hi cache friendliness).
 *
 * GET /products/:slug додатково резолвить `base_template` через окремий запит
 * до templates таблиці. Якщо base_template_slug не існує / не опублікований —
 * 422 UNSUPPORTED_BASE_TEMPLATE (ADR-027: інваріант seed-валідатора, не може
 * виникнути у нормальному flow; runtime — як safety net).
 */
import { ProductDetailSchema, ProductListResponseSchema } from "@flatcraft/types";
import { schema } from "@flatcraft/db";
import { and, eq } from "drizzle-orm";
import type { FastifyPluginAsyncZod } from "fastify-type-provider-zod";
import { z } from "zod";

export const productRoutes: FastifyPluginAsyncZod = async (app) => {
  app.get(
    "/products",
    {
      schema: {
        description: "Каталог опублікованих виробів (preset базового шаблону).",
        tags: ["products"],
        response: { 200: ProductListResponseSchema },
      },
    },
    async () => {
      const rows = await app.db
        .select({
          slug: schema.products.slug,
          name: schema.products.name,
          description: schema.products.description,
          baseTemplateSlug: schema.products.baseTemplateSlug,
          previewImageUrl: schema.products.previewImageUrl,
          useCases: schema.products.useCases,
          isPublished: schema.products.isPublished,
        })
        .from(schema.products)
        .where(eq(schema.products.isPublished, true))
        .orderBy(schema.products.slug);

      return { items: rows };
    },
  );

  const NotFoundSchema = z.object({ error: z.literal("product_not_found") });
  const UnsupportedBaseSchema = z.object({
    error: z.literal("unsupported_base_template"),
    baseTemplateSlug: z.string(),
  });

  app.get(
    "/products/:slug",
    {
      schema: {
        description: "Деталь продукту з resolved base_template для studio-flow.",
        tags: ["products"],
        params: z.object({
          slug: z
            .string()
            .min(1)
            .max(64)
            // Products: kebab-case ASCII (ADR-027), на відміну від templates lowercase+underscore.
            .regex(/^[a-z][a-z0-9-]*$/),
        }),
        response: {
          200: ProductDetailSchema,
          404: NotFoundSchema,
          422: UnsupportedBaseSchema,
        },
      },
    },
    async (req, reply) => {
      const [productRow] = await app.db
        .select()
        .from(schema.products)
        .where(
          and(eq(schema.products.slug, req.params.slug), eq(schema.products.isPublished, true)),
        )
        .limit(1);

      if (!productRow) {
        return reply.code(404).send({ error: "product_not_found" as const });
      }

      // Resolve base_template — потрібен для AutoForm (schema + defaults) у studio.
      // Якщо base_template неопублікований (it's a published-only filter у GET /templates,
      // але products можуть посилатися на хибно неопубліковані base templates типу
      // `perforated_panel_square` із PR 5, який is_published=false) — резолвимо БЕЗ
      // is_published фільтра, бо це internal lookup.
      const [templateRow] = await app.db
        .select()
        .from(schema.templates)
        .where(eq(schema.templates.slug, productRow.baseTemplateSlug))
        .limit(1);

      if (!templateRow) {
        return reply.code(422).send({
          error: "unsupported_base_template" as const,
          baseTemplateSlug: productRow.baseTemplateSlug,
        });
      }

      return {
        slug: productRow.slug,
        name: productRow.name,
        description: productRow.description,
        baseTemplateSlug: productRow.baseTemplateSlug,
        previewImageUrl: productRow.previewImageUrl,
        useCases: productRow.useCases,
        isPublished: productRow.isPublished,
        fixedParameters: (productRow.fixedParameters as Record<string, unknown> | null) ?? {},
        userEditableFields: productRow.userEditableFields,
        baseTemplate: {
          ...templateRow,
          createdAt: templateRow.createdAt.toISOString(),
          updatedAt: templateRow.updatedAt.toISOString(),
          defaultParameters:
            (templateRow.defaultParameters as Record<string, unknown> | null) ?? {},
        },
      };
    },
  );
};
