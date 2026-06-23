/**
 * Perforated panel square — плоский лист з grid квадратних отворів.
 * Phase 3.0 PR 5 (ADR-027 Рішення 6): окремий шаблон, не extension
 * perforated_panel.
 *
 * Геометрично identical до perforated_panel, але:
 * - `hole_size_mm` = side length квадратного отвору (eq. до hole_diameter_mm).
 * - DXF емітить LWPOLYLINE 4 vertices замість CIRCLE.
 * - PDF callout '□' замість 'Ø'.
 */
import { z } from "zod";

export const PerforatedPanelSquareParametersSchema = z.object({
  /** Довжина листа, мм. */
  length_mm: z.number().min(100).max(3000).describe("group:Розміри|label:Довжина листа (мм)"),
  /** Ширина листа, мм. */
  width_mm: z.number().min(100).max(3000).describe("group:Розміри|label:Ширина листа (мм)"),
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
});

export type PerforatedPanelSquareParameters = z.infer<typeof PerforatedPanelSquareParametersSchema>;

export const PERFORATED_PANEL_SQUARE_DEFAULT_PARAMETERS: PerforatedPanelSquareParameters = {
  length_mm: 200,
  width_mm: 150,
  hole_size_mm: 8,
  pitch_x_mm: 25,
  pitch_y_mm: 25,
  margin_mm: 15,
};
