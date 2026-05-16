import { describe, expect, it } from "vitest";

import { TemplateListResponseSchema, TemplateSummarySchema } from "./template.js";

const validTemplate = {
  id: "11111111-2222-3333-4444-555555555555",
  slug: "l_bracket",
  nameUk: "L-кронштейн",
  nameEn: "L-bracket",
  descriptionUk: "Кутник з двох полиць.",
  descriptionEn: "Two-flange bracket.",
  version: 1,
  previewImageUrl: null,
  isPublished: true,
  createdAt: "2026-05-16T00:00:00.000Z",
  updatedAt: "2026-05-16T00:00:00.000Z",
} as const;

describe("TemplateSummarySchema", () => {
  it("приймає валідний DTO", () => {
    expect(() => TemplateSummarySchema.parse(validTemplate)).not.toThrow();
  });

  it("приймає null у description і preview", () => {
    expect(() =>
      TemplateSummarySchema.parse({
        ...validTemplate,
        descriptionUk: null,
        descriptionEn: null,
        previewImageUrl: null,
      }),
    ).not.toThrow();
  });

  it("відхиляє не-uuid id", () => {
    expect(() => TemplateSummarySchema.parse({ ...validTemplate, id: "not-uuid" })).toThrow();
  });

  it("відхиляє порожній slug", () => {
    expect(() => TemplateSummarySchema.parse({ ...validTemplate, slug: "" })).toThrow();
  });

  it("відхиляє нечисловий version", () => {
    expect(() => TemplateSummarySchema.parse({ ...validTemplate, version: 0 })).toThrow();
    expect(() => TemplateSummarySchema.parse({ ...validTemplate, version: -1 })).toThrow();
  });

  it("відхиляє невалідний preview URL", () => {
    expect(() =>
      TemplateSummarySchema.parse({ ...validTemplate, previewImageUrl: "not a url" }),
    ).toThrow();
  });

  it("приймає валідний preview URL", () => {
    expect(() =>
      TemplateSummarySchema.parse({
        ...validTemplate,
        previewImageUrl: "https://example.com/preview.png",
      }),
    ).not.toThrow();
  });
});

describe("TemplateListResponseSchema", () => {
  it("приймає порожній список", () => {
    expect(() => TemplateListResponseSchema.parse({ items: [] })).not.toThrow();
  });

  it("приймає список з валідних шаблонів", () => {
    expect(() =>
      TemplateListResponseSchema.parse({ items: [validTemplate, validTemplate] }),
    ).not.toThrow();
  });

  it("відхиляє якщо один елемент невалідний", () => {
    expect(() =>
      TemplateListResponseSchema.parse({ items: [validTemplate, { ...validTemplate, id: "x" }] }),
    ).toThrow();
  });
});
