/**
 * Pure-helpers для products-flow (ADR-027).
 *
 * `resolveProductParams` — merge fixed_parameters з user input у повний payload
 * для cad-worker'а. Дзеркало серверного gate'у з API §5.5: відхиляє ключі,
 * яких нема у user_editable_fields, або які перетинаються з fixed_parameters.
 *
 * `filterSchemaByVisibleFields` — introspection: розбиває keys ZodObject-схеми
 * на видимі / приховані / невідомі за списком visible_fields. Використовується
 * seed-валідатором (PR 2) і AutoForm `visible_fields` prop (PR 4, ADR-027 Рішення 4).
 *
 * Обидва flat-only для Phase 3.0. Nested-поля (`side_perforation.hole_diameter_mm`,
 * ADR-027 Рішення 5) обробляються у PR 7-8 окремим helper'ом — не lock'аємо
 * API зараз без real-flow validation.
 */
import type { z } from "zod";

// ─── resolveProductParams ──────────────────────────────────────────────────

export type ResolveProductError =
  | {
      readonly code: "FIELD_NOT_EDITABLE";
      readonly field: string;
    }
  | {
      readonly code: "FIELD_IS_FIXED";
      readonly field: string;
    };

export type ResolveProductResult =
  | { readonly ok: true; readonly params: Record<string, unknown> }
  | { readonly ok: false; readonly errors: readonly ResolveProductError[] };

export interface ResolveProductParamsInput {
  readonly fixedParameters: Record<string, unknown>;
  readonly userEditableFields: readonly string[];
  readonly userInput: Record<string, unknown>;
}

/**
 * Резолвить product-mode payload: merge(fixed, userInput) після перевірки,
 * що userInput містить лише ключі з userEditableFields і не перетинається
 * з fixedParameters.
 *
 * Інваріант: при ok=true result.params містить fixed + user (user wins
 * для overlap, але overlap = error → ok=false; тож на ok=true overlap'у
 * нема, merge детермінований).
 */
export function resolveProductParams(input: ResolveProductParamsInput): ResolveProductResult {
  const editableSet = new Set(input.userEditableFields);
  const fixedKeys = new Set(Object.keys(input.fixedParameters));
  const errors: ResolveProductError[] = [];

  for (const key of Object.keys(input.userInput)) {
    if (fixedKeys.has(key)) {
      errors.push({ code: "FIELD_IS_FIXED", field: key });
    } else if (!editableSet.has(key)) {
      errors.push({ code: "FIELD_NOT_EDITABLE", field: key });
    }
  }

  if (errors.length > 0) {
    return { ok: false, errors };
  }

  return {
    ok: true,
    params: { ...input.fixedParameters, ...input.userInput },
  };
}

// ─── filterSchemaByVisibleFields ───────────────────────────────────────────

export interface FilterSchemaResult {
  /** Поля, які у visibleFields і існують у схемі. Порядок зберігається з visibleFields. */
  readonly visible: readonly string[];
  /** Поля, що є у схемі, але НЕ у visibleFields (для product-fixed або seed-валідації). */
  readonly hidden: readonly string[];
  /** Поля, що у visibleFields, але НЕ у схемі (помилка: seed містить неіснуюче поле). */
  readonly unknown: readonly string[];
}

/**
 * Чисто інтроспективна функція: розбиває ключі ZodObject на 3 категорії
 * відносно visibleFields. Працює тільки з top-level ключами (flat).
 *
 * Використання:
 *   - seed-валідатор: `unknown` → fail (seed містить неіснуюче поле).
 *   - AutoForm visible_fields prop (PR 4): `visible` → list полів для рендеру.
 */
export function filterSchemaByVisibleFields(
  schema: z.ZodObject<z.ZodRawShape>,
  visibleFields: readonly string[],
): FilterSchemaResult {
  const schemaKeys = new Set(Object.keys(schema.shape));
  const visibleSet = new Set(visibleFields);

  const visible: string[] = [];
  const unknown: string[] = [];
  for (const field of visibleFields) {
    if (schemaKeys.has(field)) {
      visible.push(field);
    } else {
      unknown.push(field);
    }
  }

  const hidden: string[] = [];
  for (const key of Object.keys(schema.shape)) {
    if (!visibleSet.has(key)) {
      hidden.push(key);
    }
  }

  return { visible, hidden, unknown };
}
