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
  it("Phase 3.0 PR 2 містить лише seed placeholder", () => {
    expect(SEED_PRODUCTS).toHaveLength(1);
    expect(SEED_PRODUCTS[0]?.slug).toBe("seed-placeholder");
  });

  it("placeholder НЕ опублікований (не потрапляє у catalog API)", () => {
    expect(SEED_PRODUCTS.every((p) => !p.isPublished)).toBe(true);
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
});
