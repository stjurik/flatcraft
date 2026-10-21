/**
 * Регресія для `enclosedShelfDefinition` (Run 7 Master Registry Track, Етап
 * 2, шоста міграція) — паритет з видаленим `enclosed-shelf-editor.tsx`:
 * `bends`/`side_perforation`/`stiffening_rib` поза generic AutoForm, summary
 * на дефолтах — той самий текст, що показував старий editor.
 */
import { describe, expect, it } from "vitest";

import { enclosedShelfDefinition } from "./index.js";

describe("enclosedShelfDefinition — visibleFields", () => {
  it("ховає bends, side_perforation, stiffening_rib (nested/масив — поза generic AutoForm)", () => {
    for (const hidden of ["bends", "side_perforation", "stiffening_rib"]) {
      expect(enclosedShelfDefinition.ui.visibleFields).not.toContain(hidden);
    }
  });

  it("показує width_mm, depth_mm, bend_radius_mm", () => {
    for (const visible of ["width_mm", "depth_mm", "bend_radius_mm"]) {
      expect(enclosedShelfDefinition.ui.visibleFields).toContain(visible);
    }
  });
});

describe("enclosedShelfDefinition — summary (testId enclosed-shelf-summary)", () => {
  const summaryControl = enclosedShelfDefinition.ui.extraControls?.find(
    (c) => c.kind === "summary",
  );

  it("зареєстрований з testId enclosed-shelf-summary", () => {
    expect(summaryControl?.testId).toBe("enclosed-shelf-summary");
  });

  it("на дефолтних параметрах — «3 гиби UP · без перфорації»", () => {
    if (summaryControl?.kind !== "summary") throw new Error("summary control not found");
    expect(summaryControl.render(enclosedShelfDefinition.defaults)).toBe(
      "3 гиби UP · без перфорації",
    );
  });
});

describe("enclosedShelfDefinition — validators (issue #237 п.2, render-gate ADR-026)", () => {
  const T = 2;
  const runValidators = (params: (typeof enclosedShelfDefinition)["defaults"], thicknessMm = T) =>
    enclosedShelfDefinition.validators.flatMap((v) => v(params, thicknessMm));

  it("дефолтні параметри → []", () => {
    expect(enclosedShelfDefinition.validators.length).toBeGreaterThan(0);
    expect(runValidators(enclosedShelfDefinition.defaults)).toEqual([]);
  });

  it("width_mm: 50 (< min 300) → issue з field width_mm", () => {
    const issues = runValidators({ ...enclosedShelfDefinition.defaults, width_mm: 50 });
    expect(issues.length).toBeGreaterThan(0);
    expect(issues.some((i) => i.field === "width_mm")).toBe(true);
  });

  it("depth_mm: 20 (< min 100) → issue з field depth_mm", () => {
    const issues = runValidators({ ...enclosedShelfDefinition.defaults, depth_mm: 20 });
    expect(issues.length).toBeGreaterThan(0);
    expect(issues.some((i) => i.field === "depth_mm")).toBe(true);
  });

  it("bend_angle_deg: 45 (literal 90) → issue з field bend_angle_deg", () => {
    const issues = runValidators({
      ...enclosedShelfDefinition.defaults,
      bend_angle_deg: 45 as unknown as 90,
    });
    expect(issues.some((i) => i.field === "bend_angle_deg")).toBe(true);
  });

  it("stiffening_rib.height_mm: 2 (< min 5) → issue з field stiffening_rib.height_mm", () => {
    const issues = runValidators({
      ...enclosedShelfDefinition.defaults,
      stiffening_rib: { height_mm: 2 },
    });
    expect(issues.some((i) => i.field === "stiffening_rib.height_mm")).toBe(true);
  });

  it("товщина 1.5 (у матриці) на дефолтах → []", () => {
    expect(runValidators(enclosedShelfDefinition.defaults, 1.5)).toEqual([]);
  });

  it("товщина 0 і 999 (поза матрицею) → issue з field thickness_mm", () => {
    for (const thicknessMm of [0, 999]) {
      const issues = runValidators(enclosedShelfDefinition.defaults, thicknessMm);
      expect(issues.some((i) => i.field === "thickness_mm")).toBe(true);
    }
  });
});
