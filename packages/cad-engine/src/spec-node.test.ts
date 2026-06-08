import path from "node:path";
import { fileURLToPath } from "node:url";

import { describe, expect, it } from "vitest";

import { loadSpecFromFile } from "./spec-node.js";

const DATA_PATH = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../data/bend-machine-esi.yaml",
);

describe("loadSpecFromFile (node-only subpath)", () => {
  it("дефолтно читає bend-machine-esi.yaml з пакета", async () => {
    const spec = await loadSpecFromFile();
    expect(spec.machine.model).toBe("reference-100t");
  });

  it("приймає кастомний path", async () => {
    const spec = await loadSpecFromFile(DATA_PATH);
    expect(spec.global.max_force_t).toBe(100);
  });
});
