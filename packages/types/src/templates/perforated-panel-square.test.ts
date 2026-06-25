/**
 * Тести Zod-схеми perforated_panel_square (Phase 3.0 PR 5, ADR-027 Рішення 6).
 */
import { describe, expect, it } from "vitest";

import {
  PERFORATED_PANEL_SQUARE_DEFAULT_PARAMETERS,
  PerforatedPanelSquareParametersSchema,
} from "./perforated-panel-square.js";

describe("PerforatedPanelSquareParametersSchema", () => {
  it("приймає default-значення", () => {
    const parsed = PerforatedPanelSquareParametersSchema.safeParse(
      PERFORATED_PANEL_SQUARE_DEFAULT_PARAMETERS,
    );
    expect(parsed.success).toBe(true);
  });

  it("відхиляє hole_size_mm > 30", () => {
    const parsed = PerforatedPanelSquareParametersSchema.safeParse({
      ...PERFORATED_PANEL_SQUARE_DEFAULT_PARAMETERS,
      hole_size_mm: 50,
    });
    expect(parsed.success).toBe(false);
  });

  it("відхиляє hole_size_mm < 3", () => {
    const parsed = PerforatedPanelSquareParametersSchema.safeParse({
      ...PERFORATED_PANEL_SQUARE_DEFAULT_PARAMETERS,
      hole_size_mm: 1,
    });
    expect(parsed.success).toBe(false);
  });

  it("приймає мінімальні валідні значення", () => {
    const parsed = PerforatedPanelSquareParametersSchema.safeParse({
      length_mm: 100,
      width_mm: 100,
      hole_size_mm: 3,
      pitch_x_mm: 10,
      pitch_y_mm: 10,
      margin_mm: 5,
      rib_height_mm: 15,
      bend_radius_mm: 1,
      bend_angle_deg: 90,
    });
    expect(parsed.success).toBe(true);
  });

  it("відхиляє rib_height поза 15–50 (ADR-030)", () => {
    for (const rib of [10, 60]) {
      const parsed = PerforatedPanelSquareParametersSchema.safeParse({
        ...PERFORATED_PANEL_SQUARE_DEFAULT_PARAMETERS,
        rib_height_mm: rib,
      });
      expect(parsed.success).toBe(false);
    }
  });

  it("відхиляє bend_radius поза allowed set {1,2.5,4,5}", () => {
    const parsed = PerforatedPanelSquareParametersSchema.safeParse({
      ...PERFORATED_PANEL_SQUARE_DEFAULT_PARAMETERS,
      bend_radius_mm: 1.7,
    });
    expect(parsed.success).toBe(false);
  });

  it("вимагає rib_height (ребра обов'язкові)", () => {
    const { rib_height_mm: _omit, ...withoutRib } = PERFORATED_PANEL_SQUARE_DEFAULT_PARAMETERS;
    const parsed = PerforatedPanelSquareParametersSchema.safeParse(withoutRib);
    expect(parsed.success).toBe(false);
  });

  it("відхиляє від'ємні значення", () => {
    const parsed = PerforatedPanelSquareParametersSchema.safeParse({
      length_mm: -100,
      width_mm: 150,
      hole_size_mm: 8,
      pitch_x_mm: 20,
      pitch_y_mm: 20,
      margin_mm: 15,
    });
    expect(parsed.success).toBe(false);
  });

  it("default містить очікувані поля", () => {
    expect(PERFORATED_PANEL_SQUARE_DEFAULT_PARAMETERS.hole_size_mm).toBe(8);
    expect(PERFORATED_PANEL_SQUARE_DEFAULT_PARAMETERS.length_mm).toBe(200);
    expect(PERFORATED_PANEL_SQUARE_DEFAULT_PARAMETERS.width_mm).toBe(150);
  });
});
