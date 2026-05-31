/**
 * Контракт `GET /materials` (Phase 2.12).
 *
 * Повертає матеріали з доступними товщинами (JOIN materials ↔
 * material_thicknesses, лише active=true). Web-клієнт використовує
 * це для рендерингу `<MaterialSection>` у студії.
 */
import { z } from "zod";

export const MaterialCategorySchema = z.enum(["steel", "stainless", "aluminum", "non_ferrous"]);
export type MaterialCategory = z.infer<typeof MaterialCategorySchema>;

export const MaterialChoiceSchema = z.object({
  code: z.string().min(1).max(64),
  name_uk: z.string().min(1),
  name_en: z.string().min(1),
  category: MaterialCategorySchema,
  /** Сортовано за зростанням; «10.0» виключено для stainless (див. seed §4). */
  thicknesses_mm: z.array(z.number().positive()).min(1),
});
export type MaterialChoice = z.infer<typeof MaterialChoiceSchema>;

export const MaterialListResponseSchema = z.object({
  items: z.array(MaterialChoiceSchema),
});
export type MaterialListResponse = z.infer<typeof MaterialListResponseSchema>;
