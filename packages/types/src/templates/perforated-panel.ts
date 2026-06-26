/**
 * Перфорована МОНТАЖНА панель — ОДИН параметричний шаблон (ADR-031).
 *
 * Раніше було два окремих шаблони (`perforated_panel` круглий-плоский +
 * `perforated_panel_square` квадратний-ребристий) з клієнтським toggle-shim
 * (ADR-029) та асиметрією ADR-030. ADR-031 уніфікує: **один** ребристий лоток,
 * де форма отвору — звичайний параметр `hole_shape` (circle|square). Обидва
 * варіанти ідентичні в усьому, крім геометрії перфо-отвору.
 *
 * Геометрія — гнутий лоток: центральна перфо-площина length×width (між лініями
 * гибу), 4 фланці 90° (ребра жорсткості, висота `rib_height_mm`), 4 кутові
 * установочні отвори Ø5.5. Розгортка — хрест/плюс (деталі — unfold.py).
 *
 * - `hole_shape` = форма перфо-отвору: circle (Ø) або square (□).
 * - `hole_size_mm` = розмір отвору: діаметр (circle) або сторона (square).
 * - `rib_height_mm` = висота ребра (15–50), однакова на 4 сторони (обов'язкове).
 * - `bend_radius_mm` = внутрішній радіус гибу ребер (allowed set).
 * - Скруглення кутів ребер (R5), inset установочних отворів (12мм), Ø5.5 —
 *   фіксовані константи воркера (не у формі).
 */
import { z } from "zod";

export const HOLE_SHAPES = ["circle", "square"] as const;
export type HoleShape = (typeof HOLE_SHAPES)[number];

export const PerforatedPanelParametersSchema = z.object({
  /** Довжина перфо-площини (між лініями гибу), мм. */
  length_mm: z.number().min(100).max(3000).describe("group:Розміри|label:Довжина площини (мм)"),
  /** Ширина перфо-площини (між лініями гибу), мм. */
  width_mm: z.number().min(100).max(3000).describe("group:Розміри|label:Ширина площини (мм)"),
  /** Форма перфо-отвору: круг (діаметр) або квадрат (сторона). */
  hole_shape: z
    .enum(HOLE_SHAPES)
    .describe("group:Сітка отворів|label:Форма отвору|enum:circle=Круг,square=Квадрат"),
  /** Розмір отвору, мм: діаметр (circle) або сторона квадрата (square). */
  hole_size_mm: z.number().min(3).max(30).describe("group:Сітка отворів|label:Розмір отвору (мм)"),
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
  /** Висота ребра жорсткості (фланця) після гибу, мм. Обов'язкове (ADR-030/031). */
  rib_height_mm: z
    .number()
    .min(15)
    .max(50)
    .describe("group:Ребра жорсткості|label:Висота ребра (мм)"),
  /** Внутрішній радіус гибу ребер, мм (allowed set за bend-machine spec). */
  bend_radius_mm: z
    .union([z.literal(1), z.literal(2.5), z.literal(4), z.literal(5)])
    .describe("group:Ребра жорсткості|label:Радіус гибу (мм)"),
  /** Кут гибу ребер — MVP лише 90°. */
  bend_angle_deg: z.literal(90).describe("group:Ребра жорсткості|label:Кут гибу (°)"),
});

export type PerforatedPanelParameters = z.infer<typeof PerforatedPanelParametersSchema>;

export const PERFORATED_PANEL_DEFAULT_PARAMETERS: PerforatedPanelParameters = {
  length_mm: 200,
  width_mm: 150,
  hole_shape: "square",
  hole_size_mm: 8,
  pitch_x_mm: 25,
  pitch_y_mm: 25,
  margin_mm: 15,
  rib_height_mm: 30,
  bend_radius_mm: 2.5,
  bend_angle_deg: 90,
};
