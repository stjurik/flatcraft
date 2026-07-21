/**
 * Slug-паритет TS ↔ Python (docs/12_TEMPLATE_CONTRACT.md §3.1, ADR-033 §5) —
 * фіксований JSON-файл (`workers/cad/tests/fixtures/ts_registry_slugs.json`),
 * який `tools/scripts/export-registry.ts` генерує з `TEMPLATE_REGISTRY`.
 *
 * Цей тест — сторона TS: якщо хтось додав slug у `TEMPLATE_REGISTRY`, але
 * забув перегенерувати фікстуру (`pnpm --filter @flatcraft/templates run
 * export-registry`), CI падає ТУТ (Node-job, де є змога регенерувати).
 * Дзеркальний Python-тест (`workers/cad/tests/templates/test_registry.py`)
 * звіряє ту саму фікстуру проти `TEMPLATES.keys()` — якщо Python-реєстр
 * відстає, падає ТАМ (F6-клас бага: `enclosed_shelf` відсутній у dict).
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { describe, expect, test } from "vitest";

import { TEMPLATE_REGISTRY } from "../src/registry.js";

const fixturePath = fileURLToPath(
  new URL("../../../workers/cad/tests/fixtures/ts_registry_slugs.json", import.meta.url),
);

describe("registry fixture sync (TS ↔ Python slug parity)", () => {
  test("ts_registry_slugs.json збігається з Object.keys(TEMPLATE_REGISTRY)", () => {
    const fixture = JSON.parse(readFileSync(fixturePath, "utf-8")) as string[];
    const actual = Object.keys(TEMPLATE_REGISTRY).sort();
    expect([...fixture].sort()).toEqual(actual);
  });
});
