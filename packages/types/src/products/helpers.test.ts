/**
 * Тести pure-helpers'ів products (ADR-027).
 *
 * resolveProductParams: merge + перевірки overlap'у + invalid keys.
 * filterSchemaByVisibleFields: introspection ZodObject keys vs visible list.
 */
import { describe, expect, it } from "vitest";
import { z } from "zod";

import { filterSchemaByVisibleFields, resolveProductParams } from "./helpers.js";

describe("resolveProductParams", () => {
  it("повертає merged params коли userInput у межах editable", () => {
    const result = resolveProductParams({
      fixedParameters: { thickness_mm: 1.5, material_code: "cold_rolled_steel" },
      userEditableFields: ["width_mm", "height_mm"],
      userInput: { width_mm: 200, height_mm: 300 },
    });
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.params).toEqual({
        thickness_mm: 1.5,
        material_code: "cold_rolled_steel",
        width_mm: 200,
        height_mm: 300,
      });
    }
  });

  it("обробляє порожній userInput → params = fixed", () => {
    const result = resolveProductParams({
      fixedParameters: { thickness_mm: 2 },
      userEditableFields: ["width_mm"],
      userInput: {},
    });
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.params).toEqual({ thickness_mm: 2 });
    }
  });

  it("обробляє порожній fixedParameters → params = userInput", () => {
    const result = resolveProductParams({
      fixedParameters: {},
      userEditableFields: ["width_mm"],
      userInput: { width_mm: 100 },
    });
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.params).toEqual({ width_mm: 100 });
    }
  });

  it("відхиляє ключ, якого нема у user_editable_fields (FIELD_NOT_EDITABLE)", () => {
    const result = resolveProductParams({
      fixedParameters: { thickness_mm: 2 },
      userEditableFields: ["width_mm"],
      userInput: { width_mm: 100, malicious_field: "hack" },
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.errors).toContainEqual({
        code: "FIELD_NOT_EDITABLE",
        field: "malicious_field",
      });
    }
  });

  it("відхиляє ключ, що перетинається з fixed_parameters (FIELD_IS_FIXED) — захист від обходу preset'у", () => {
    const result = resolveProductParams({
      fixedParameters: { hole_shape: "square" },
      userEditableFields: ["width_mm"],
      userInput: { hole_shape: "circle" }, // спроба змінити fixed
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.errors).toContainEqual({
        code: "FIELD_IS_FIXED",
        field: "hole_shape",
      });
    }
  });

  it("повертає МНОЖИНУ помилок при кількох порушеннях (не тільки першу)", () => {
    const result = resolveProductParams({
      fixedParameters: { hole_shape: "square" },
      userEditableFields: ["width_mm"],
      userInput: {
        hole_shape: "circle", // FIELD_IS_FIXED
        unknown_field: 42, // FIELD_NOT_EDITABLE
      },
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.errors).toHaveLength(2);
    }
  });

  it("є чистим (не мутує input)", () => {
    const fixed = { thickness_mm: 2 };
    const editable = ["width_mm"] as const;
    const input = { width_mm: 100 };

    const fixedSnapshot = JSON.stringify(fixed);
    const editableSnapshot = JSON.stringify(editable);
    const inputSnapshot = JSON.stringify(input);

    resolveProductParams({
      fixedParameters: fixed,
      userEditableFields: editable,
      userInput: input,
    });

    expect(JSON.stringify(fixed)).toBe(fixedSnapshot);
    expect(JSON.stringify(editable)).toBe(editableSnapshot);
    expect(JSON.stringify(input)).toBe(inputSnapshot);
  });

  it("детермінований (повторні виклики з однаковим input → equal output)", () => {
    const args = {
      fixedParameters: { thickness_mm: 1.5 },
      userEditableFields: ["width_mm"],
      userInput: { width_mm: 200 },
    };
    const r1 = resolveProductParams(args);
    const r2 = resolveProductParams(args);
    expect(r1).toEqual(r2);
  });

  it("FIELD_IS_FIXED має пріоритет над FIELD_NOT_EDITABLE при overlap'і — користувач має знати, що поле саме fixed (не «приховане»)", () => {
    // Якщо ключ є у fixed AND відсутній у editable (звичайний випадок),
    // помилка має бути FIELD_IS_FIXED — точніший diagnostic.
    const result = resolveProductParams({
      fixedParameters: { hole_shape: "square" },
      userEditableFields: ["width_mm"], // hole_shape не у editable
      userInput: { hole_shape: "circle" },
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.errors).toContainEqual({
        code: "FIELD_IS_FIXED",
        field: "hole_shape",
      });
      // НЕ FIELD_NOT_EDITABLE
      expect(result.errors.find((e) => e.code === "FIELD_NOT_EDITABLE")).toBeUndefined();
    }
  });
});

describe("filterSchemaByVisibleFields", () => {
  const TestSchema = z.object({
    width_mm: z.number(),
    height_mm: z.number(),
    thickness_mm: z.number(),
    material_code: z.string(),
    hole_diameter_mm: z.number(),
  });

  it("розбиває keys на visible / hidden / unknown", () => {
    const result = filterSchemaByVisibleFields(TestSchema, [
      "width_mm",
      "height_mm",
      "made_up_field",
    ]);
    expect(result.visible).toEqual(["width_mm", "height_mm"]);
    expect(result.hidden).toEqual(["thickness_mm", "material_code", "hole_diameter_mm"]);
    expect(result.unknown).toEqual(["made_up_field"]);
  });

  it("зберігає порядок visible з visibleFields (для AutoForm rendering order)", () => {
    const result = filterSchemaByVisibleFields(TestSchema, [
      "hole_diameter_mm",
      "width_mm",
      "thickness_mm",
    ]);
    expect(result.visible).toEqual(["hole_diameter_mm", "width_mm", "thickness_mm"]);
  });

  it("обробляє порожній visibleFields → всі поля у hidden", () => {
    const result = filterSchemaByVisibleFields(TestSchema, []);
    expect(result.visible).toEqual([]);
    expect(result.unknown).toEqual([]);
    expect(result.hidden).toHaveLength(5);
  });

  it("обробляє visibleFields що покриває всі поля схеми", () => {
    const result = filterSchemaByVisibleFields(TestSchema, [
      "width_mm",
      "height_mm",
      "thickness_mm",
      "material_code",
      "hole_diameter_mm",
    ]);
    expect(result.visible).toHaveLength(5);
    expect(result.hidden).toEqual([]);
    expect(result.unknown).toEqual([]);
  });

  it("обробляє visibleFields з лише невідомими полями", () => {
    const result = filterSchemaByVisibleFields(TestSchema, ["foo", "bar"]);
    expect(result.visible).toEqual([]);
    expect(result.unknown).toEqual(["foo", "bar"]);
    expect(result.hidden).toHaveLength(5);
  });

  it("обробляє дублікати у visibleFields (не видаляє — caller за збереження inваріантів)", () => {
    const result = filterSchemaByVisibleFields(TestSchema, ["width_mm", "width_mm"]);
    expect(result.visible).toEqual(["width_mm", "width_mm"]);
  });

  it("є чистим (не мутує schema/visibleFields)", () => {
    const fields = ["width_mm"];
    const snapshot = [...fields];
    filterSchemaByVisibleFields(TestSchema, fields);
    expect(fields).toEqual(snapshot);
  });

  it("працює з порожньою ZodObject схемою", () => {
    const EmptySchema = z.object({});
    const result = filterSchemaByVisibleFields(EmptySchema, ["any_field"]);
    expect(result.visible).toEqual([]);
    expect(result.hidden).toEqual([]);
    expect(result.unknown).toEqual(["any_field"]);
  });
});
