import { describe, expect, it } from "vitest";

import { L_BRACKET_DEFAULT_PARAMETERS, LBracketParametersSchema } from "./l-bracket.js";

describe("LBracketParametersSchema", () => {
  it("приймає дефолтні параметри", () => {
    expect(() => LBracketParametersSchema.parse(L_BRACKET_DEFAULT_PARAMETERS)).not.toThrow();
  });

  it("дефолтні значення у межах spec", () => {
    expect(L_BRACKET_DEFAULT_PARAMETERS.legA_mm).toBeGreaterThanOrEqual(20);
    expect(L_BRACKET_DEFAULT_PARAMETERS.legA_mm).toBeLessThanOrEqual(500);
    expect(L_BRACKET_DEFAULT_PARAMETERS.bend_angle_deg).toBe(90);
  });

  it("відхиляє legA < 20мм", () => {
    expect(() =>
      LBracketParametersSchema.parse({
        ...L_BRACKET_DEFAULT_PARAMETERS,
        legA_mm: 10,
      }),
    ).toThrow();
  });

  it("відхиляє legB > 500мм", () => {
    expect(() =>
      LBracketParametersSchema.parse({
        ...L_BRACKET_DEFAULT_PARAMETERS,
        legB_mm: 600,
      }),
    ).toThrow();
  });

  it("приймає лише радіуси {1, 2.5, 4, 5}", () => {
    for (const r of [1, 2.5, 4, 5] as const) {
      expect(() =>
        LBracketParametersSchema.parse({
          ...L_BRACKET_DEFAULT_PARAMETERS,
          bend_radius_mm: r,
        }),
      ).not.toThrow();
    }
    expect(() =>
      LBracketParametersSchema.parse({
        ...L_BRACKET_DEFAULT_PARAMETERS,
        bend_radius_mm: 3,
      }),
    ).toThrow();
  });

  it("MVP: тільки 90° гиб", () => {
    expect(() =>
      LBracketParametersSchema.parse({
        ...L_BRACKET_DEFAULT_PARAMETERS,
        bend_angle_deg: 60,
      }),
    ).toThrow();
  });

  it("приймає до 20 отворів, відхиляє 21", () => {
    const hole = {
      leg: "A" as const,
      distance_from_edge_mm: 10,
      distance_from_bend_mm: 10,
      diameter_mm: 5,
    };
    expect(() =>
      LBracketParametersSchema.parse({
        ...L_BRACKET_DEFAULT_PARAMETERS,
        holes: Array.from({ length: 20 }, () => hole),
      }),
    ).not.toThrow();
    expect(() =>
      LBracketParametersSchema.parse({
        ...L_BRACKET_DEFAULT_PARAMETERS,
        holes: Array.from({ length: 21 }, () => hole),
      }),
    ).toThrow();
  });

  it("bend_direction: дефолт 'down' коли відсутній (Hotfix 2.10.e)", () => {
    const { bend_direction: _omit, ...withoutDir } = L_BRACKET_DEFAULT_PARAMETERS;
    const parsed = LBracketParametersSchema.parse(withoutDir);
    expect(parsed.bend_direction).toBe("down");
  });

  it("bend_direction: приймає 'up', відхиляє інше", () => {
    expect(
      LBracketParametersSchema.parse({ ...L_BRACKET_DEFAULT_PARAMETERS, bend_direction: "up" })
        .bend_direction,
    ).toBe("up");
    expect(() =>
      LBracketParametersSchema.parse({
        ...L_BRACKET_DEFAULT_PARAMETERS,
        bend_direction: "sideways",
      }),
    ).toThrow();
  });

  it("отвір: leg тільки A або B", () => {
    expect(() =>
      LBracketParametersSchema.parse({
        ...L_BRACKET_DEFAULT_PARAMETERS,
        holes: [
          {
            leg: "C",
            distance_from_edge_mm: 10,
            distance_from_bend_mm: 10,
            diameter_mm: 5,
          },
        ],
      }),
    ).toThrow();
  });

  it("отвір: діаметр у [2, 50]", () => {
    expect(() =>
      LBracketParametersSchema.parse({
        ...L_BRACKET_DEFAULT_PARAMETERS,
        holes: [
          {
            leg: "A",
            distance_from_edge_mm: 10,
            distance_from_bend_mm: 10,
            diameter_mm: 1,
          },
        ],
      }),
    ).toThrow();
    expect(() =>
      LBracketParametersSchema.parse({
        ...L_BRACKET_DEFAULT_PARAMETERS,
        holes: [
          {
            leg: "A",
            distance_from_edge_mm: 10,
            distance_from_bend_mm: 10,
            diameter_mm: 60,
          },
        ],
      }),
    ).toThrow();
  });
});
