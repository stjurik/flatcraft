/**
 * Wall shelf — U-channel настінна полиця.
 *
 * 3 сегменти, 2 гиби в одну сторону (U-профіль):
 *
 *   ──────┐  ← top of back
 *         │
 *    back │  ← вертикальна стінка з mounting holes
 *         │
 *         └──────────┐  ← bend 1 (back → shelf)
 *            shelf   │
 *                    │  ← bend 2 (shelf → lip)
 *                    │  ← front_lip (containment edge)
 *
 * front_lip_mm = 0 → 2 сегменти, 1 гиб (вироджена форма ≈ L-полиця).
 * front_lip_mm ≥ 5 → повноцінний U-channel.
 *
 * Контракт {0, [5..100]} реалізовано як plain number range + refine,
 * щоб AutoForm бачив число-поле, а cross-field constraint підіймався
 * на zod issues.
 */
import { z } from "zod";

import { BendSpecSchema } from "./bends.js";

/**
 * Plain ZodObject — споживається у `ExportRequestSchema.discriminatedUnion`,
 * який вимагає ZodObject members (а не ZodEffects від refine).
 */
export const WallShelfParametersBaseSchema = z.object({
  /** Висота вертикальної back-стінки (на стіні), мм. */
  back_height_mm: z
    .number()
    .min(30)
    .max(500)
    .describe("group:Задня полиця|label:Висота back-стінки (мм)"),
  /** Глибина горизонтальної shelf-площини, мм. */
  shelf_depth_mm: z.number().min(50).max(500).describe("group:Полиця|label:Глибина полиці (мм)"),
  /**
   * Висота переднього лопику, мм. Допустимі значення: 0 (без lip)
   * АБО проміжок [5, 100]. Cross-field constraint у refine нижче.
   */
  front_lip_mm: z
    .number()
    .min(0)
    .max(100)
    .describe("group:Фронт-губка|label:Висота губки (0 або ≥5 мм)"),
  bend_radius_mm: z
    .union([z.literal(1), z.literal(2.5), z.literal(4), z.literal(5)])
    .describe("group:Гиби|label:Внутрішній радіус (мм)"),
  bend_angle_deg: z.literal(90).describe("group:Гиби|label:Кут гиба (°)"),
  /**
   * Напрям згину на кожен гиб (Hotfix 2.10.e). 1 або 2 гиби залежно від
   * front_lip. Дефолт обидва 'down'. bends[0] — back→shelf, bends[1] — shelf→lip.
   */
  bends: z
    .array(BendSpecSchema)
    .min(1)
    .max(2)
    .default([{ direction: "down" }, { direction: "down" }])
    .describe("group:Гиби|label:Напрями згину"),
  width_mm: z
    .number()
    .min(100)
    .max(3000)
    .describe("group:Загальне|label:Ширина (довжина гиба, мм)"),
  mount_hole_diameter_mm: z
    .number()
    .min(3)
    .max(20)
    .describe("group:Отвори монтажу|label:Діаметр (мм)"),
  mount_hole_rows: z.number().int().min(0).max(5).describe("group:Отвори монтажу|label:Рядів"),
  mount_hole_cols: z.number().int().min(0).max(5).describe("group:Отвори монтажу|label:Колонок"),
  mount_hole_margin_mm: z
    .number()
    .min(5)
    .max(50)
    .describe("group:Отвори монтажу|label:Відступ від країв (мм)"),
});

/**
 * Refined schema — підкріплює "lip=0 або lip≥5" як zod-issue
 * на полі `front_lip_mm`. Використовується редактором/UI.
 */
export const WallShelfParametersSchema = WallShelfParametersBaseSchema.refine(
  (v) => v.front_lip_mm === 0 || v.front_lip_mm >= 5,
  {
    path: ["front_lip_mm"],
    message: "front_lip_mm має бути 0 (без lip) або ≥5 мм",
  },
);

export type WallShelfParameters = z.infer<typeof WallShelfParametersSchema>;

export const WALL_SHELF_DEFAULT_PARAMETERS: WallShelfParameters = {
  back_height_mm: 80,
  shelf_depth_mm: 150,
  front_lip_mm: 20,
  bend_radius_mm: 2.5,
  bend_angle_deg: 90,
  bends: [{ direction: "down" }, { direction: "down" }],
  width_mm: 300,
  mount_hole_diameter_mm: 6,
  mount_hole_rows: 2,
  mount_hole_cols: 2,
  mount_hole_margin_mm: 15,
};
