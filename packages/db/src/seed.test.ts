/**
 * Перевіряє форму seed-даних. Інтеграційний тест (вставка у реальну Postgres)
 * — окремо, після `docker compose up`.
 */
import { describe, expect, it } from "vitest";

import {
  SEED_MATERIALS,
  SEED_TEMPLATES,
  STANDARD_THICKNESSES_MM,
  STAINLESS_EXCLUDED_THICKNESS_MM,
} from "./seed.js";

describe("SEED_MATERIALS", () => {
  it("містить 7 матеріалів", () => {
    expect(SEED_MATERIALS).toHaveLength(7);
  });

  it("кожен матеріал має унікальний code", () => {
    const codes = SEED_MATERIALS.map((m) => m.code);
    expect(new Set(codes).size).toBe(SEED_MATERIALS.length);
  });

  it("містить очікувані коди матеріалів з doc/05 §4", () => {
    const codes = SEED_MATERIALS.map((m) => m.code).sort();
    expect(codes).toEqual([
      "aluminum_5754",
      "aluminum_amg3",
      "cold_rolled_steel",
      "galvanized_steel",
      "hot_rolled_steel",
      "stainless_304",
      "stainless_430",
    ]);
  });

  it("density_kg_m3 — додатне число для всіх", () => {
    for (const m of SEED_MATERIALS) {
      expect(Number(m.densityKgM3)).toBeGreaterThan(0);
    }
  });

  it("кожен матеріал має category з очікуваного набору", () => {
    const allowed = new Set(["steel", "stainless", "aluminum", "non_ferrous"]);
    for (const m of SEED_MATERIALS) {
      expect(allowed.has(m.category)).toBe(true);
    }
  });
});

describe("STANDARD_THICKNESSES_MM", () => {
  it("містить 10 стандартних товщин 1.0..10.0", () => {
    expect(STANDARD_THICKNESSES_MM).toEqual([1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0]);
  });

  it("STAINLESS_EXCLUDED_THICKNESS_MM = 10.0 (нержавійка не йде у 10мм)", () => {
    expect(STAINLESS_EXCLUDED_THICKNESS_MM).toBe(10.0);
  });
});

describe("SEED_TEMPLATES", () => {
  it("містить 6 шаблонів (Phase 2.10 × 5 + Phase 3.0 PR5 perforated_panel_square)", () => {
    expect(SEED_TEMPLATES).toHaveLength(6);
  });

  it("Phase 2.10 шаблони опубліковано у каталозі", () => {
    const published = SEED_TEMPLATES.filter((t) => t.isPublished)
      .map((t) => t.slug)
      .sort();
    expect(published).toEqual([
      "corner_angle",
      "l_bracket",
      "perforated_panel",
      "wall_shelf",
      "z_bracket",
    ]);
  });

  it("slug-и унікальні і відповідають Phase 2.10 + 3.0", () => {
    const slugs = SEED_TEMPLATES.map((t) => t.slug).sort();
    expect(slugs).toEqual([
      "corner_angle",
      "l_bracket",
      "perforated_panel",
      "perforated_panel_square",
      "wall_shelf",
      "z_bracket",
    ]);
  });

  it("кожен шаблон has name_uk і name_en", () => {
    for (const t of SEED_TEMPLATES) {
      expect(t.nameUk.length).toBeGreaterThan(0);
      expect(t.nameEn.length).toBeGreaterThan(0);
    }
  });

  it("L-bracket defaultParameters містить очікувані поля", () => {
    const lBracket = SEED_TEMPLATES.find((t) => t.slug === "l_bracket");
    expect(lBracket?.defaultParameters).toMatchObject({
      legA_mm: expect.any(Number),
      legB_mm: expect.any(Number),
      bend_radius_mm: expect.any(Number),
      bend_angle_deg: 90,
      width_mm: expect.any(Number),
    });
  });

  it("Z-bracket defaultParameters містить очікувані поля", () => {
    const zBracket = SEED_TEMPLATES.find((t) => t.slug === "z_bracket");
    expect(zBracket?.defaultParameters).toMatchObject({
      top_flange_mm: expect.any(Number),
      bottom_flange_mm: expect.any(Number),
      offset_mm: expect.any(Number),
      bend_radius_mm: expect.any(Number),
      bend_angle_deg: 90,
      width_mm: expect.any(Number),
    });
  });

  it("corner_angle defaultParameters містить hole-grid поля", () => {
    const corner = SEED_TEMPLATES.find((t) => t.slug === "corner_angle");
    expect(corner?.defaultParameters).toMatchObject({
      legA_mm: expect.any(Number),
      legB_mm: expect.any(Number),
      bend_radius_mm: expect.any(Number),
      bend_angle_deg: 90,
      width_mm: expect.any(Number),
      hole_diameter_mm: expect.any(Number),
      hole_rows: expect.any(Number),
      hole_cols: expect.any(Number),
      hole_margin_mm: expect.any(Number),
    });
  });

  it("wall_shelf defaultParameters містить U-channel і mount-hole поля", () => {
    const shelf = SEED_TEMPLATES.find((t) => t.slug === "wall_shelf");
    expect(shelf?.defaultParameters).toMatchObject({
      back_height_mm: expect.any(Number),
      shelf_depth_mm: expect.any(Number),
      front_lip_mm: expect.any(Number),
      bend_radius_mm: expect.any(Number),
      bend_angle_deg: 90,
      width_mm: expect.any(Number),
      mount_hole_diameter_mm: expect.any(Number),
      mount_hole_rows: expect.any(Number),
      mount_hole_cols: expect.any(Number),
      mount_hole_margin_mm: expect.any(Number),
    });
  });

  it("perforated_panel defaultParameters містить pitch-grid поля", () => {
    const panel = SEED_TEMPLATES.find((t) => t.slug === "perforated_panel");
    expect(panel?.defaultParameters).toMatchObject({
      length_mm: expect.any(Number),
      width_mm: expect.any(Number),
      hole_diameter_mm: expect.any(Number),
      pitch_x_mm: expect.any(Number),
      pitch_y_mm: expect.any(Number),
      margin_mm: expect.any(Number),
    });
  });

  it("perforated_panel_square defaultParameters містить square-hole поля", () => {
    const sq = SEED_TEMPLATES.find((t) => t.slug === "perforated_panel_square");
    expect(sq?.defaultParameters).toMatchObject({
      length_mm: expect.any(Number),
      width_mm: expect.any(Number),
      hole_size_mm: expect.any(Number),
      pitch_x_mm: expect.any(Number),
      pitch_y_mm: expect.any(Number),
      margin_mm: expect.any(Number),
    });
  });

  it("perforated_panel_square — єдиний unpublished (base для products, Phase 3.0 PR 5)", () => {
    const unpublished = SEED_TEMPLATES.filter((t) => !t.isPublished).map((t) => t.slug);
    expect(unpublished).toEqual(["perforated_panel_square"]);
  });
});
