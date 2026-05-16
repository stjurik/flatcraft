/**
 * Template DTO — те, що повертає `GET /templates` і споживає web.
 *
 * Це менший зріз `templates` таблиці (docs/05 §templates): без
 * parameters_schema / default_parameters (вони важкі і для каталогу
 * не потрібні — приходять на сторінці редактора).
 */
import { z } from "zod";

export const TemplateSummarySchema = z.object({
  id: z.string().uuid(),
  slug: z.string().min(1),
  nameUk: z.string().min(1),
  nameEn: z.string().min(1),
  descriptionUk: z.string().nullable(),
  descriptionEn: z.string().nullable(),
  version: z.number().int().positive(),
  previewImageUrl: z.string().url().nullable(),
  isPublished: z.boolean(),
  createdAt: z.string().datetime(),
  updatedAt: z.string().datetime(),
});

export type TemplateSummary = z.infer<typeof TemplateSummarySchema>;

export const TemplateListResponseSchema = z.object({
  items: z.array(TemplateSummarySchema),
});

export type TemplateListResponse = z.infer<typeof TemplateListResponseSchema>;
