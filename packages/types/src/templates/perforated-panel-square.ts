/**
 * Перфорована МОНТАЖНА панель (квадратні отвори + ребра жорсткості) — ADR-030.
 *
 * Раніше plоский лист (Phase 3.0 PR 5). ADR-030 переосмислює на ГНУТИЙ ЛОТОК:
 * усі 4 сторони зміцнені ребрами (фланцями 90°), у 4 кутах площини установочні
 * отвори Ø5.5. Ребра обов'язкові (не опційні).
 *
 * - `hole_size_mm` = side length квадратного перфо-отвору.
 * - `rib_height_mm` = висота ребра (15–50), однакова на 4 сторони.
 * - `bend_radius_mm` = внутрішній радіус гибу ребер (allowed set).
 * - Скруглення кутів ребер (R5) і inset установочних отворів (12мм) — фіксовані
 *   константи воркера (не у формі); Ø5.5 — фіксований.
 */
import { z } from "zod";

export const PerforatedPanelSquareParametersSchema = z.object({
  /** Довжина перфо-площини (між лініями гибу), мм. */
  length_mm: z.number().min(100).max(3000).describe("group:Розміри|label:Довжина площини (мм)"),
  /** Ширина перфо-площини (між лініями гибу), мм. */
  width_mm: z.number().min(100).max(3000).describe("group:Розміри|label:Ширина площини (мм)"),
  /** Side length квадратного отвору, мм. */
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
  /** Висота ребра жорсткості (фланця) після гибу, мм. Обов'язкове (ADR-030). */
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

export type PerforatedPanelSquareParameters = z.infer<typeof PerforatedPanelSquareParametersSchema>;

export const PERFORATED_PANEL_SQUARE_DEFAULT_PARAMETERS: PerforatedPanelSquareParameters = {
  length_mm: 200,
  width_mm: 150,
  hole_size_mm: 8,
  pitch_x_mm: 25,
  pitch_y_mm: 25,
  margin_mm: 15,
  rib_height_mm: 30,
  bend_radius_mm: 2.5,
  bend_angle_deg: 90,
};
