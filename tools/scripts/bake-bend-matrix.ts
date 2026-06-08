/**
 * bake-bend-matrix.ts (Hotfix 2.9.c, ADR-022)
 *
 * Читає єдине джерело істини `packages/cad-engine/data/bend-machine-esi.yaml`,
 * валідує його через `loadSpec` (та сама Zod-схема, що й рантайм) і запікає у
 * типізований TS-модуль `packages/cad-engine/src/generated/baked-spec.ts`.
 *
 * Навіщо: браузер (web-студії) не має доступу до `node:fs`, тож не може читати
 * YAML. Замість руками-дубльованої матриці він імпортує цей snapshot. YAML
 * лишається ЄДИНИМ джерелом — `bakedSpec` завжди похідний.
 *
 * Коли ганяється: `prebuild` пакета cad-engine (та опційно вручну через
 * `pnpm --filter @flatcraft/cad-engine bake`). Згенерований файл також комічений,
 * тож тести зелені без build-кроку; prebuild лише гарантує свіжість.
 */
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { loadSpec } from "../../packages/cad-engine/src/spec.js";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "../..");
const YAML_PATH = path.join(ROOT, "packages/cad-engine/data/bend-machine-esi.yaml");
const OUT_DIR = path.join(ROOT, "packages/cad-engine/src/generated");
const OUT_PATH = path.join(OUT_DIR, "baked-spec.ts");

function main(): void {
  const yamlText = readFileSync(YAML_PATH, "utf8");
  // Валідуємо через ту саму схему — крихта в YAML впаде тут, а не у браузері.
  const spec = loadSpec(yamlText);

  const banner = [
    "/**",
    " * ⚠️  ЗГЕНЕРОВАНО АВТОМАТИЧНО — НЕ РЕДАГУВАТИ ВРУЧНУ.",
    " *",
    " * Джерело: packages/cad-engine/data/bend-machine-esi.yaml",
    " * Генератор: tools/scripts/bake-bend-matrix.ts (prebuild, ADR-022).",
    " *",
    " * Browser-safe snapshot bend-machine spec для клієнтської валідації матриці",
    " * гибу (Hotfix 2.9.c). Щоб змінити — правте YAML і запустіть bake, не цей файл.",
    " */",
  ].join("\n");

  const body =
    `import type { BendMachineSpec } from "../spec.js";\n\n` +
    `export const bakedSpec: BendMachineSpec = ${JSON.stringify(spec, null, 2)};\n`;

  mkdirSync(OUT_DIR, { recursive: true });
  writeFileSync(OUT_PATH, `${banner}\n\n${body}`, "utf8");

  // eslint-disable-next-line no-console
  console.log(
    `baked ${spec.capability_matrix.length} thickness rows → ${path.relative(ROOT, OUT_PATH)}`,
  );
}

main();
