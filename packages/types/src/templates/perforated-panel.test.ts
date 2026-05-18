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

  it("дефолти у межах spec", () => {
    expect(PERFORATED_PANEL_DEFAULT_PARAMETERS.length_mm).toBeGreaterThanOrEqual(100);
    expect(PERFORATED_PANEL_DEFAULT_PARAMETERS.hole_diameter_mm).toBeGreaterThanOrEqual(3);
    expect(PERFORATED_PANEL_DEFAULT_PARAMETERS.pitch_x_mm).toBeGreaterThanOrEqual(10);
  });

  it("length < 100 відхиляє", () => {
    expect(() =>
      PerforatedPanelParametersSchema.parse({
        ...PERFORATED_PANEL_DEFAULT_PARAMETERS,
        length_mm: 50,
      }),
    ).toThrow();
  });

  it("hole_diameter > 30 відхиляє", () => {
    expect(() =>
      PerforatedPanelParametersSchema.parse({
        ...PERFORATED_PANEL_DEFAULT_PARAMETERS,
        hole_diameter_mm: 40,
      }),
    ).toThrow();
  });

  it("pitch_x < 10 відхиляє", () => {
    expect(() =>
      PerforatedPanelParametersSchema.parse({
        ...PERFORATED_PANEL_DEFAULT_PARAMETERS,
        pitch_x_mm: 5,
      }),
    ).toThrow();
  });

  it("pitch_y > 200 відхиляє", () => {
    expect(() =>
      PerforatedPanelParametersSchema.parse({
        ...PERFORATED_PANEL_DEFAULT_PARAMETERS,
        pitch_y_mm: 250,
      }),
    ).toThrow();
  });

  it("margin > 100 відхиляє", () => {
    expect(() =>
      PerforatedPanelParametersSchema.parse({
        ...PERFORATED_PANEL_DEFAULT_PARAMETERS,
        margin_mm: 150,
      }),
    ).toThrow();
  });

  it("margin = 5 (мін.) приймає", () => {
    expect(() =>
      PerforatedPanelParametersSchema.parse({
        ...PERFORATED_PANEL_DEFAULT_PARAMETERS,
        margin_mm: 5,
      }),
    ).not.toThrow();
  });
});
