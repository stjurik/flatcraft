import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

import { describe, expect, it } from "vitest";

import { loadSpec, loadSpecFromFile } from "./spec.js";

const DATA_PATH = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../data/bend-machine-esi.yaml",
);

describe("loadSpec — happy path з реального YAML", () => {
  it("парсить bend-machine-esi.yaml і повертає типобезпечну spec", async () => {
    const yaml = await readFile(DATA_PATH, "utf8");
    const spec = loadSpec(yaml);
    expect(spec.machine.vendor).toContain("ЕСІ");
    expect(spec.global.max_force_t).toBe(100);
    expect(spec.global.min_flange_mm).toBe(7.5);
    expect(spec.global.angle_tolerance_deg).toBe(0.25);
    expect(spec.global.allowed_angles_deg).toContain(90);
    expect(spec.global.default_angle_deg).toBe(90);
  });

  it("capability_matrix покриває 11 товщин (1.0..10.0 + 1.8)", async () => {
    const yaml = await readFile(DATA_PATH, "utf8");
    const spec = loadSpec(yaml);
    const thicknesses = spec.capability_matrix.map((r) => r.thickness_mm);
    expect(thicknesses).toEqual([1.0, 1.5, 1.8, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0]);
  });

  it("k_factor.default_by_material має очікувані матеріали з doc/05", async () => {
    const yaml = await readFile(DATA_PATH, "utf8");
    const spec = loadSpec(yaml);
    expect(spec.k_factor.default_by_material.cold_rolled_steel).toBe(0.4);
    expect(spec.k_factor.default_by_material.stainless_304).toBe(0.45);
    expect(spec.k_factor.default_by_material.aluminum_5754).toBe(0.33);
  });

  it("ratio_correction містить 3 діапазони, що покривають [0, 999]", async () => {
    const yaml = await readFile(DATA_PATH, "utf8");
    const spec = loadSpec(yaml);
    const ranges = spec.k_factor.ratio_correction;
    expect(ranges).toHaveLength(3);
    expect(ranges[0]?.ratio_min).toBe(0);
    expect(ranges[ranges.length - 1]?.ratio_max).toBeGreaterThanOrEqual(999);
  });

  it("hole_to_bend_distance формула і коефіцієнти за матеріалом", async () => {
    const yaml = await readFile(DATA_PATH, "utf8");
    const spec = loadSpec(yaml);
    expect(spec.hole_to_bend_distance.formula).toBe("a * thickness_mm + inner_radius_mm");
    expect(spec.hole_to_bend_distance.coefficient_by_material.cold_rolled_steel).toBe(2.0);
    expect(spec.hole_to_bend_distance.coefficient_by_material.aluminum_5754).toBe(1.5);
  });
});

describe("loadSpec — валідація", () => {
  it("кидає на відсутньому machine.vendor", () => {
    const bad = "machine:\n  model: x\nglobal:\n  max_force_t: 100";
    expect(() => loadSpec(bad)).toThrow();
  });

  it("кидає на нечисловому max_force_t", () => {
    const yamlText = `
machine: { vendor: "x", model: "y", source: "z", source_date: "2026-05-08" }
global:
  max_force_t: "not-a-number"
  min_flange_mm: 7.5
  angle_tolerance_deg: 0.25
  allowed_angles_deg: [90]
  default_angle_deg: 90
material_groups: {}
capability_matrix: []
k_factor: { default_by_material: {}, ratio_correction: [] }
hole_to_bend_distance: { formula: "x", coefficient_by_material: {} }
`;
    expect(() => loadSpec(yamlText)).toThrow();
  });
});

describe("loadSpecFromFile", () => {
  it("дефолтно читає bend-machine-esi.yaml з пакета", async () => {
    const spec = await loadSpecFromFile();
    expect(spec.machine.model).toBe("reference-100t");
  });

  it("приймає кастомний path", async () => {
    const spec = await loadSpecFromFile(DATA_PATH);
    expect(spec.global.max_force_t).toBe(100);
  });
});
