import { describe, expect, it } from "vitest";

import { loadSpecFromFile } from "../spec.js";
import { validateSheet } from "./sheet.js";

const spec = await loadSpecFromFile();

describe("validateSheet", () => {
  it("happy path: підтримувані товщина+матеріал, габарит у нормі", () => {
    const result = validateSheet(
      {
        materialCode: "cold_rolled_steel",
        thicknessMm: 2.0,
        widthMm: 200,
        heightMm: 300,
      },
      spec,
    );
    expect(result.valid).toBe(true);
  });

  it("відхиляє непідтримувану товщину (не у capability_matrix)", () => {
    const result = validateSheet(
      {
        materialCode: "cold_rolled_steel",
        thicknessMm: 7.0,
        widthMm: 100,
        heightMm: 100,
      },
      spec,
    );
    expect(result.valid).toBe(false);
    if (!result.valid) {
      expect(result.errors[0]?.code).toBe("sheet.thickness_unsupported");
      expect(result.errors[0]?.fields).toContain("thicknessMm");
    }
  });

  it("відхиляє нержавійку 10мм (вона у carbon_alu_galv_only group)", () => {
    const result = validateSheet(
      {
        materialCode: "stainless_304",
        thicknessMm: 10.0,
        widthMm: 100,
        heightMm: 100,
      },
      spec,
    );
    expect(result.valid).toBe(false);
    if (!result.valid) {
      expect(result.errors.some((e) => e.code === "sheet.material_not_in_group")).toBe(true);
    }
  });

  it("відхиляє габарит, що перевищує max_bend_length_mm для товщини", () => {
    // Для 8мм max_bend_length_mm = 1000.
    const result = validateSheet(
      {
        materialCode: "cold_rolled_steel",
        thicknessMm: 8.0,
        widthMm: 1200,
        heightMm: 500,
      },
      spec,
    );
    expect(result.valid).toBe(false);
    if (!result.valid) {
      expect(result.errors.some((e) => e.code === "sheet.exceeds_max_bend_length")).toBe(true);
    }
  });

  it("приймає 8мм заготовку 1000×500 (точно межа)", () => {
    const result = validateSheet(
      {
        materialCode: "cold_rolled_steel",
        thicknessMm: 8.0,
        widthMm: 1000,
        heightMm: 500,
      },
      spec,
    );
    expect(result.valid).toBe(true);
  });

  it("збирає кілька помилок у одну відповідь", () => {
    const result = validateSheet(
      {
        materialCode: "stainless_304",
        thicknessMm: 10.0,
        widthMm: 5000,
        heightMm: 100,
      },
      spec,
    );
    expect(result.valid).toBe(false);
    if (!result.valid) {
      // material_not_in_group + exceeds_max_bend_length
      expect(result.errors.length).toBeGreaterThanOrEqual(2);
    }
  });
});
