/**
 * Perforated panel — плоский лист з сіткою отворів.
 *
 * Принципово відрізняється від решти Phase 2.10 шаблонів: НЕ має гибів.
 * Тільки laser-cut з grid'ом отворів за заданим кроком (pitch).
 *
 *   ┌──────────────────────┐
 *   │  ●   ●   ●   ●   ●   │
 *   │  ●   ●   ●   ●   ●   │  ← pitch_x між колонками, pitch_y між рядами
 *   │  ●   ●   ●   ●   ●   │
 *   └──────────────────────┘
 *
 * Layout — індустріальна конвенція pitch (центр-в-центр), grid
 * автоматично центрується між margin'ами країв. Користувач не задає
 * count — він обчислюється з length/width/pitch/margin.
 */
import { z } from "zod";

export const PerforatedPanelParametersSchema = z.object({
  /** Довжина листа, мм. */
  length_mm: z.number().min(100).max(3000).describe("group:Розміри|label:Довжина листа (мм)"),
  /** Ширина листа, мм. */
  width_mm: z.number().min(100).max(3000).describe("group:Розміри|label:Ширина листа (мм)"),
  /** Діаметр отворів, мм. */
  hole_diameter_mm: z
    .number()
    .min(3)
    .max(30)
    .describe("group:Сітка отворів|label:Діаметр отворів (мм)"),
  /** Крок між центрами отворів вздовж довжини, мм. */
  pitch_x_mm: z.number().min(10).max(200).describe("group:Сітка отворів|label:Крок X (мм)"),
  /** Крок між центрами отворів вздовж ширини, мм. */
  pitch_y_mm: z.number().min(10).max(200).describe("group:Сітка отворів|label:Крок Y (мм)"),
  /** Мінімальний відступ від країв до центра крайнього отвору, мм. */
  margin_mm: z
    .number()
    .min(5)
    .max(100)
    .describe("group:Сітка отворів|label:Відступ від країв (мм)"),
});

export type PerforatedPanelParameters = z.infer<typeof PerforatedPanelParametersSchema>;

export const PERFORATED_PANEL_DEFAULT_PARAMETERS: PerforatedPanelParameters = {
  length_mm: 200,
  width_mm: 150,
  hole_diameter_mm: 8,
  pitch_x_mm: 20,
  pitch_y_mm: 20,
  margin_mm: 15,
};
