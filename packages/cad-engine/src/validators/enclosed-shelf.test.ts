/**
 * Юніт-тести enclosed_shelf-гейта (issue #283): ребро жорсткості і
 * перфорація боковин. Дзеркало Python
 * `workers/cad/tests/test_enclosed_shelf_gate.py`.
 */
import { describe, expect, it } from "vitest";

import {
  validateEnclosedShelfRib,
  validateEnclosedShelfSidePerforation,
} from "./enclosed-shelf.js";

describe("validateEnclosedShelfRib", () => {
  it("stiffening_rib=null → []", () => {
    expect(validateEnclosedShelfRib({ stiffening_rib: null, bend_radius_mm: 2.5 }, 2.5)).toEqual(
      [],
    );
  });

  it("height_mm == t+r (5 == 2.5+2.5) → FLANGE_TOO_SHORT (межа — строго більше)", () => {
    const issues = validateEnclosedShelfRib(
      { stiffening_rib: { height_mm: 5 }, bend_radius_mm: 2.5 },
      2.5,
    );
    expect(issues).toHaveLength(1);
    expect(issues[0]).toMatchObject({
      code: "FLANGE_TOO_SHORT",
      field: "stiffening_rib.height_mm",
      value: 5,
    });
  });

  it("height_mm 4.9 < t+r → FLANGE_TOO_SHORT, повідомлення містить 4.9", () => {
    const issues = validateEnclosedShelfRib(
      { stiffening_rib: { height_mm: 4.9 }, bend_radius_mm: 2.5 },
      2.5,
    );
    expect(issues[0]?.message).toContain("4.9");
  });

  it("height_mm 5.5 > t+r → []", () => {
    expect(
      validateEnclosedShelfRib({ stiffening_rib: { height_mm: 5.5 }, bend_radius_mm: 2.5 }, 2.5),
    ).toEqual([]);
  });
});

describe("validateEnclosedShelfSidePerforation", () => {
  const SIDE = { hole_size_mm: 10, pitch_x_mm: 20, pitch_y_mm: 20, margin_mm: 20 };

  it("side_perforation=null → []", () => {
    expect(
      validateEnclosedShelfSidePerforation(
        { side_perforation: null, depth_mm: 200, bend_radius_mm: 2.5 },
        2,
      ),
    ).toEqual([]);
  });

  it("валідна перфорація (дефолтна глибина 200) → []", () => {
    expect(
      validateEnclosedShelfSidePerforation(
        { side_perforation: SIDE, depth_mm: 200, bend_radius_mm: 2.5 },
        2,
      ),
    ).toEqual([]);
  });

  it("pitch_x_mm=10 == hole_size_mm → HOLES_OVERLAP на pitch_x_mm", () => {
    const issues = validateEnclosedShelfSidePerforation(
      { side_perforation: { ...SIDE, pitch_x_mm: 10 }, depth_mm: 200, bend_radius_mm: 2.5 },
      2,
    );
    expect(issues.map((e) => e.code)).toContain("HOLES_OVERLAP");
    expect(issues.find((e) => e.code === "HOLES_OVERLAP")?.field).toBe(
      "side_perforation.pitch_x_mm",
    );
  });

  it("pitch_y_mm=8 < hole_size_mm → HOLES_OVERLAP на pitch_y_mm", () => {
    const issues = validateEnclosedShelfSidePerforation(
      { side_perforation: { ...SIDE, pitch_y_mm: 8 }, depth_mm: 200, bend_radius_mm: 2.5 },
      2,
    );
    expect(issues.find((e) => e.field === "side_perforation.pitch_y_mm")?.code).toBe(
      "HOLES_OVERLAP",
    );
  });

  it("margin_mm=5 == hole_size_mm/2 → MARGIN_TOO_SMALL (межа — строго більше)", () => {
    const issues = validateEnclosedShelfSidePerforation(
      { side_perforation: { ...SIDE, margin_mm: 5 }, depth_mm: 200, bend_radius_mm: 2.5 },
      2,
    );
    expect(issues.find((e) => e.code === "MARGIN_TOO_SMALL")?.field).toBe(
      "side_perforation.margin_mm",
    );
  });

  it("d=100, r=2.5, t=2, margin=48 → PERFORATION_DOES_NOT_FIT на margin_mm, повідомлення містить 48", () => {
    const issues = validateEnclosedShelfSidePerforation(
      { side_perforation: { ...SIDE, margin_mm: 48 }, depth_mm: 100, bend_radius_mm: 2.5 },
      2,
    );
    const hit = issues.find(
      (e) => e.code === "PERFORATION_DOES_NOT_FIT" && e.field === "side_perforation.margin_mm",
    );
    expect(hit).toBeDefined();
    expect(hit?.message).toContain("48");
  });

  it("d=100, r=2.5, t=2, margin=47.5 (межа, w=95.5, 2m=95≤95.5) → без помилок", () => {
    expect(
      validateEnclosedShelfSidePerforation(
        { side_perforation: { ...SIDE, margin_mm: 47.5 }, depth_mm: 100, bend_radius_mm: 2.5 },
        2,
      ),
    ).toEqual([]);
  });

  it("d=100, r=2.5, t=2, hole_size_mm=96 (≥ w=95.5) → PERFORATION_DOES_NOT_FIT на hole_size_mm", () => {
    const issues = validateEnclosedShelfSidePerforation(
      {
        side_perforation: { hole_size_mm: 96, pitch_x_mm: 100, pitch_y_mm: 100, margin_mm: 45 },
        depth_mm: 100,
        bend_radius_mm: 2.5,
      },
      2,
    );
    expect(issues.find((e) => e.field === "side_perforation.hole_size_mm")?.code).toBe(
      "PERFORATION_DOES_NOT_FIT",
    );
  });

  it("усі порушення разом: pitch_x=8, pitch_y=8, margin=3 → 3 незалежні помилки", () => {
    const issues = validateEnclosedShelfSidePerforation(
      {
        side_perforation: { hole_size_mm: 10, pitch_x_mm: 8, pitch_y_mm: 8, margin_mm: 3 },
        depth_mm: 200,
        bend_radius_mm: 2.5,
      },
      2,
    );
    const got = issues.map((e) => `${e.code}@${e.field}`);
    expect(got).toContain("HOLES_OVERLAP@side_perforation.pitch_x_mm");
    expect(got).toContain("HOLES_OVERLAP@side_perforation.pitch_y_mm");
    expect(got).toContain("MARGIN_TOO_SMALL@side_perforation.margin_mm");
  });
});
