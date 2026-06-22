/**
 * Тести Zod-схем `products` (ADR-027).
 *
 * Парадигма: round-trip parse валідного payload + reject невалідних
 * (slug-формат, відсутні обов'язкові поля, неправильні типи).
 */
import { describe, expect, it } from "vitest";

import {
  PRODUCT_SLUG_REGEX,
  ProductDetailSchema,
  ProductListResponseSchema,
  ProductSummarySchema,
} from "./product.js";

const VALID_SUMMARY = {
  slug: "perforated-panel-decorative",
  name: "Декоративна перфо-панель",
  description: "Стильна декоративна перфо-панель для інтер'єру.",
  baseTemplateSlug: "perforated_panel_square",
  previewImageUrl: "/product-previews/perforated-panel-decorative.png",
  useCases: ["інтер'єр", "офіс", "дім"],
  isPublished: true,
} as const;

const VALID_TEMPLATE_DETAIL = {
  id: "550e8400-e29b-41d4-a716-446655440000",
  slug: "perforated_panel_square",
  nameUk: "Перфорована панель (квадратні отвори)",
  nameEn: "Perforated panel (square holes)",
  descriptionUk: "Перфорація з квадратними отворами.",
  descriptionEn: "Perforated panel with square holes.",
  version: 1,
  previewImageUrl: null,
  isPublished: false,
  createdAt: "2026-06-22T00:00:00.000Z",
  updatedAt: "2026-06-22T00:00:00.000Z",
  parametersSchema: {},
  defaultParameters: { width_mm: 200, height_mm: 200 },
} as const;

describe("ProductSummarySchema", () => {
  it("приймає валідний summary", () => {
    const parsed = ProductSummarySchema.safeParse(VALID_SUMMARY);
    expect(parsed.success).toBe(true);
  });

  it("приймає description = null", () => {
    const parsed = ProductSummarySchema.safeParse({ ...VALID_SUMMARY, description: null });
    expect(parsed.success).toBe(true);
  });

  it("приймає previewImageUrl = null (для drafts без рендера)", () => {
    const parsed = ProductSummarySchema.safeParse({ ...VALID_SUMMARY, previewImageUrl: null });
    expect(parsed.success).toBe(true);
  });

  it("приймає use_cases = [] (продукт без тегів)", () => {
    const parsed = ProductSummarySchema.safeParse({ ...VALID_SUMMARY, useCases: [] });
    expect(parsed.success).toBe(true);
  });

  it("відхиляє slug у CamelCase (ADR-027 — kebab-case ASCII)", () => {
    const parsed = ProductSummarySchema.safeParse({ ...VALID_SUMMARY, slug: "PerforatedPanel" });
    expect(parsed.success).toBe(false);
  });

  it("відхиляє slug з underscore (templates pattern, не products)", () => {
    const parsed = ProductSummarySchema.safeParse({
      ...VALID_SUMMARY,
      slug: "perforated_panel_decorative",
    });
    expect(parsed.success).toBe(false);
  });

  it("відхиляє пустий name (NOT NULL інваріант)", () => {
    const parsed = ProductSummarySchema.safeParse({ ...VALID_SUMMARY, name: "" });
    expect(parsed.success).toBe(false);
  });

  it("відхиляє пустий baseTemplateSlug", () => {
    const parsed = ProductSummarySchema.safeParse({ ...VALID_SUMMARY, baseTemplateSlug: "" });
    expect(parsed.success).toBe(false);
  });
});

describe("PRODUCT_SLUG_REGEX", () => {
  it("приймає валідні slug'и", () => {
    expect(PRODUCT_SLUG_REGEX.test("perforated-panel-decorative")).toBe(true);
    expect(PRODUCT_SLUG_REGEX.test("wall-shelf-custom")).toBe(true);
    expect(PRODUCT_SLUG_REGEX.test("a")).toBe(true);
    expect(PRODUCT_SLUG_REGEX.test("a1b2c3")).toBe(true);
  });

  it("відхиляє невалідні", () => {
    expect(PRODUCT_SLUG_REGEX.test("")).toBe(false);
    expect(PRODUCT_SLUG_REGEX.test("Capital")).toBe(false);
    expect(PRODUCT_SLUG_REGEX.test("under_score")).toBe(false);
    expect(PRODUCT_SLUG_REGEX.test("-leading-dash")).toBe(false);
    expect(PRODUCT_SLUG_REGEX.test("1-leading-digit")).toBe(false);
    expect(PRODUCT_SLUG_REGEX.test("with space")).toBe(false);
  });
});

describe("ProductListResponseSchema", () => {
  it("приймає порожній list", () => {
    const parsed = ProductListResponseSchema.safeParse({ items: [] });
    expect(parsed.success).toBe(true);
  });

  it("приймає list з одним продуктом", () => {
    const parsed = ProductListResponseSchema.safeParse({ items: [VALID_SUMMARY] });
    expect(parsed.success).toBe(true);
  });

  it("відхиляє items не-масив", () => {
    const parsed = ProductListResponseSchema.safeParse({ items: "not-array" });
    expect(parsed.success).toBe(false);
  });
});

describe("ProductDetailSchema", () => {
  const VALID_DETAIL = {
    ...VALID_SUMMARY,
    fixedParameters: { thickness_mm: 1.5, material_code: "cold_rolled_steel" },
    userEditableFields: ["width_mm", "height_mm", "hole_diameter_mm"],
    baseTemplate: VALID_TEMPLATE_DETAIL,
  };

  it("приймає валідний detail з resolved baseTemplate", () => {
    const parsed = ProductDetailSchema.safeParse(VALID_DETAIL);
    expect(parsed.success).toBe(true);
  });

  it("приймає fixed_parameters порожній об'єкт (всі поля редаговані)", () => {
    const parsed = ProductDetailSchema.safeParse({ ...VALID_DETAIL, fixedParameters: {} });
    expect(parsed.success).toBe(true);
  });

  it("приймає nested-поля з dot-notation у userEditableFields", () => {
    const parsed = ProductDetailSchema.safeParse({
      ...VALID_DETAIL,
      userEditableFields: ["width_mm", "side_perforation.hole_diameter_mm"],
    });
    expect(parsed.success).toBe(true);
  });

  it("відхиляє userEditableFields = [] (інваріант: продукт мусить мати щось редаговане)", () => {
    // Phase 3.0 не enforce'ить інваріант на Zod-рівні — це seed-валідатор.
    // Але пустий масив все одно валідний як shape.
    const parsed = ProductDetailSchema.safeParse({ ...VALID_DETAIL, userEditableFields: [] });
    expect(parsed.success).toBe(true);
  });

  it("відхиляє userEditableFields з пустим рядком", () => {
    const parsed = ProductDetailSchema.safeParse({
      ...VALID_DETAIL,
      userEditableFields: ["width_mm", ""],
    });
    expect(parsed.success).toBe(false);
  });

  it("відхиляє відсутній baseTemplate", () => {
    const { baseTemplate: _omit, ...withoutBase } = VALID_DETAIL;
    const parsed = ProductDetailSchema.safeParse(withoutBase);
    expect(parsed.success).toBe(false);
  });
});
