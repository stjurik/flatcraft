/**
 * Enclosed shelf — настінна полиця з 4-сторонньою cross-розгорткою
 * (Phase 3.0 PR 7, ADR-027).
 *
 * Геометрія:
 *
 *                ┌──────────────┐
 *                │              │
 *                │     BACK     │  висота = depth_mm (квадратна стінка)
 *                │              │
 *   ┌────────────┼──────────────┼────────────┐
 *   │  LEFT      │              │   RIGHT    │
 *   │ (depth ×   │   BOTTOM     │  depth ×   │  бокові стінки — квадрати depth × depth
 *   │  depth)    │ (width ×     │  depth)    │
 *   │            │  depth)      │            │
 *   └────────────┼──────────────┼────────────┘
 *                │ FRONT_RIB?   │  опційне 5-те ребро
 *                └──────────────┘
 *
 * Cross-розгортка означає 3-4 bend lines уздовж 2 осей (back+rib — уздовж X,
 * sides — уздовж Y). На відміну від wall_shelf/l_bracket з лінійним 1D unfold,
 * unfold для enclosed_shelf 2D — UnfoldedEnclosedShelf зберігає координати
 * кожного сегменту окремо (`bend_lines: tuple[BendLine2D, ...]`). Реалізація
 * unfold + builder + DXF/PDF — PR 7b/7c.
 *
 * Параметри:
 *   - width_mm: довжина полиці (= ширина bottom). 300-1000, крок 10.
 *   - depth_mm: глибина полиці (= висота back AND розмір кожної боковини).
 *     100-300, крок 10. Квадратні бокові — інваріант (`side_w = side_h = depth_mm`).
 *
 * Опційні features:
 *   - side_perforation: декоративні квадратні отвори на боковинах
 *     (як perforated_panel_square — той же grid, але на 2 окремих площинах).
 *   - stiffening_rib: ребро жорсткості на front edge bottom — мала смужка,
 *     що згинається UP. Прибирає прогин полиці у середині.
 */
import { z } from "zod";

/**
 * Напрям гибу enclosed_shelf — лише 'up' (issue #237 п.1, рішення yurii
 * 2026-10-14 «3а»). На відміну від інших multi-bend шаблонів (`BendSpecSchema`
 * у `./bends.js`, up/down) закрита полиця фізично гнеться лише вгору — `down`
 * дав би дзеркальну, нежиттєздатну деталь, а PDF усе одно пише «UP (усі)»
 * (export/pdf.py), тож `down` на вході — брехня на кресленні. Власна схема,
 * не розширення `BendSpecSchema`, — щоб інші шаблони (wall_shelf, z_bracket)
 * лишались у стані up/down без змін.
 */
export const EnclosedShelfBendSpecSchema = z.object({
  direction: z
    .literal("up", {
      // zod ігнорує `message` для invalid_literal (лише invalid_type/invalid_enum_value) —
      // тому дружнє повідомлення йде через errorMap, не через `message`.
      errorMap: () => ({
        message:
          "Закрита полиця (enclosed_shelf) гнеться лише вгору — напрям гибу може бути тільки 'up'.",
      }),
    })
    .default("up")
    .describe("group:Гиб|label:Напрям згину"),
});
export type EnclosedShelfBendSpec = z.infer<typeof EnclosedShelfBendSpecSchema>;

/**
 * Опційна декоративна перфорація бокових стінок. Якщо `null` — без отворів.
 * Геометрія сітки повторює perforated_panel_square (4-vertex LWPOLYLINE).
 */
export const EnclosedShelfSidePerforationSchema = z.object({
  hole_size_mm: z.number().min(3).max(20).describe("group:Перфорація сторін|label:Сторона □ (мм)"),
  pitch_x_mm: z.number().min(10).max(100).describe("group:Перфорація сторін|label:Pitch X (мм)"),
  pitch_y_mm: z.number().min(10).max(100).describe("group:Перфорація сторін|label:Pitch Y (мм)"),
  margin_mm: z
    .number()
    .min(5)
    .max(50)
    .describe("group:Перфорація сторін|label:Відступ від країв (мм)"),
});
export type EnclosedShelfSidePerforation = z.infer<typeof EnclosedShelfSidePerforationSchema>;

/**
 * Опційне ребро жорсткості — front lip bottom (UP-bend).
 * `height_mm` — висота ребра після гибу.
 */
export const EnclosedShelfStiffeningRibSchema = z.object({
  height_mm: z.number().min(5).max(50).describe("group:Ребро жорсткості|label:Висота ребра (мм)"),
});
export type EnclosedShelfStiffeningRib = z.infer<typeof EnclosedShelfStiffeningRibSchema>;

export const EnclosedShelfParametersSchema = z.object({
  /** Довжина полиці (= ширина bottom). 300-1000 мм, крок 10. */
  width_mm: z.number().min(300).max(1000).describe("group:Розміри|label:Ширина полиці (мм)"),
  /**
   * Глибина полиці. Одночасно: висота back, ширина/висота квадратних боковин.
   * 100-300 мм, крок 10.
   */
  depth_mm: z
    .number()
    .min(100)
    .max(300)
    .describe("group:Розміри|label:Глибина (= висота back, мм)"),
  bend_radius_mm: z
    .union([z.literal(1), z.literal(2.5), z.literal(4), z.literal(5)])
    .describe("group:Гиб|label:Внутрішній радіус (мм)"),
  bend_angle_deg: z.literal(90).describe("group:Гиб|label:Кут гиба (°)"),
  /**
   * Напрям згину на кожен з 3-4 гибів: [back, left, right, rib?].
   * Лише 'up' (issue #237 п.1) — дефолт і єдине дозволене значення.
   */
  bends: z
    .array(EnclosedShelfBendSpecSchema)
    .min(3)
    .max(4)
    .default([{ direction: "up" }, { direction: "up" }, { direction: "up" }, { direction: "up" }])
    .describe("group:Гиб|label:Напрями згину (back/left/right/rib)"),
  side_perforation: EnclosedShelfSidePerforationSchema.nullable()
    .default(null)
    .describe("group:Перфорація сторін|label:Декоративна перфорація"),
  stiffening_rib: EnclosedShelfStiffeningRibSchema.nullable()
    .default(null)
    .describe("group:Ребро жорсткості|label:Ребро жорсткості"),
});

export type EnclosedShelfParameters = z.infer<typeof EnclosedShelfParametersSchema>;

export const ENCLOSED_SHELF_DEFAULT_PARAMETERS: EnclosedShelfParameters = {
  width_mm: 600,
  depth_mm: 200,
  bend_radius_mm: 2.5,
  bend_angle_deg: 90,
  bends: [{ direction: "up" }, { direction: "up" }, { direction: "up" }, { direction: "up" }],
  side_perforation: null,
  stiffening_rib: null,
};
