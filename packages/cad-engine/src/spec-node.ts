/**
 * Node-only loader для bend-machine spec (subpath `@flatcraft/cad-engine/node`).
 *
 * Тут — і ТІЛЬКИ тут — живуть `node:fs`/`path`/`url`. Сервер (Fastify, cad-worker
 * tooling) читає YAML з файлу; браузер натомість імпортує `bakedSpec` із головного
 * entry. Розділ навмисний (Hotfix 2.9.c, ADR-022): головний `@flatcraft/cad-engine`
 * має лишатися browser-safe, інакше Next тягне `node:fs` у клієнтський бандл.
 */
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { loadSpec, type BendMachineSpec } from "./spec.js";

const DEFAULT_SPEC_PATH = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../data/bend-machine-esi.yaml",
);

export async function loadSpecFromFile(
  filePath: string = DEFAULT_SPEC_PATH,
): Promise<BendMachineSpec> {
  const text = await readFile(filePath, "utf8");
  return loadSpec(text);
}
