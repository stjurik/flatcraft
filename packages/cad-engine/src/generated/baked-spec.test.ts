/**
 * Hotfix 2.9.c (ADR-022): browser-safe snapshot bend-machine spec.
 *
 * Перевіряємо, що `bakedSpec` (1) валідний за тією ж Zod-схемою, що й YAML,
 * (2) збігається з YAML-джерелом байт-у-байт після парсингу, (3) не тягне
 * `node:fs` у browser-entry (source-scan).
 */
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { describe, expect, it } from "vitest";

import { bakedSpec } from "./baked-spec.js";
import { BendMachineSpecSchema, loadSpec } from "../spec.js";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const YAML_PATH = path.resolve(HERE, "../../data/bend-machine-esi.yaml");

describe("bakedSpec", () => {
  it("валідний за BendMachineSpecSchema", () => {
    expect(() => BendMachineSpecSchema.parse(bakedSpec)).not.toThrow();
  });

  it("байт-у-байт збігається з YAML-джерелом (snapshot не застарів)", () => {
    const fromYaml = loadSpec(readFileSync(YAML_PATH, "utf8"));
    expect(bakedSpec).toEqual(fromYaml);
  });

  it("містить усі рядки товщин (11) та відомий vendor", () => {
    expect(bakedSpec.capability_matrix).toHaveLength(11);
    expect(bakedSpec.machine.vendor).toBe("ТОВ ЕСІ ПРОММЕТАЛ");
  });

  it("весь browser-entry граф не імпортує node:* (інакше Next тягне fs у клієнт)", () => {
    // Кожен файл, досяжний з головного index.ts. spec-node.ts навмисно НЕ тут —
    // він живе у subpath `/node` і має право на node:fs.
    const browserGraph = [
      "../index.ts",
      "../spec.ts",
      "./baked-spec.ts",
      "../k-factor.ts",
      "../validators/index.ts",
      "../validators/bend.ts",
      "../validators/sheet.ts",
      "../validators/holes.ts",
      "../validators/types.ts",
      "../validators/export-gate.ts",
    ];
    for (const rel of browserGraph) {
      const src = readFileSync(path.resolve(HERE, rel), "utf8");
      expect(src, `${rel} must stay browser-safe`).not.toMatch(/from "node:/);
    }
  });
});
