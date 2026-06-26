/**
 * Тести уніфікованої Zod-схеми perforated_panel (ADR-031): ребриста монтажна
 * панель з параметром форми отвору (circle|square). Злиті кейси з колишніх
 * perforated_panel (круглий) і perforated_panel_square (квадратний).
 */
import { describe, expect, it } from "vitest";

import {
  PERFORATED_PANEL_DEFAULT_PARAMETERS,
  PerforatedPanelParametersSchema,
} from "./perforated-panel.js";

describe("PerforatedPanelParametersSchema", () => {
  it("приймає дефолтні параметри", () => {
    expect(() =>
      PerforatedPanelParametersSchema.parse(PERFORATED_PANEL_DEFAULT_PARAMETERS),
    ).not.toThrow();
  });

  it("приймає обидві форми отвору", () => {
    for (const hole_shape of ["circle", "square"] as const) {
      const parsed = PerforatedPanelParametersSchema.safeParse({
        ...PERFORATED_PANEL_DEFAULT_PARAMETERS,
        hole_shape,
      });
      expect(parsed.success).toBe(true);
    }
  });

  it("відхиляє невідому форму отвору", () => {
    const parsed = PerforatedPanelParametersSchema.safeParse({
      ...PERFORATED_PANEL_DEFAULT_PARAMETERS,
      hole_shape: "hex",
    });
    expect(parsed.success).toBe(false);
  });

  it("дефолти у межах spec", () => {
    expect(PERFORATED_PANEL_DEFAULT_PARAMETERS.length_mm).toBeGreaterThanOrEqual(100);
    expect(PERFORATED_PANEL_DEFAULT_PARAMETERS.hole_size_mm).toBeGreaterThanOrEqual(3);
    expect(PERFORATED_PANEL_DEFAULT_PARAMETERS.pitch_x_mm).toBeGreaterThanOrEqual(10);
    expect(PERFORATED_PANEL_DEFAULT_PARAMETERS.rib_height_mm).toBeGreaterThanOrEqual(15);
  });

  it("length < 100 відхиляє", () => {
    expect(
      PerforatedPanelParametersSchema.safeParse({
        ...PERFORATED_PANEL_DEFAULT_PARAMETERS,
        length_mm: 50,
      }).success,
    ).toBe(false);
  });

  it("hole_size поза 3–30 відхиляє", () => {
    for (const hole_size_mm of [1, 40]) {
      expect(
        PerforatedPanelParametersSchema.safeParse({
          ...PERFORATED_PANEL_DEFAULT_PARAMETERS,
          hole_size_mm,
        }).success,
      ).toBe(false);
    }
  });

  it("pitch_x < 10 / pitch_y > 200 відхиляє", () => {
    expect(
      PerforatedPanelParametersSchema.safeParse({
        ...PERFORATED_PANEL_DEFAULT_PARAMETERS,
        pitch_x_mm: 5,
      }).success,
    ).toBe(false);
    expect(
      PerforatedPanelParametersSchema.safeParse({
        ...PERFORATED_PANEL_DEFAULT_PARAMETERS,
        pitch_y_mm: 250,
      }).success,
    ).toBe(false);
  });

  it("margin поза 5–100 відхиляє; margin = 5 приймає", () => {
    expect(
      PerforatedPanelParametersSchema.safeParse({
        ...PERFORATED_PANEL_DEFAULT_PARAMETERS,
        margin_mm: 150,
      }).success,
    ).toBe(false);
    expect(
      PerforatedPanelParametersSchema.safeParse({
        ...PERFORATED_PANEL_DEFAULT_PARAMETERS,
        margin_mm: 5,
      }).success,
    ).toBe(true);
  });

  it("приймає мінімальні валідні значення", () => {
    const parsed = PerforatedPanelParametersSchema.safeParse({
      length_mm: 100,
      width_mm: 100,
      hole_shape: "square",
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
      expect(
        PerforatedPanelParametersSchema.safeParse({
          ...PERFORATED_PANEL_DEFAULT_PARAMETERS,
          rib_height_mm: rib,
        }).success,
      ).toBe(false);
    }
  });

  it("вимагає rib_height (ребра обов'язкові)", () => {
    const { rib_height_mm: _omit, ...withoutRib } = PERFORATED_PANEL_DEFAULT_PARAMETERS;
    expect(PerforatedPanelParametersSchema.safeParse(withoutRib).success).toBe(false);
  });

  it("відхиляє bend_radius поза allowed set {1,2.5,4,5}", () => {
    expect(
      PerforatedPanelParametersSchema.safeParse({
        ...PERFORATED_PANEL_DEFAULT_PARAMETERS,
        bend_radius_mm: 1.7,
      }).success,
    ).toBe(false);
  });
});
