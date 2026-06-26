/**
 * Юніт-тести profile-валідатора (Hotfix 2.9.f, ADR-026).
 *
 * Перевіряємо паритет із assertion'ами `geometry.ts` для всіх 4 гибових
 * шаблонів + імунітет perforated_panel.
 */
import { describe, expect, it } from "vitest";

import { validateProfile } from "./profile.js";

describe("validateProfile — l_bracket / corner_angle (legs)", () => {
  const base = { legA_mm: 60, legB_mm: 60, bend_radius_mm: 2.5 };

  it("валідний профіль → []", () => {
    expect(
      validateProfile({ templateSlug: "corner_angle", parameters: base, thicknessMm: 2 }),
    ).toEqual([]);
  });

  it("legA рівно на межі (t+r) → валідно (inclusive)", () => {
    // t=2, r=2.5 → min=4.5; legA=4.5 не кидає у geometry.ts.
    const issues = validateProfile({
      templateSlug: "l_bracket",
      parameters: { ...base, legA_mm: 4.5 },
      thicknessMm: 2,
    });
    expect(issues).toEqual([]);
  });

  it("legA нижче межі → LEG_TOO_SHORT з which/min/got", () => {
    const issues = validateProfile({
      templateSlug: "corner_angle",
      parameters: { ...base, legA_mm: 1 },
      thicknessMm: 2,
    });
    expect(issues).toHaveLength(1);
    expect(issues[0]).toMatchObject({ code: "LEG_TOO_SHORT", which: "legA", min: 4.5, got: 1 });
    expect(issues[0]?.message).toContain("4.5");
  });

  it("legB нижче межі → LEG_TOO_SHORT which=legB", () => {
    const issues = validateProfile({
      templateSlug: "l_bracket",
      parameters: { ...base, legB_mm: 2 },
      thicknessMm: 2,
    });
    expect(issues).toEqual([
      expect.objectContaining({ code: "LEG_TOO_SHORT", which: "legB", min: 4.5, got: 2 }),
    ]);
  });

  it("обидва плеча замалі → два issues", () => {
    const issues = validateProfile({
      templateSlug: "corner_angle",
      parameters: { legA_mm: 1, legB_mm: 1, bend_radius_mm: 2.5 },
      thicknessMm: 2,
    });
    expect(issues.map((i) => i.which).sort()).toEqual(["legA", "legB"]);
  });

  it("thickness <= 0 → [] (захист, не валимо)", () => {
    expect(
      validateProfile({
        templateSlug: "l_bracket",
        parameters: { ...base, legA_mm: 1 },
        thicknessMm: 0,
      }),
    ).toEqual([]);
  });
});

describe("validateProfile — z_bracket (flanges strict + offset)", () => {
  const base = { top_flange_mm: 60, bottom_flange_mm: 60, offset_mm: 50, bend_radius_mm: 2.5 };

  it("валідний → []", () => {
    expect(
      validateProfile({ templateSlug: "z_bracket", parameters: base, thicknessMm: 2 }),
    ).toEqual([]);
  });

  it("top_flange рівно t+r → НЕвалідно (строге >)", () => {
    const issues = validateProfile({
      templateSlug: "z_bracket",
      parameters: { ...base, top_flange_mm: 4.5 },
      thicknessMm: 2,
    });
    expect(issues).toEqual([
      expect.objectContaining({
        code: "FLANGE_TOO_SHORT",
        which: "top_flange",
        min: 4.5,
        got: 4.5,
      }),
    ]);
  });

  it("offset <= r → OFFSET_TOO_SMALL (min=r)", () => {
    const issues = validateProfile({
      templateSlug: "z_bracket",
      parameters: { ...base, offset_mm: 2.5 },
      thicknessMm: 2,
    });
    expect(issues).toEqual([
      expect.objectContaining({ code: "OFFSET_TOO_SMALL", which: "offset", min: 2.5, got: 2.5 }),
    ]);
  });

  it("bottom_flange замала → FLANGE_TOO_SHORT which=bottom_flange", () => {
    const issues = validateProfile({
      templateSlug: "z_bracket",
      parameters: { ...base, bottom_flange_mm: 3 },
      thicknessMm: 2,
    });
    expect(issues).toEqual([
      expect.objectContaining({ code: "FLANGE_TOO_SHORT", which: "bottom_flange" }),
    ]);
  });
});

describe("validateProfile — wall_shelf (back + shelf double-bend/lip)", () => {
  const withLip = {
    back_height_mm: 80,
    shelf_depth_mm: 120,
    front_lip_mm: 20,
    bend_radius_mm: 2.5,
  };

  it("валідний з губою → []", () => {
    expect(
      validateProfile({ templateSlug: "wall_shelf", parameters: withLip, thicknessMm: 2 }),
    ).toEqual([]);
  });

  it("back_height <= t+r → FLANGE_TOO_SHORT which=back_height", () => {
    const issues = validateProfile({
      templateSlug: "wall_shelf",
      parameters: { ...withLip, back_height_mm: 4 },
      thicknessMm: 2,
    });
    expect(issues).toEqual([
      expect.objectContaining({ code: "FLANGE_TOO_SHORT", which: "back_height" }),
    ]);
  });

  it("lip>0: shelf має бути > 2(t+r); shelf=2(t+r)=9 → SHELF_TOO_SHORT min=9", () => {
    const issues = validateProfile({
      templateSlug: "wall_shelf",
      parameters: { ...withLip, shelf_depth_mm: 9 },
      thicknessMm: 2,
    });
    expect(issues).toEqual([
      expect.objectContaining({ code: "SHELF_TOO_SHORT", which: "shelf_depth", min: 9, got: 9 }),
    ]);
  });

  it("lip=0: достатньо shelf > t+r (4.5); shelf=10 → []", () => {
    const issues = validateProfile({
      templateSlug: "wall_shelf",
      parameters: { ...withLip, front_lip_mm: 0, shelf_depth_mm: 10 },
      thicknessMm: 2,
    });
    expect(issues).toEqual([]);
  });
});

describe("validateProfile — perforated_panel (ребриста, ADR-031)", () => {
  it("валідне ребро (rib_height > t+r) → []", () => {
    expect(
      validateProfile({
        templateSlug: "perforated_panel",
        parameters: { rib_height_mm: 30, bend_radius_mm: 2.5 },
        thicknessMm: 2,
      }),
    ).toEqual([]);
  });

  it("замале ребро (rib_height ≤ t+r) → FLANGE_TOO_SHORT", () => {
    const issues = validateProfile({
      templateSlug: "perforated_panel",
      parameters: { rib_height_mm: 4, bend_radius_mm: 2.5 },
      thicknessMm: 2,
    });
    expect(issues.map((i) => i.code)).toContain("FLANGE_TOO_SHORT");
    expect(issues[0]?.which).toBe("rib_height");
  });
});
