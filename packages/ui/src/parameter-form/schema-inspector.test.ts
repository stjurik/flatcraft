import { LBracketParametersSchema } from "@flatcraft/types";
import { describe, expect, it } from "vitest";
import { z } from "zod";

import { introspectSchema, type FieldDescriptor, type NumberField } from "./schema-inspector.js";

describe("introspectSchema — атомарні випадки", () => {
  it("ZodNumber з min/max повертає NumberField з межами", () => {
    const schema = z.object({ width_mm: z.number().min(20).max(3000) });
    const [field] = introspectSchema(schema);
    expect(field).toEqual<NumberField>({
      kind: "number",
      name: "width_mm",
      min: 20,
      max: 3000,
      isInt: false,
    });
  });

  it("ZodNumber з .int() ставить isInt=true", () => {
    const schema = z.object({ count: z.number().int().min(0) });
    const [field] = introspectSchema(schema);
    expect(field).toMatchObject({ kind: "number", isInt: true, min: 0 });
  });

  it("ZodLiteral(90) → literal field", () => {
    const schema = z.object({ angle: z.literal(90) });
    const [field] = introspectSchema(schema);
    expect(field).toEqual({ kind: "literal", name: "angle", value: 90 });
  });

  it("z.union([literal(1), literal(2.5)]) → enum з options у порядку оголошення", () => {
    const schema = z.object({
      radius: z.union([z.literal(1), z.literal(2.5), z.literal(4), z.literal(5)]),
    });
    const [field] = introspectSchema(schema);
    expect(field).toEqual({
      kind: "enum",
      name: "radius",
      options: [1, 2.5, 4, 5],
    });
  });

  it("z.enum(['A', 'B']) → enum зі string options", () => {
    const schema = z.object({ leg: z.enum(["A", "B"]) });
    const [field] = introspectSchema(schema);
    expect(field).toEqual({ kind: "enum", name: "leg", options: ["A", "B"] });
  });

  it("z.array(...) → unsupported (рендериться окремим компонентом)", () => {
    const schema = z.object({ holes: z.array(z.string()) });
    const [field] = introspectSchema(schema);
    expect(field?.kind).toBe("unsupported");
    if (field?.kind === "unsupported") {
      expect(field.reason).toMatch(/array/i);
    }
  });

  it("optional/nullable wrapper розпаковуються рекурсивно", () => {
    const schema = z.object({
      maybe_count: z.number().min(0).optional(),
      maybe_radius: z.union([z.literal(1), z.literal(2)]).nullable(),
    });
    const fields = introspectSchema(schema);
    expect(fields[0]).toEqual({ kind: "number", name: "maybe_count", min: 0, isInt: false });
    expect(fields[1]).toEqual({
      kind: "enum",
      name: "maybe_radius",
      options: [1, 2],
    });
  });

  it("union із non-literal членом → unsupported (бо невідомо, як рендерити)", () => {
    const schema = z.object({
      mixed: z.union([z.literal(1), z.number()]),
    });
    const [field] = introspectSchema(schema);
    expect(field?.kind).toBe("unsupported");
  });
});

describe("group/label metadata (Phase 2.12)", () => {
  it(".describe('group:G|label:L') → FieldDescriptor.group + .label", () => {
    const schema = z.object({
      legA_mm: z.number().min(20).describe("group:Полиця A|label:Висота (мм)"),
    });
    const [field] = introspectSchema(schema);
    expect(field).toMatchObject({
      kind: "number",
      name: "legA_mm",
      min: 20,
      group: "Полиця A",
      label: "Висота (мм)",
    });
  });

  it("describe тільки з group — label лишається undefined (fallback на name)", () => {
    const schema = z.object({
      width_mm: z.number().describe("group:Загальне"),
    });
    const [field] = introspectSchema(schema);
    expect(field?.group).toBe("Загальне");
    expect(field?.label).toBeUndefined();
  });

  it("schema без .describe() → group/label undefined (legacy behaviour)", () => {
    const schema = z.object({
      width_mm: z.number().min(20),
      holes: z.array(z.string()),
    });
    const fields = introspectSchema(schema);
    expect(fields.every((f) => f.group === undefined && f.label === undefined)).toBe(true);
  });

  it("describe на array працює — unsupported field теж отримує group", () => {
    const schema = z.object({
      holes: z.array(z.string()).describe("group:Отвори|label:Отвори"),
    });
    const [field] = introspectSchema(schema);
    expect(field).toMatchObject({
      kind: "unsupported",
      name: "holes",
      group: "Отвори",
      label: "Отвори",
    });
  });

  it("describe на union літералів — group/label осідають на EnumField", () => {
    const schema = z.object({
      bend_radius_mm: z
        .union([z.literal(1), z.literal(2.5)])
        .describe("group:Гиб|label:Внутрішній радіус (мм)"),
    });
    const [field] = introspectSchema(schema);
    expect(field).toMatchObject({
      kind: "enum",
      name: "bend_radius_mm",
      options: [1, 2.5],
      group: "Гиб",
      label: "Внутрішній радіус (мм)",
    });
  });
});

describe("introspectSchema — LBracketParametersSchema (real fixture)", () => {
  it("повертає поля у порядку оголошення схеми", () => {
    const fields = introspectSchema(LBracketParametersSchema);
    const names = fields.map((f) => f.name);
    expect(names).toEqual([
      "legA_mm",
      "legB_mm",
      "bend_radius_mm",
      "bend_angle_deg",
      "width_mm",
      "holes",
    ]);
  });

  it("legA_mm — NumberField з межами 20..500", () => {
    const fields = introspectSchema(LBracketParametersSchema);
    const legA = fields.find((f): f is FieldDescriptor & NumberField => f.name === "legA_mm");
    expect(legA).toMatchObject({ kind: "number", min: 20, max: 500 });
  });

  it("bend_radius_mm — EnumField з [1, 2.5, 4, 5]", () => {
    const fields = introspectSchema(LBracketParametersSchema);
    const radius = fields.find((f) => f.name === "bend_radius_mm");
    expect(radius).toEqual({
      kind: "enum",
      name: "bend_radius_mm",
      options: [1, 2.5, 4, 5],
    });
  });

  it("bend_angle_deg — LiteralField(90)", () => {
    const fields = introspectSchema(LBracketParametersSchema);
    const angle = fields.find((f) => f.name === "bend_angle_deg");
    expect(angle).toEqual({ kind: "literal", name: "bend_angle_deg", value: 90 });
  });

  it("holes — unsupported (буде окремий holes-editor у Phase 2.5)", () => {
    const fields = introspectSchema(LBracketParametersSchema);
    const holes = fields.find((f) => f.name === "holes");
    expect(holes?.kind).toBe("unsupported");
  });
});
