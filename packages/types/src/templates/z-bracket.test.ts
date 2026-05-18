import { describe, expect, it } from "vitest";

import { Z_BRACKET_DEFAULT_PARAMETERS, ZBracketParametersSchema } from "./z-bracket.js";

describe("ZBracketParametersSchema", () => {
  it("приймає дефолтні параметри", () => {
    expect(() => ZBracketParametersSchema.parse(Z_BRACKET_DEFAULT_PARAMETERS)).not.toThrow();
  });

  it("дефолтні значення у межах spec", () => {
    expect(Z_BRACKET_DEFAULT_PARAMETERS.top_flange_mm).toBeGreaterThanOrEqual(20);
    expect(Z_BRACKET_DEFAULT_PARAMETERS.offset_mm).toBeGreaterThanOrEqual(20);
    expect(Z_BRACKET_DEFAULT_PARAMETERS.bend_angle_deg).toBe(90);
  });

  it("відхиляє top_flange < 20", () => {
    expect(() =>
      ZBracketParametersSchema.parse({
        ...Z_BRACKET_DEFAULT_PARAMETERS,
        top_flange_mm: 10,
      }),
    ).toThrow();
  });

  it("відхиляє offset > 500", () => {
    expect(() =>
      ZBracketParametersSchema.parse({
        ...Z_BRACKET_DEFAULT_PARAMETERS,
        offset_mm: 600,
      }),
    ).toThrow();
  });

  it("приймає тільки радіуси {1, 2.5, 4, 5}", () => {
    for (const r of [1, 2.5, 4, 5] as const) {
      expect(() =>
        ZBracketParametersSchema.parse({
          ...Z_BRACKET_DEFAULT_PARAMETERS,
          bend_radius_mm: r,
        }),
      ).not.toThrow();
    }
    expect(() =>
      ZBracketParametersSchema.parse({
        ...Z_BRACKET_DEFAULT_PARAMETERS,
        bend_radius_mm: 3,
      }),
    ).toThrow();
  });

  it("отвір: segment лише T/M/B", () => {
    expect(() =>
      ZBracketParametersSchema.parse({
        ...Z_BRACKET_DEFAULT_PARAMETERS,
        holes: [
          {
            segment: "X",
            distance_from_edge_mm: 10,
            distance_from_bend_mm: 10,
            diameter_mm: 5,
          },
        ],
      }),
    ).toThrow();
  });

  it("max 20 отворів", () => {
    const hole = {
      segment: "T" as const,
      distance_from_edge_mm: 10,
      distance_from_bend_mm: 10,
      diameter_mm: 5,
    };
    expect(() =>
      ZBracketParametersSchema.parse({
        ...Z_BRACKET_DEFAULT_PARAMETERS,
        holes: Array.from({ length: 21 }, () => hole),
      }),
    ).toThrow();
  });
});
