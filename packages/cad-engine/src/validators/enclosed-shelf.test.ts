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

  const COMMON = {
    bend_radius_mm: 2.5,
    stiffening_rib: null,
    material_code: "cold_rolled_steel",
  } as const;

  it("side_perforation=null → []", () => {
    expect(
      validateEnclosedShelfSidePerforation({ side_perforation: null, depth_mm: 200, ...COMMON }, 2),
    ).toEqual([]);
  });

  it("валідна перфорація (дефолтна глибина 200) → []", () => {
    expect(
      validateEnclosedShelfSidePerforation({ side_perforation: SIDE, depth_mm: 200, ...COMMON }, 2),
    ).toEqual([]);
  });

  it("pitch_x_mm=10 == hole_size_mm → HOLES_OVERLAP на pitch_x_mm", () => {
    const issues = validateEnclosedShelfSidePerforation(
      { side_perforation: { ...SIDE, pitch_x_mm: 10 }, depth_mm: 200, ...COMMON },
      2,
    );
    expect(issues.map((e) => e.code)).toContain("HOLES_OVERLAP");
    expect(issues.find((e) => e.code === "HOLES_OVERLAP")?.field).toBe(
      "side_perforation.pitch_x_mm",
    );
  });

  it("pitch_y_mm=8 < hole_size_mm → HOLES_OVERLAP на pitch_y_mm", () => {
    const issues = validateEnclosedShelfSidePerforation(
      { side_perforation: { ...SIDE, pitch_y_mm: 8 }, depth_mm: 200, ...COMMON },
      2,
    );
    expect(issues.find((e) => e.field === "side_perforation.pitch_y_mm")?.code).toBe(
      "HOLES_OVERLAP",
    );
  });

  it("margin_mm=5 == hole_size_mm/2 → MARGIN_TOO_SMALL (межа — строго більше)", () => {
    const issues = validateEnclosedShelfSidePerforation(
      { side_perforation: { ...SIDE, margin_mm: 5 }, depth_mm: 200, ...COMMON },
      2,
    );
    expect(issues.find((e) => e.code === "MARGIN_TOO_SMALL")?.field).toBe(
      "side_perforation.margin_mm",
    );
  });

  it("d=100, r=2.5, t=2, margin=48 → PERFORATION_DOES_NOT_FIT на margin_mm, повідомлення містить 48", () => {
    const issues = validateEnclosedShelfSidePerforation(
      { side_perforation: { ...SIDE, margin_mm: 48 }, depth_mm: 100, ...COMMON },
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
        { side_perforation: { ...SIDE, margin_mm: 47.5 }, depth_mm: 100, ...COMMON },
        2,
      ),
    ).toEqual([]);
  });

  it("d=100, r=2.5, t=2, hole_size_mm=96 (≥ w=95.5) → PERFORATION_DOES_NOT_FIT на hole_size_mm", () => {
    const issues = validateEnclosedShelfSidePerforation(
      {
        side_perforation: { hole_size_mm: 96, pitch_x_mm: 100, pitch_y_mm: 100, margin_mm: 45 },
        depth_mm: 100,
        ...COMMON,
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
        ...COMMON,
      },
      2,
    );
    const got = issues.map((e) => `${e.code}@${e.field}`);
    expect(got).toContain("HOLES_OVERLAP@side_perforation.pitch_x_mm");
    expect(got).toContain("HOLES_OVERLAP@side_perforation.pitch_y_mm");
    expect(got).toContain("MARGIN_TOO_SMALL@side_perforation.margin_mm");
  });

  it("issue #303: отвір надто близько до гиба і в кутовому виступі → обидві нові помилки", () => {
    const issues = validateEnclosedShelfSidePerforation(
      {
        side_perforation: { hole_size_mm: 20, pitch_x_mm: 37, pitch_y_mm: 39.5, margin_mm: 10.5 },
        depth_mm: 100,
        bend_radius_mm: 2.5,
        stiffening_rib: { height_mm: 15 },
        material_code: "cold_rolled_steel",
      },
      2.5,
    );
    const got = issues.map((e) => `${e.code}@${e.field}`);
    expect(got).toContain("HOLE_TOO_CLOSE_TO_BEND@side_perforation.margin_mm");
    expect(got).toContain("HOLE_IN_CORNER_TAB@side_perforation.margin_mm");
  });

  it("межа гиба e_x-h/2=7.5=a·t+r → без HOLE_TOO_CLOSE_TO_BEND", () => {
    const issues = validateEnclosedShelfSidePerforation(
      {
        side_perforation: { hole_size_mm: 10, pitch_x_mm: 35, pitch_y_mm: 35, margin_mm: 12.5 },
        depth_mm: 100,
        bend_radius_mm: 2.5,
        stiffening_rib: { height_mm: 15 },
        material_code: "cold_rolled_steel",
      },
      2.5,
    );
    expect(issues.map((e) => e.code)).not.toContain("HOLE_TOO_CLOSE_TO_BEND");
  });

  it("невідомий material_code → HOLE_TOO_CLOSE_TO_BEND пропускається, HOLE_IN_CORNER_TAB лишається", () => {
    const issues = validateEnclosedShelfSidePerforation(
      {
        side_perforation: { hole_size_mm: 20, pitch_x_mm: 37, pitch_y_mm: 39.5, margin_mm: 10.5 },
        depth_mm: 100,
        bend_radius_mm: 2.5,
        stiffening_rib: { height_mm: 15 },
        material_code: "unobtanium",
      },
      2.5,
    );
    const got = issues.map((e) => e.code);
    expect(got).not.toContain("HOLE_TOO_CLOSE_TO_BEND");
    expect(got).toContain("HOLE_IN_CORNER_TAB");
  });
});

describe("validateEnclosedShelfSidePerforation — #303, сценарії постановки 060 (рецензія #321)", () => {
  const side = (h: number, px: number, py: number, m: number) => ({
    hole_size_mm: h,
    pitch_x_mm: px,
    pitch_y_mm: py,
    margin_mm: m,
  });
  const codes = (
    s: ReturnType<typeof side>,
    rib: number | null = 15,
    material = "cold_rolled_steel",
  ): string[] =>
    validateEnclosedShelfSidePerforation(
      {
        side_perforation: s,
        depth_mm: 100,
        bend_radius_mm: 2.5,
        stiffening_rib: rib === null ? null : { height_mm: rib },
        material_code: material,
      },
      2.5,
    ).map((e) => `${e.code}@${e.field}`);
  const BEND = "HOLE_TOO_CLOSE_TO_BEND@side_perforation.margin_mm";
  const TAB = "HOLE_IN_CORNER_TAB@side_perforation.margin_mm";

  it("px=36, m=11.5 → HOLE_TOO_CLOSE_TO_BEND (6.5 < 7.5), без HOLE_IN_CORNER_TAB", () => {
    const c = codes(side(10, 36, 35, 11.5));
    expect(c).toContain(BEND);
    expect(c).not.toContain(TAB);
  });
  it("py=42, m=8: з ребром → HOLE_IN_CORNER_TAB; без ребра → немає", () => {
    expect(codes(side(10, 35, 42, 8), 15)).toContain(TAB);
    expect(codes(side(10, 35, 42, 8), null)).not.toContain(TAB);
  });
  it("py=45, m=8 → без HOLE_IN_CORNER_TAB (рахується від e_y = 27.5, а не m)", () => {
    expect(codes(side(10, 35, 45, 8))).not.toContain(TAB);
  });
  it("коефіцієнт з таблиці: aluminum_5754 → без BEND; stainless_304 на межі сталі → BEND", () => {
    expect(codes(side(10, 36, 35, 11.5), 15, "aluminum_5754")).not.toContain(BEND);
    expect(codes(side(10, 35, 35, 12.5), 15, "stainless_304")).toContain(BEND);
  });
});
