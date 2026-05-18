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
  it("містить 5 шаблонів", () => {
    expect(SEED_TEMPLATES).toHaveLength(5);
  });

  it("L-bracket і Z-bracket опубліковано (Phase 2.10 готовий)", () => {
    const published = SEED_TEMPLATES.filter((t) => t.isPublished)
      .map((t) => t.slug)
      .sort();
    expect(published).toEqual(["l_bracket", "z_bracket"]);
  });

  it("slug-и унікальні і відповідають roadmap Phase 2.10", () => {
    const slugs = SEED_TEMPLATES.map((t) => t.slug).sort();
    expect(slugs).toEqual([
      "corner_angle",
      "l_bracket",
      "perforated_panel",
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

  it("неопубліковані шаблони мають порожній defaultParameters", () => {
    const unpublished = SEED_TEMPLATES.filter((t) => !t.isPublished);
    for (const t of unpublished) {
      expect(t.defaultParameters).toEqual({});
    }
  });
});
