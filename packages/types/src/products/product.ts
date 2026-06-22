/**
 * Product DTO — те, що повертає `GET /products` (listing) і `GET /products/:slug`
 * (detail). Phase 3.0, ADR-027.
 *
 * Listing (Summary) НЕ повертає fixed_parameters / user_editable_fields — це
 * деталі реалізації preset'у, релевантні лише на сторінці продукту. Detail
 * додає їх + resolved base_template (schema + defaults для AutoForm).
 */
import { z } from "zod";

import { TemplateDetailSchema } from "../domain/template.js";

/**
 * Slug-формат: kebab-case ASCII (на відміну від templates, де lowercase+underscore).
 * Приклади: `perforated-panel-decorative`, `wall-shelf-custom`.
 */
export const PRODUCT_SLUG_REGEX = /^[a-z][a-z0-9-]*$/;

export const ProductSummarySchema = z.object({
  slug: z.string().min(1).regex(PRODUCT_SLUG_REGEX),
  name: z.string().min(1),
  description: z.string().nullable(),
  baseTemplateSlug: z.string().min(1),
  previewImageUrl: z.string().min(1).nullable(),
  useCases: z.array(z.string()),
  isPublished: z.boolean(),
});

export type ProductSummary = z.infer<typeof ProductSummarySchema>;

export const ProductListResponseSchema = z.object({
  items: z.array(ProductSummarySchema),
});

export type ProductListResponse = z.infer<typeof ProductListResponseSchema>;

/**
 * Detail = Summary + fixed_parameters + user_editable_fields + resolved base_template.
 *
 * `baseTemplate` — повний TemplateDetail (parametersSchema + defaultParameters),
 * щоб клієнт міг показати AutoForm з visible_fields фільтром (Рішення 4) без
 * додаткового запиту до `/templates/:base_template_slug`. Серверне резолвання
 * відбувається у `GET /products/:slug` handler'і.
 */
export const ProductDetailSchema = ProductSummarySchema.extend({
  fixedParameters: z.record(z.string(), z.unknown()),
  userEditableFields: z.array(z.string().min(1)),
  baseTemplate: TemplateDetailSchema,
});

export type ProductDetail = z.infer<typeof ProductDetailSchema>;
