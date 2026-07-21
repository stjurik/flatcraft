/**
 * export-registry.ts (ADR-033 §5 CONSEQUENCES) — генерує
 * `workers/cad/tests/fixtures/ts_registry_slugs.json` з `TEMPLATE_REGISTRY`.
 *
 * Джерело істини для slug-паритету TS ↔ Python (docs/12_TEMPLATE_CONTRACT.md
 * §3.1): TS-тест (`packages/templates/test/registry-fixture-sync.test.ts`) і
 * Python-тест (`workers/cad/tests/templates/test_registry.py`) звіряють свій
 * реєстр проти цієї самої фікстури. Ганяти вручну після зміни
 * `TEMPLATE_REGISTRY`: `pnpm --filter @flatcraft/templates run export-registry`.
 */
import { mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { TEMPLATE_REGISTRY } from "../../packages/templates/src/registry.js";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "../..");
const OUT_DIR = path.join(ROOT, "workers/cad/tests/fixtures");
const OUT_PATH = path.join(OUT_DIR, "ts_registry_slugs.json");

function main(): void {
  const slugs = Object.keys(TEMPLATE_REGISTRY).sort();
  mkdirSync(OUT_DIR, { recursive: true });
  writeFileSync(OUT_PATH, `${JSON.stringify(slugs, null, 2)}\n`, "utf8");
  console.info(`Wrote ${slugs.length} slug(s) to ${path.relative(ROOT, OUT_PATH)}`);
}

main();
