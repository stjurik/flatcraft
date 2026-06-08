import { describe, expect, it } from "vitest";

import { loadSpecFromFile } from "../spec-node.js";
import { validateHoles } from "./holes.js";

const spec = await loadSpecFromFile();

describe("validateHoles", () => {
  it("happy path: cold rolled 2мм, R=2.5, отвір на 7мм від гиба", () => {
    // min distance = 2.0 * 2.0 + 2.5 = 6.5 → 7 OK.
    const result = validateHoles(
      {
        materialCode: "cold_rolled_steel",
        thicknessMm: 2.0,
        innerRadiusMm: 2.5,
        holes: [{ distanceFromBendMm: 7, diameterMm: 5 }],
      },
      spec,
    );
    expect(result.valid).toBe(true);
  });

  it("відхиляє отвір ближче за мінімальну відстань", () => {
    // cold rolled, t=2.0, R=2.5: min = 2.0*2.0 + 2.5 = 6.5. distance=5 → invalid.
    const result = validateHoles(
      {
        materialCode: "cold_rolled_steel",
        thicknessMm: 2.0,
        innerRadiusMm: 2.5,
        holes: [{ distanceFromBendMm: 5, diameterMm: 5 }],
      },
      spec,
    );
    expect(result.valid).toBe(false);
    if (!result.valid) {
      expect(result.errors[0]?.code).toBe("holes.too_close_to_bend");
      expect(result.errors[0]?.fields[0]).toMatch(/holes\[0\]\.distanceFromBendMm/);
    }
  });

  it("aluminum_5754: коефіцієнт 1.5 → меншу відстань допустимо", () => {
    // al 5754, t=2.0, R=2.5: min = 1.5*2.0 + 2.5 = 5.5. distance=5.5 → OK.
    const result = validateHoles(
      {
        materialCode: "aluminum_5754",
        thicknessMm: 2.0,
        innerRadiusMm: 2.5,
        holes: [{ distanceFromBendMm: 5.5, diameterMm: 5 }],
      },
      spec,
    );
    expect(result.valid).toBe(true);
  });

  it("кілька отворів — повідомляє про кожний некоректний з його індексом", () => {
    const result = validateHoles(
      {
        materialCode: "cold_rolled_steel",
        thicknessMm: 2.0,
        innerRadiusMm: 2.5,
        holes: [
          { distanceFromBendMm: 10, diameterMm: 5 }, // OK
          { distanceFromBendMm: 3, diameterMm: 5 }, // bad
          { distanceFromBendMm: 4, diameterMm: 5 }, // bad
        ],
      },
      spec,
    );
    expect(result.valid).toBe(false);
    if (!result.valid) {
      expect(result.errors).toHaveLength(2);
      expect(result.errors[0]?.fields).toEqual(["holes[1].distanceFromBendMm"]);
      expect(result.errors[1]?.fields).toEqual(["holes[2].distanceFromBendMm"]);
    }
  });

  it("кидає на невідомому матеріалі (відсутній coefficient)", () => {
    const result = validateHoles(
      {
        materialCode: "unobtanium",
        thicknessMm: 2.0,
        innerRadiusMm: 2.5,
        holes: [{ distanceFromBendMm: 100, diameterMm: 5 }],
      },
      spec,
    );
    expect(result.valid).toBe(false);
    if (!result.valid) {
      expect(result.errors[0]?.code).toBe("holes.material_coefficient_missing");
    }
  });

  it("порожній список отворів — valid", () => {
    const result = validateHoles(
      {
        materialCode: "cold_rolled_steel",
        thicknessMm: 2.0,
        innerRadiusMm: 2.5,
        holes: [],
      },
      spec,
    );
    expect(result.valid).toBe(true);
  });
});
