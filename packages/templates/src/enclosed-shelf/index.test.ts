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

// Доробка #275 (issue #237 п.2) — одне коло за рецензіями Flash і Argon Medium
// (PR #275#issuecomment-6410942324). Argon-контрприклад 1: `unfold.py:799-805`
// кидає `ValueError` при `flat_rib_y = height_mm - (t+r) <= 0`, а render-gate
// цього не бачив — валідатори повертали `[]`.
describe("enclosedShelfDefinition — stiffeningRibValidator (Argon-контрприклад 1)", () => {
  const runValidators = (
    params: (typeof enclosedShelfDefinition)["defaults"],
    thicknessMm: number,
  ) => enclosedShelfDefinition.validators.flatMap((v) => v(params, thicknessMm));

  it("height_mm <= t+r (5 при t=2.5, r=2.5) → issue FLANGE_TOO_SHORT на stiffening_rib.height_mm", () => {
    const issues = runValidators(
      {
        ...enclosedShelfDefinition.defaults,
        bend_radius_mm: 2.5,
        stiffening_rib: { height_mm: 5 },
      },
      2.5,
    );
    const ribIssue = issues.find((i) => i.field === "stiffening_rib.height_mm");
    expect(ribIssue?.code).toBe("FLANGE_TOO_SHORT");
    expect(ribIssue?.message).toBeTruthy();
  });

  it("height_mm > t+r (5.5 при t=2.5, r=2.5) → без issue на stiffening_rib.height_mm", () => {
    const issues = runValidators(
      {
        ...enclosedShelfDefinition.defaults,
        bend_radius_mm: 2.5,
        stiffening_rib: { height_mm: 5.5 },
      },
      2.5,
    );
    expect(issues.filter((i) => i.field === "stiffening_rib.height_mm")).toEqual([]);
  });

  it("без ребра (stiffening_rib: null, дефолт) → без issue на stiffening_rib.height_mm", () => {
    const issues = runValidators(enclosedShelfDefinition.defaults, 2.5);
    expect(issues.filter((i) => i.field === "stiffening_rib.height_mm")).toEqual([]);
  });
});

// Argon-контрприклади 2 і 3: `side_rect.w_mm` у `_enclosed_shelf_side_holes`
// (`unfold.py:626-640`) — це `depth_mm - (t+r)`, не повний `depth_mm`;
// `pitch <= hole_size` чи `margin < hole_size/2` дають отвори, що
// зливаються/виходять за межі боковини.
describe("enclosedShelfDefinition — sidePerforationValidator (Argon-контрприклади 2 і 3)", () => {
  type Params = (typeof enclosedShelfDefinition)["defaults"];
  type SidePerforation = NonNullable<Params["side_perforation"]>;

  const perf = (hole: number, px: number, py: number, margin: number): SidePerforation => ({
    hole_size_mm: hole,
    pitch_x_mm: px,
    pitch_y_mm: py,
    margin_mm: margin,
  });
  const withPerf = (
    sp: SidePerforation,
    depth = 200,
    r: Params["bend_radius_mm"] = 2.5,
  ): Params => ({
    ...enclosedShelfDefinition.defaults,
    depth_mm: depth,
    bend_radius_mm: r,
    side_perforation: sp,
  });
  const runValidators = (params: Params, thicknessMm: number) =>
    enclosedShelfDefinition.validators.flatMap((v) => v(params, thicknessMm));

  it("2·margin_mm > depth_mm-(t+r) (margin 48, depth 100, t=2, r=2.5) → issue HOLES_NO_ROOM", () => {
    const issues = runValidators(withPerf(perf(10, 20, 20, 48), 100), 2);
    const issue = issues.find((i) => i.field === "side_perforation.margin_mm");
    expect(issue?.code).toBe("HOLES_NO_ROOM");
  });

  it("межа 2·margin_mm = depth_mm-(t+r) (margin 49, depth 100, t=1, r=1) → без issue HOLES_NO_ROOM", () => {
    const issues = runValidators(withPerf(perf(10, 20, 20, 49), 100, 1), 1);
    expect(issues.some((i) => i.code === "HOLES_NO_ROOM")).toBe(false);
  });

  it("pitch_x_mm <= hole_size_mm (20<=20) → issue HOLES_OVERLAP на side_perforation.pitch_x_mm", () => {
    const issues = runValidators(withPerf(perf(20, 20, 30, 20)), 2);
    const issue = issues.find((i) => i.field === "side_perforation.pitch_x_mm");
    expect(issue?.code).toBe("HOLES_OVERLAP");
    expect(issue?.message).toBeTruthy();
  });

  it("pitch_y_mm <= hole_size_mm (20<=20) → issue HOLES_OVERLAP на side_perforation.pitch_y_mm", () => {
    const issues = runValidators(withPerf(perf(20, 30, 20, 20)), 2);
    const issue = issues.find((i) => i.field === "side_perforation.pitch_y_mm");
    expect(issue?.code).toBe("HOLES_OVERLAP");
  });

  it("margin_mm < hole_size_mm/2 (hole 20, margin 5) → issue HOLES_OUT_OF_BOUNDS", () => {
    const issues = runValidators(withPerf(perf(20, 30, 30, 5)), 2);
    const issue = issues.find((i) => i.field === "side_perforation.margin_mm");
    expect(issue?.code).toBe("HOLES_OUT_OF_BOUNDS");
  });

  it("межа margin_mm = hole_size_mm/2 (hole 20, margin 10) → без issue HOLES_OUT_OF_BOUNDS", () => {
    const issues = runValidators(withPerf(perf(20, 30, 30, 10)), 2);
    expect(issues.some((i) => i.code === "HOLES_OUT_OF_BOUNDS")).toBe(false);
  });

  it("валідна перфорація (10/20/20/20, depth 200) → без issue", () => {
    expect(runValidators(withPerf(perf(10, 20, 20, 20)), 2)).toEqual([]);
  });

  it("нові issue — конкретний code (не INVALID_PARAMETER) і україномовне message", () => {
    const UA = /[А-Яа-яІіЇїЄєҐґ]/;
    const issues = [
      ...runValidators(
        {
          ...enclosedShelfDefinition.defaults,
          bend_radius_mm: 2.5,
          stiffening_rib: { height_mm: 5 },
        },
        2.5,
      ),
      ...runValidators(withPerf(perf(20, 20, 20, 20)), 2),
    ].filter((i) => i.field.startsWith("stiffening_rib") || i.field.startsWith("side_perforation"));
    expect(issues.length).toBeGreaterThan(1);
    for (const issue of issues) {
      expect(issue.code).toBeTruthy();
      expect(issue.code).not.toBe("INVALID_PARAMETER");
      expect(issue.message ?? "").toMatch(UA);
    }
  });
});
