/**
 * Corner angle — підсилювальний кутник з auto-grid отворів.
 *
 * Геометрія = L-bracket (2 полиці під 90°, 1 гиб), але hole-pattern
 * — автоматичний grid rows×cols на кожній полиці, що генерується з
 * параметрів без ручних координат. Це типовий меблевий кутник
 * "купив і прикрутив".
 *
 *   ┌──────────────────────┐  ← horizontal flange (legB_mm × width_mm)
 *   │ ●     ●     ●        │     holes: rows × cols, distributed
 *   │ ●     ●     ●        │     evenly between hole_margin_mm edges
 *   └──────────────────────┘
 *   │
 *   │ ●     ●
 *   │ ●     ●  ← vertical flange (legA_mm × width_mm)
 *   │ ●     ●
 *   │
 *   └ bend (90°)
 *
 * Кількість отворів = 2 × hole_rows × hole_cols (по один patern на полицю).
 * MVP-обмеження ті ж самі: 90°, радіус з фіксованого набору.
 */
import { z } from "zod";

export const CornerAngleParametersSchema = z.object({
  /** Висота вертикальної полиці, мм. */
  legA_mm: z.number().min(20).max(500).describe("group:Полиця A|label:Висота полиці A (мм)"),
  /** Глибина горизонтальної полиці, мм. */
  legB_mm: z.number().min(20).max(500).describe("group:Полиця B|label:Глибина полиці B (мм)"),
  /** Внутрішній радіус гиба, мм. */
  bend_radius_mm: z
    .union([z.literal(1), z.literal(2.5), z.literal(4), z.literal(5)])
    .describe("group:Гиб|label:Внутрішній радіус (мм)"),
  /** MVP: лише 90°. */
  bend_angle_deg: z.literal(90).describe("group:Гиб|label:Кут гиба (°)"),
  /** Ширина (довжина гиба), мм. */
  width_mm: z.number().min(20).max(3000).describe("group:Загальне|label:Ширина (довжина гиба, мм)"),
  /** Діаметр отворів, мм (один для всього grid). */
  hole_diameter_mm: z
    .number()
    .min(3)
    .max(20)
    .describe("group:Сітка отворів|label:Діаметр отвору (мм)"),
  /** Рядів отворів вздовж ширини (perpendicular to leg length). */
  hole_rows: z.number().int().min(0).max(5).describe("group:Сітка отворів|label:Рядів отворів"),
  /** Колонок отворів вздовж довжини полиці (parallel to leg length). */
  hole_cols: z.number().int().min(0).max(5).describe("group:Сітка отворів|label:Колонок отворів"),
  /** Мінімальна відстань від країв полиці до центра крайнього отвору, мм. */
  hole_margin_mm: z
    .number()
    .min(5)
    .max(50)
    .describe("group:Сітка отворів|label:Відступ від країв (мм)"),
});

export type CornerAngleParameters = z.infer<typeof CornerAngleParametersSchema>;

export const CORNER_ANGLE_DEFAULT_PARAMETERS: CornerAngleParameters = {
  legA_mm: 50,
  legB_mm: 50,
  bend_radius_mm: 2.5,
  bend_angle_deg: 90,
  width_mm: 80,
  hole_diameter_mm: 5,
  hole_rows: 1,
  hole_cols: 2,
  hole_margin_mm: 12,
};
