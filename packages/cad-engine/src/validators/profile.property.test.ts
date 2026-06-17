/**
 * Property-based тести profile-валідатора (Hotfix 2.9.f, ADR-026).
 *
 * Oracle — незалежні геометричні нерівності (НЕ виклик самого валідатора),
 * дзеркалені у Python (`tests/test_profile_validator_property.py`). Для будь-яких
 * (t, r, розміри): issue для виміру існує ⇔ oracle вважає його замалим.
 * 300 ітерацій (правило простіше за матрицю гибу).
 */
import fc from "fast-check";
import { describe, it } from "vitest";

import { validateProfile } from "./profile.js";

const ITER = 300;
const tArb = fc.constantFrom(0.5, 1, 1.5, 2, 3, 4, 6, 8);
const rArb = fc.constantFrom(0.5, 1, 2.5, 4, 5);
const dimArb = fc.constantFrom(0.5, 1, 2, 4, 4.5, 5, 9, 10, 50, 100, 500);

function has(issues: { which: string }[], which: string): boolean {
  return issues.some((i) => i.which === which);
}

describe("validateProfile — property parity з geometry.ts", () => {
  it("legs (corner_angle): issue ⇔ leg < t+r", () => {
    fc.assert(
      fc.property(tArb, rArb, dimArb, dimArb, (t, r, legA, legB) => {
        const issues = validateProfile({
          templateSlug: "corner_angle",
          parameters: { legA_mm: legA, legB_mm: legB, bend_radius_mm: r },
          thicknessMm: t,
        });
        return has(issues, "legA") === legA < t + r && has(issues, "legB") === legB < t + r;
      }),
      { numRuns: ITER },
    );
  });

  it("z_bracket: flange issue ⇔ flange <= t+r; offset issue ⇔ offset <= r", () => {
    fc.assert(
      fc.property(tArb, rArb, dimArb, dimArb, dimArb, (t, r, tf, bf, off) => {
        const issues = validateProfile({
          templateSlug: "z_bracket",
          parameters: {
            top_flange_mm: tf,
            bottom_flange_mm: bf,
            offset_mm: off,
            bend_radius_mm: r,
          },
          thicknessMm: t,
        });
        return (
          has(issues, "top_flange") === tf <= t + r &&
          has(issues, "bottom_flange") === bf <= t + r &&
          has(issues, "offset") === off <= r
        );
      }),
      { numRuns: ITER },
    );
  });

  it("wall_shelf: back issue ⇔ bh<=t+r; shelf issue ⇔ sd<=(lip>0?2(t+r):t+r)", () => {
    fc.assert(
      fc.property(tArb, rArb, dimArb, dimArb, fc.constantFrom(0, 20), (t, r, bh, sd, lip) => {
        const issues = validateProfile({
          templateSlug: "wall_shelf",
          parameters: {
            back_height_mm: bh,
            shelf_depth_mm: sd,
            front_lip_mm: lip,
            bend_radius_mm: r,
          },
          thicknessMm: t,
        });
        const shelfThreshold = lip > 0 ? 2 * (t + r) : t + r;
        return (
          has(issues, "back_height") === bh <= t + r &&
          has(issues, "shelf_depth") === sd <= shelfThreshold
        );
      }),
      { numRuns: ITER },
    );
  });
});
