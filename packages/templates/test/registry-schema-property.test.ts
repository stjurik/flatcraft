/**
 * Conformance-suite — schema-паритет, property-based слайс (docs/12_TEMPLATE_CONTRACT.md
 * §3.1). Повний крос-мовний прогін (TS fast-check → JSON → Python Pydantic
 * `model_validate_json`, і навпаки через hypothesis) вимагає RPC-фікстуру між
 * Node- і Python-CI-джобами (`ci.yml`: `test` і `python` — окремі jobs без
 * спільного runtime) — свідомо ВІДКЛАДЕНО до першого реального шаблону
 * (Етап 2, PR perforated_panel), коли буде конкретна схема, під яку варто
 * будувати генератор і RPC-міст, а не абстракція над порожнім реєстром.
 * ВІДОМА ПРОГАЛИНА (навмисно занесена у agy тест-інженер пас, Етап 1 run'у) —
 * див. `docs/promts/inputs/agy-conformance-gaps.md`.
 *
 * Цей слайс перевіряє те, що можна перевірити ЗАРАЗ без крос-мовного мосту:
 * JSON round-trip дефолтів кожного зареєстрованого шаблону лишається валідним
 * проти власної Zod-схеми (ловить non-JSON-serializable значення в defaults —
 * напр. `Date`/`undefined`-у-масиві — ще ДО того, як вони поїдуть у Pydantic).
 */
import fc from "fast-check";
import { describe, test } from "vitest";

import type { TemplateDefinition } from "../src/definition.js";
import { TEMPLATE_REGISTRY } from "../src/registry.js";

// Див. коментар у registry-invariants.test.ts — `never`-звуження порожнього
// реєстру потребує явного касту через entries замість keyof-індексації.
const entries = Object.entries(TEMPLATE_REGISTRY) as Array<[string, TemplateDefinition<unknown>]>;

describe.each(entries)("schema property — %s", (_slug, def) => {
  test("JSON round-trip дефолтів лишається валідним", () => {
    fc.assert(
      fc.property(fc.constant(def.defaults), (sample) => {
        const roundTripped: unknown = JSON.parse(JSON.stringify(sample));
        return def.schema.safeParse(roundTripped).success;
      }),
    );
  });
});
