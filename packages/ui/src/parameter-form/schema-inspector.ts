/**
 * Pure інтроспекція Zod-схем у FieldDescriptor-список — основа AutoForm.
 *
 * Phase 2.4 покриває скалярні типи, які реально використовуються у MVP-шаблонах:
 *   - ZodNumber з checks (min/max/step/int).
 *   - ZodLiteral (renders як read-only або hidden).
 *   - ZodEnum (string union).
 *   - ZodUnion з ZodLiteral-варіантів (number radio/select).
 * Решта (ZodArray, ZodObject) — `unsupported` дескриптор, AutoForm покаже
 * предупередження. Реальний holes-editor — окремий компонент (Phase 2.5).
 */
import { z } from "zod";

export interface NumberField {
  readonly kind: "number";
  readonly name: string;
  readonly min?: number;
  readonly max?: number;
  readonly step?: number;
  readonly isInt: boolean;
}

export interface EnumField {
  readonly kind: "enum";
  readonly name: string;
  /** Список допустимих значень, у порядку оголошення. */
  readonly options: ReadonlyArray<number | string>;
}

export interface LiteralField {
  readonly kind: "literal";
  readonly name: string;
  readonly value: number | string | boolean;
}

export interface UnsupportedField {
  readonly kind: "unsupported";
  readonly name: string;
  readonly reason: string;
}

export type FieldDescriptor = NumberField | EnumField | LiteralField | UnsupportedField;

interface NumberCheck {
  readonly kind: string;
  readonly value?: number;
}

function describeNumber(name: string, def: z.ZodNumberDef): NumberField {
  const checks: ReadonlyArray<NumberCheck> = def.checks ?? [];
  const min = checks.find((c) => c.kind === "min")?.value;
  const max = checks.find((c) => c.kind === "max")?.value;
  const step = checks.find((c) => c.kind === "multipleOf")?.value;
  const isInt = checks.some((c) => c.kind === "int");
  return {
    kind: "number",
    name,
    ...(min !== undefined ? { min } : {}),
    ...(max !== undefined ? { max } : {}),
    ...(step !== undefined ? { step } : {}),
    isInt,
  };
}

/**
 * `z.union([z.literal(1), z.literal(2.5), ...])` — типовий випадок для
 * фіксованих наборів (наприклад, allowed_inner_radius_mm). Розпаковуємо
 * у EnumField.
 */
function tryLiteralUnion(name: string, schema: z.ZodTypeAny): EnumField | null {
  if (!(schema instanceof z.ZodUnion)) return null;
  const literals: Array<number | string> = [];
  for (const option of schema._def.options as z.ZodTypeAny[]) {
    if (!(option instanceof z.ZodLiteral)) return null;
    const value = option._def.value;
    if (typeof value !== "number" && typeof value !== "string") return null;
    literals.push(value);
  }
  return { kind: "enum", name, options: literals };
}

function describeField(name: string, schema: z.ZodTypeAny): FieldDescriptor {
  if (schema instanceof z.ZodNumber) {
    return describeNumber(name, schema._def);
  }
  if (schema instanceof z.ZodEnum) {
    return { kind: "enum", name, options: schema._def.values as ReadonlyArray<string> };
  }
  if (schema instanceof z.ZodLiteral) {
    const value = schema._def.value;
    if (typeof value === "number" || typeof value === "string" || typeof value === "boolean") {
      return { kind: "literal", name, value };
    }
    return { kind: "unsupported", name, reason: "literal type is not primitive" };
  }
  const unionEnum = tryLiteralUnion(name, schema);
  if (unionEnum) return unionEnum;
  if (schema instanceof z.ZodOptional || schema instanceof z.ZodNullable) {
    return describeField(name, schema._def.innerType as z.ZodTypeAny);
  }
  if (schema instanceof z.ZodArray) {
    return { kind: "unsupported", name, reason: "array fields rendered by dedicated editor" };
  }
  if (schema instanceof z.ZodObject) {
    return { kind: "unsupported", name, reason: "nested object — потребує групи полів" };
  }
  return {
    kind: "unsupported",
    name,
    reason: `unhandled Zod type: ${schema._def.typeName ?? "?"}`,
  };
}

/**
 * Інтроспекує top-level ZodObject у плоский список FieldDescriptor.
 * Порядок — за оголошенням у схемі (Object.entries(shape) stable у V8).
 */
export function introspectSchema(schema: z.ZodObject<z.ZodRawShape>): FieldDescriptor[] {
  const shape = schema.shape;
  return Object.entries(shape).map(([name, field]) => describeField(name, field));
}
