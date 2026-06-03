import { describe, expect, it } from "vitest";

import { CORNER_ANGLE_DEFAULT_PARAMETERS, CornerAngleParametersSchema } from "./corner-angle.js";

describe("CornerAngleParametersSchema", () => {
  it("приймає дефолтні параметри", () => {
    expect(() => CornerAngleParametersSchema.parse(CORNER_ANGLE_DEFAULT_PARAMETERS)).not.toThrow();
  });

  it("дефолтні значення у межах spec", () => {
    expect(CORNER_ANGLE_DEFAULT_PARAMETERS.legA_mm).toBeGreaterThanOrEqual(20);
    expect(CORNER_ANGLE_DEFAULT_PARAMETERS.hole_rows).toBeGreaterThanOrEqual(1);
    expect(CORNER_ANGLE_DEFAULT_PARAMETERS.hole_cols).toBeGreaterThanOrEqual(1);
    expect(CORNER_ANGLE_DEFAULT_PARAMETERS.bend_angle_deg).toBe(90);
  });

  it("відхиляє legA < 20", () => {
    expect(() =>
      CornerAngleParametersSchema.parse({
        ...CORNER_ANGLE_DEFAULT_PARAMETERS,
        legA_mm: 10,
      }),
    ).toThrow();
  });

  it("відхиляє hole_rows як non-integer", () => {
    expect(() =>
      CornerAngleParametersSchema.parse({
        ...CORNER_ANGLE_DEFAULT_PARAMETERS,
        hole_rows: 1.5,
      }),
    ).toThrow();
  });

  it("відхиляє hole_cols > 5", () => {
    expect(() =>
      CornerAngleParametersSchema.parse({
        ...CORNER_ANGLE_DEFAULT_PARAMETERS,
        hole_cols: 6,
      }),
    ).toThrow();
  });

  it("приймає тільки радіуси {1, 2.5, 4, 5}", () => {
    for (const r of [1, 2.5, 4, 5] as const) {
      expect(() =>
        CornerAngleParametersSchema.parse({
          ...CORNER_ANGLE_DEFAULT_PARAMETERS,
          bend_radius_mm: r,
        }),
      ).not.toThrow();
    }
    expect(() =>
      CornerAngleParametersSchema.parse({
        ...CORNER_ANGLE_DEFAULT_PARAMETERS,
        bend_radius_mm: 3,
      }),
    ).toThrow();
  });

  it("відхиляє hole_diameter < 3", () => {
    expect(() =>
      CornerAngleParametersSchema.parse({
        ...CORNER_ANGLE_DEFAULT_PARAMETERS,
        hole_diameter_mm: 2,
      }),
    ).toThrow();
  });

  it("приймає hole_rows = 0 (без отворів)", () => {
    expect(() =>
      CornerAngleParametersSchema.parse({
        ...CORNER_ANGLE_DEFAULT_PARAMETERS,
        hole_rows: 0,
      }),
    ).not.toThrow();
  });

  it("відхиляє hole_rows < 0", () => {
    expect(() =>
      CornerAngleParametersSchema.parse({
        ...CORNER_ANGLE_DEFAULT_PARAMETERS,
        hole_rows: -1,
      }),
    ).toThrow();
  });

  it("відхиляє hole_margin > 50", () => {
    expect(() =>
      CornerAngleParametersSchema.parse({
        ...CORNER_ANGLE_DEFAULT_PARAMETERS,
        hole_margin_mm: 60,
      }),
    ).toThrow();
  });

  it("bend_direction: дефолт 'down', приймає 'up', відхиляє інше (Hotfix 2.10.e)", () => {
    const { bend_direction: _omit, ...withoutDir } = CORNER_ANGLE_DEFAULT_PARAMETERS;
    expect(CornerAngleParametersSchema.parse(withoutDir).bend_direction).toBe("down");
    expect(
      CornerAngleParametersSchema.parse({
        ...CORNER_ANGLE_DEFAULT_PARAMETERS,
        bend_direction: "up",
      }).bend_direction,
    ).toBe("up");
    expect(() =>
      CornerAngleParametersSchema.parse({
        ...CORNER_ANGLE_DEFAULT_PARAMETERS,
        bend_direction: "nope",
      }),
    ).toThrow();
  });
});
