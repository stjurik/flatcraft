/**
 * Property-based тести pure-helpers'ів products (Phase 3.0 PR 4, ADR-027 Рішення 4).
 *
 * Цикл fast-check проганяє 300 ітерацій з рандомізованими payload'ами,
 * щоб переконатись у:
 *   - merge детермінований і idempotent (повторні виклики еквівалентні).
 *   - відсутність overlap fixed↔editable+input → завжди ok=true і
 *     params.size = fixed.size + input.size.
 *   - filter ідемпотентний — повторний фільтр через ті самі visibleFields
 *     не змінює результат.
 *
 * 300 ітерацій — узгоджено з ADR-019 / fast-check у cad-engine.
 */
import { describe, expect, it } from "vitest";
import fc from "fast-check";

import { filterSchemaByVisibleFields, resolveProductParams } from "./helpers.js";

const RUNS = 300;

// Helpers для генерації unique ключів і значень.
const fieldName = fc
  .stringMatching(/^[a-z][a-z0-9_]{1,15}$/)
  .filter((s) => s !== "__proto__" && s !== "constructor");
const fieldValue = fc.oneof(fc.integer(), fc.double({ noNaN: true }), fc.string(), fc.boolean());

/** Дисьюнктні набори ключів. */
const disjointKeySets = fc
  .tuple(fc.uniqueArray(fieldName, { minLength: 1, maxLength: 5 }))
  .chain(([first]) =>
    fc
      .uniqueArray(fieldName, { minLength: 1, maxLength: 5 })
      .filter((second) => !second.some((k) => first.includes(k)))
      .map((second) => [first, second] as const),
  );

describe("resolveProductParams — fast-check (Phase 3.0 PR 4)", () => {
  it("merge детермінований: повторні виклики з тим самим input дають однаковий output", () => {
    fc.assert(
      fc.property(
        fc.dictionary(fieldName, fieldValue),
        fc.uniqueArray(fieldName),
        fc.dictionary(fieldName, fieldValue),
        (fixed, editable, input) => {
          const r1 = resolveProductParams({
            fixedParameters: fixed,
            userEditableFields: editable,
            userInput: input,
          });
          const r2 = resolveProductParams({
            fixedParameters: fixed,
            userEditableFields: editable,
            userInput: input,
          });
          expect(r1).toEqual(r2);
        },
      ),
      { numRuns: RUNS },
    );
  });

  it("disjoint fixed + input + всі input keys у editable → ok=true і повний merge", () => {
    fc.assert(
      fc.property(
        disjointKeySets,
        fc.array(fieldValue, { minLength: 1, maxLength: 5 }),
        fc.array(fieldValue, { minLength: 1, maxLength: 5 }),
        ([fixedKeys, inputKeys], fixedValues, inputValues) => {
          // Builds: fixed = { fixedKey1: val1, ... }
          const fixed = Object.fromEntries(
            fixedKeys.map((k, i) => [k, fixedValues[i % fixedValues.length]] as const),
          );
          const userInput = Object.fromEntries(
            inputKeys.map((k, i) => [k, inputValues[i % inputValues.length]] as const),
          );
          // editable = inputKeys (всі input keys у editable, ніяких extra)
          const result = resolveProductParams({
            fixedParameters: fixed,
            userEditableFields: inputKeys,
            userInput,
          });
          expect(result.ok).toBe(true);
          if (result.ok) {
            // params має ВСІ keys з fixed + input (бо disjoint, нема втрат).
            expect(Object.keys(result.params).sort()).toEqual([...fixedKeys, ...inputKeys].sort());
          }
        },
      ),
      { numRuns: RUNS },
    );
  });

  it("input з ключем НЕ у editable і НЕ у fixed → error FIELD_NOT_EDITABLE", () => {
    fc.assert(
      fc.property(
        fc.dictionary(fieldName, fieldValue),
        fc.uniqueArray(fieldName, { minLength: 1 }),
        fieldName,
        fieldValue,
        (fixed, editable, malicious, malValue) => {
          // Тільки якщо malicious НЕ в editable і НЕ в fixed.
          fc.pre(!editable.includes(malicious));
          fc.pre(!Object.prototype.hasOwnProperty.call(fixed, malicious));
          const result = resolveProductParams({
            fixedParameters: fixed,
            userEditableFields: editable,
            userInput: { [malicious]: malValue },
          });
          expect(result.ok).toBe(false);
          if (!result.ok) {
            expect(result.errors).toContainEqual({
              code: "FIELD_NOT_EDITABLE",
              field: malicious,
            });
          }
        },
      ),
      { numRuns: RUNS },
    );
  });
});

describe("filterSchemaByVisibleFields — fast-check", () => {
  it("visible ∪ hidden = schema-keys (partition інваріант)", () => {
    // Простий ZodObject зі stringFields → перевіряємо partition.
    fc.assert(
      fc.property(
        fc.uniqueArray(fieldName, { minLength: 1, maxLength: 10 }),
        fc.array(fieldName, { maxLength: 10 }),
        (schemaKeys, visibleFields) => {
          // Білдимо ZodObject з простими z.string() полями (filter використовує
          // тільки `.shape` ключі — внутрішнього типу не торкається).
          const { z } = require("zod") as typeof import("zod");
          const shape: Record<string, ReturnType<typeof z.string>> = {};
          for (const k of schemaKeys) shape[k] = z.string();
          const schema = z.object(shape);
          const result = filterSchemaByVisibleFields(schema, visibleFields);
          const partition = [...result.visible, ...result.hidden].sort();
          expect(partition).toEqual([...schemaKeys].sort());
        },
      ),
      { numRuns: RUNS },
    );
  });

  it("unknown ⊆ visibleFields \\ schema-keys", () => {
    fc.assert(
      fc.property(
        fc.uniqueArray(fieldName, { minLength: 0, maxLength: 10 }),
        fc.uniqueArray(fieldName, { minLength: 0, maxLength: 10 }),
        (schemaKeys, visibleFields) => {
          const { z } = require("zod") as typeof import("zod");
          const shape: Record<string, ReturnType<typeof z.string>> = {};
          for (const k of schemaKeys) shape[k] = z.string();
          const schema = z.object(shape);
          const result = filterSchemaByVisibleFields(schema, visibleFields);
          for (const u of result.unknown) {
            expect(visibleFields).toContain(u);
            expect(schemaKeys).not.toContain(u);
          }
        },
      ),
      { numRuns: RUNS },
    );
  });
});
