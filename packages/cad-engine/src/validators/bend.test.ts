import { describe, expect, it } from "vitest";

import { loadSpecFromFile } from "../spec.js";
import { validateBend } from "./bend.js";

const spec = await loadSpecFromFile();

describe("validateBend", () => {
  it("happy path: 2мм холоднокатана, R=2.5, 90°, полиця 20мм, гиб 200мм", () => {
    const result = validateBend(
      {
        materialCode: "cold_rolled_steel",
        thicknessMm: 2.0,
        innerRadiusMm: 2.5,
        angleDeg: 90,
        flangeMm: 20,
        bendLengthMm: 200,
      },
      spec,
    );
    expect(result.valid).toBe(true);
  });

  it("відхиляє неdозволений радіус для (товщина, матеріал)", () => {
    // Для 8мм allowed = [5.0]; R=2.5 заборонений.
    const result = validateBend(
      {
        materialCode: "cold_rolled_steel",
        thicknessMm: 8.0,
        innerRadiusMm: 2.5,
        angleDeg: 90,
        flangeMm: 30,
        bendLengthMm: 500,
      },
      spec,
    );
    expect(result.valid).toBe(false);
    if (!result.valid) {
      expect(result.errors.some((e) => e.code === "bend.inner_radius_not_allowed")).toBe(true);
    }
  });

  it("відхиляє кут не з allowed_angles_deg", () => {
    const result = validateBend(
      {
        materialCode: "cold_rolled_steel",
        thicknessMm: 2.0,
        innerRadiusMm: 2.5,
        angleDeg: 75,
        flangeMm: 20,
        bendLengthMm: 200,
      },
      spec,
    );
    expect(result.valid).toBe(false);
    if (!result.valid) {
      expect(result.errors.some((e) => e.code === "bend.angle_not_allowed")).toBe(true);
    }
  });

  it("відхиляє полицю меншу за 7.5мм (CLAUDE.md §7)", () => {
    const result = validateBend(
      {
        materialCode: "cold_rolled_steel",
        thicknessMm: 2.0,
        innerRadiusMm: 2.5,
        angleDeg: 90,
        flangeMm: 5,
        bendLengthMm: 200,
      },
      spec,
    );
    expect(result.valid).toBe(false);
    if (!result.valid) {
      expect(result.errors.some((e) => e.code === "bend.flange_too_short")).toBe(true);
    }
  });

  it("відхиляє bendLength понад max_bend_length_mm для товщини", () => {
    // 8мм → max 1000мм
    const result = validateBend(
      {
        materialCode: "cold_rolled_steel",
        thicknessMm: 8.0,
        innerRadiusMm: 5.0,
        angleDeg: 90,
        flangeMm: 30,
        bendLengthMm: 1500,
      },
      spec,
    );
    expect(result.valid).toBe(false);
    if (!result.valid) {
      expect(result.errors.some((e) => e.code === "bend.exceeds_max_bend_length")).toBe(true);
    }
  });

  it("відхиляє непідтримувану товщину гиба", () => {
    const result = validateBend(
      {
        materialCode: "cold_rolled_steel",
        thicknessMm: 7.0,
        innerRadiusMm: 4.0,
        angleDeg: 90,
        flangeMm: 30,
        bendLengthMm: 200,
      },
      spec,
    );
    expect(result.valid).toBe(false);
    if (!result.valid) {
      expect(result.errors[0]?.code).toBe("bend.thickness_unsupported");
    }
  });

  it("відхиляє нержавійку 10мм навіть з валідним кутом і радіусом", () => {
    const result = validateBend(
      {
        materialCode: "stainless_304",
        thicknessMm: 10.0,
        innerRadiusMm: 5.0,
        angleDeg: 90,
        flangeMm: 30,
        bendLengthMm: 500,
      },
      spec,
    );
    expect(result.valid).toBe(false);
    if (!result.valid) {
      expect(result.errors.some((e) => e.code === "bend.material_not_in_group")).toBe(true);
    }
  });
});
