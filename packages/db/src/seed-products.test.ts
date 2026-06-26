/**
 * Перевіряє форму SEED_PRODUCTS. Інтеграційний тест (вставка у реальну Postgres)
 * — у migrate/seed integration suite з DATABASE_URL.
 *
 * Phase 3.0 PR 2: тільки placeholder, isPublished=false (для unit-flow).
 * Реальні products — у PR 6/8 за master prompt'ом.
 */
import { describe, expect, it } from "vitest";

import { PRODUCT_SLUG_REGEX } from "@flatcraft/types";

import { SEED_PRODUCTS } from "./seed-products.js";

describe("SEED_PRODUCTS", () => {
  it("Phase 3.0 PR 8b: 3 products — placeholder + perforated-panel-decorative + closed-shelf-standard", () => {
    expect(SEED_PRODUCTS).toHaveLength(3);
    const slugs = SEED_PRODUCTS.map((p) => p.slug).sort();
    expect(slugs).toEqual([
      "closed-shelf-standard",
      "perforated-panel-decorative",
      "seed-placeholder",
    ]);
  });

  it("placeholder НЕ опублікований; решта (perfo-decorative, closed-shelf-standard) — опубліковані", () => {
    const published = SEED_PRODUCTS.filter((p) => p.isPublished)
      .map((p) => p.slug)
      .sort();
    expect(published).toEqual(["closed-shelf-standard", "perforated-panel-decorative"]);
  });

  it("кожен product має унікальний slug (UNIQUE constraint у БД)", () => {
    const slugs = SEED_PRODUCTS.map((p) => p.slug);
    expect(new Set(slugs).size).toBe(SEED_PRODUCTS.length);
  });

  it("slug кожного product — kebab-case ASCII (ADR-027 інваріант)", () => {
    for (const p of SEED_PRODUCTS) {
      expect(PRODUCT_SLUG_REGEX.test(p.slug)).toBe(true);
    }
  });

  it("кожен product має base_template_slug (інваріант ADR-027)", () => {
    for (const p of SEED_PRODUCTS) {
      expect(p.baseTemplateSlug.length).toBeGreaterThan(0);
    }
  });

  it("user_editable_fields і fixed_parameters НЕ перетинаються (ADR-027 інваріант)", () => {
    for (const p of SEED_PRODUCTS) {
      const fixedKeys = new Set(Object.keys(p.fixedParameters));
      const overlap = p.userEditableFields.filter((f) => fixedKeys.has(f));
      expect(overlap).toEqual([]);
    }
  });

  it("perforated-panel-decorative використовує perforated_panel base (ADR-031)", () => {
    const product = SEED_PRODUCTS.find((p) => p.slug === "perforated-panel-decorative");
    expect(product).toBeDefined();
    expect(product?.baseTemplateSlug).toBe("perforated_panel");
    // Геометрія + висота ребра редаговані; форма отвору фіксована (квадрат).
    expect(product?.userEditableFields).toEqual([
      "length_mm",
      "width_mm",
      "hole_size_mm",
      "pitch_x_mm",
      "pitch_y_mm",
      "margin_mm",
      "rib_height_mm",
    ]);
    expect(product?.fixedParameters).toEqual({ hole_shape: "square" });
    expect(product?.useCases).toEqual(["інтер'єр", "офіс", "дім"]);
  });

  it("closed-shelf-standard використовує enclosed_shelf base (Phase 3.0 PR 8b)", () => {
    const product = SEED_PRODUCTS.find((p) => p.slug === "closed-shelf-standard");
    expect(product).toBeDefined();
    expect(product?.baseTemplateSlug).toBe("enclosed_shelf");
    // Лише геометричні параметри редаговані; bends/side_perforation/stiffening_rib
    // лишаються у дефолтах (опціональні features — не у PR 8b формі).
    expect(product?.userEditableFields).toEqual(["width_mm", "depth_mm", "bend_radius_mm"]);
    expect(product?.fixedParameters).toEqual({});
    expect(product?.isPublished).toBe(true);
  });
});
