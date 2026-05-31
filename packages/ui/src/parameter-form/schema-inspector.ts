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
 *
 * Phase 2.12 (ADR-017): кожне поле може отримати .group / .label з Zod
 * `_def.description` у форматі `group:G|label:L`. Невідомі ключі — ігнор.
 */
import { z } from "zod";

interface CommonMeta {
  /** Назва секції (fieldset/legend) у редакторі. */
  readonly group?: string;
  /** Лейбл поля (override до AutoFormLabels). */
  readonly label?: string;
}

export interface NumberField extends CommonMeta {
  readonly kind: "number";
  readonly name: string;
  readonly min?: number;
  readonly max?: number;
  readonly step?: number;
  readonly isInt: boolean;
}

export interface EnumField extends CommonMeta {
  readonly kind: "enum";
  readonly name: string;
  /** Список допустимих значень, у порядку оголошення. */
  readonly options: ReadonlyArray<number | string>;
}

export interface LiteralField extends CommonMeta {
  readonly kind: "literal";
  readonly name: string;
  readonly value: number | string | boolean;
}

export interface UnsupportedField extends CommonMeta {
  readonly kind: "unsupported";
  readonly name: string;
  readonly reason: string;
}

export type FieldDescriptor = NumberField | EnumField | LiteralField | UnsupportedField;

/**
 * Парсить `.describe("group:G|label:L")` у структуру. Невідомі ключі
 * ігноруємо мовчки — це не валідаційний контракт, а метадані рендеру.
 * Пробіли навколо `:` і `|` обрізаються; значення можуть містити пробіли.
 */
export function parseDescription(text: string | undefined): CommonMeta {
  if (!text) return {};
  const result: { group?: string; label?: string } = {};
  for (const part of text.split("|")) {
    const idx = part.indexOf(":");
    if (idx < 0) continue;
    const key = part.slice(0, idx).trim();
    const value = part.slice(idx + 1).trim();
    if (!value) continue;
    if (key === "group") result.group = value;
    else if (key === "label") result.label = value;
  }
  return result;
}

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

function describeFieldRaw(name: string, schema: z.ZodTypeAny): FieldDescriptor {
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
    return describeFieldRaw(name, schema._def.innerType as z.ZodTypeAny);
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
 * Wrapper що накладає group/label з `.describe(...)`. Description лежить
 * на безпосередньому schema (а не у внутрішньому wrapped) — тому читаємо
 * з `schema.description` ПЕРЕД рекурсією у innerType (optional/nullable).
 */
function describeField(name: string, schema: z.ZodTypeAny): FieldDescriptor {
  const meta = parseDescription(schema.description);
  const raw = describeFieldRaw(name, schema);
  return { ...raw, ...meta } as FieldDescriptor;
}

/**
 * Інтроспекує top-level ZodObject у плоский список FieldDescriptor.
 * Порядок — за оголошенням у схемі (Object.entries(shape) stable у V8).
 */
export function introspectSchema(schema: z.ZodObject<z.ZodRawShape>): FieldDescriptor[] {
  const shape = schema.shape;
  return Object.entries(shape).map(([name, field]) => describeField(name, field));
}
