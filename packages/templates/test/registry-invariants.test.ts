/**
 * Conformance-suite — структурні інваріанти + render-gate (docs/12_TEMPLATE_CONTRACT.md
 * §3.3). Автогенерується з `Object.keys(TEMPLATE_REGISTRY)` — з порожнім
 * реєстром (Run 7 Етап 1) іде 0 ітерацій `describe.each` (зелено, не пропуск:
 * `test.each([])` не реєструє жодного test-case, і vitest не падає завдяки
 * `--passWithNoTests` на рівні пакета; коли Етап 2 додасть перший slug —
 * перевірки одразу стають активними без правок цього файлу).
 */
import { describe, expect, test } from "vitest";

import type { TemplateDefinition } from "../src/definition.js";
import { TEMPLATE_REGISTRY } from "../src/registry.js";

// `TEMPLATE_REGISTRY` типізовано як `{} as const satisfies Record<...>`
// (ADR-033 §1) — з порожнім реєстром `keyof typeof TEMPLATE_REGISTRY` є
// `never`, тож індексація `TEMPLATE_REGISTRY[slug]` теж звузилась би до
// `never`. `Object.entries` + явний каст тримає тестовий файл валідним
// незалежно від того, скільки slug'ів зараз у реєстрі.
const entries = Object.entries(TEMPLATE_REGISTRY) as Array<[string, TemplateDefinition<unknown>]>;

describe.each(entries)("registry invariants — %s", (slug, def) => {
  test("slug у визначенні збігається з ключем реєстру", () => {
    expect(def.slug).toBe(slug);
  });

  test("defaults проходять власну schema", () => {
    expect(def.schema.safeParse(def.defaults).success).toBe(true);
  });

  test("capabilities непорожній", () => {
    expect(def.capabilities.length).toBeGreaterThan(0);
  });

  test("render-gate: усі валідатори мовчать на дефолтних параметрах", () => {
    for (const validator of def.validators) {
      expect(validator(def.defaults, 2)).toHaveLength(0);
    }
  });

  test("render-gate: явно неможлива товщина стрельне хоча б одним валідатором (якщо валідатори є)", () => {
    if (def.validators.length === 0) return;
    const issues = def.validators.flatMap((validator) => validator(def.defaults, 999));
    expect(issues.length).toBeGreaterThan(0);
  });
});

test("TEMPLATE_REGISTRY — ключі об'єкта збігаються зі slug кожного визначення", () => {
  for (const [key, def] of entries) {
    expect(def.slug).toBe(key);
  }
});
