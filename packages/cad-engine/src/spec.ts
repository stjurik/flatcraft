/**
 * Завантажувач bend-machine spec — єдине джерело істини про обмеження
 * листозгинальної машини. YAML живе у `data/bend-machine-esi.yaml`,
 * валідується Zod-схемою на load.
 *
 * Чому YAML, а не JSON: редагувати руками легше (коментарі, multiline).
 * Чому окрема Zod-схема, а не лише types: catch'имо помилки даних до того,
 * як вони потраплять у валідатори чи UI.
 *
 * ВАЖЛИВО (Hotfix 2.9.c): цей модуль — browser-safe. Жодних `node:fs`/`path`/
 * `process` на top-level — інакше імпорт `@flatcraft/cad-engine` у web тягне
 * Node-only код у клієнтський бандл. Файловий loader винесено у `spec-node.ts`
 * (subpath `@flatcraft/cad-engine/node`). Браузер натомість бере згенерований
 * snapshot `bakedSpec` (`generated/baked-spec.ts`, ADR-022).
 */
import { parse } from "yaml";
import { z } from "zod";

const MaterialCode = z.string().min(1);

const MachineSchema = z.object({
  vendor: z.string().min(1),
  model: z.string().min(1),
  source: z.string().min(1),
  source_date: z.string().min(1),
});

const GlobalSchema = z.object({
  max_force_t: z.number().positive(),
  min_flange_mm: z.number().positive(),
  angle_tolerance_deg: z.number().positive(),
  allowed_angles_deg: z.array(z.number().positive()).min(1),
  default_angle_deg: z.number().positive(),
});

const MaterialGroupSchema = z.object({
  members: z.array(MaterialCode).min(1),
});

const CapabilityRowSchema = z.object({
  thickness_mm: z.number().positive(),
  group: z.string().min(1),
  allowed_inner_radius_mm: z.array(z.number().positive()).min(1),
  inner_radius_max_mm: z.number().positive().optional(),
  max_bend_length_mm: z.number().positive(),
  notes: z.record(z.boolean()).optional(),
});

const RatioCorrectionSchema = z.object({
  ratio_min: z.number().nonnegative(),
  ratio_max: z.number().positive(),
  multiplier: z.number().positive(),
});

const KFactorSchema = z.object({
  default_by_material: z.record(MaterialCode, z.number().positive()),
  ratio_correction: z.array(RatioCorrectionSchema).min(1),
});

const HoleToBendDistanceSchema = z.object({
  formula: z.string().min(1),
  coefficient_by_material: z.record(MaterialCode, z.number().positive()),
});

export const BendMachineSpecSchema = z.object({
  machine: MachineSchema,
  global: GlobalSchema,
  material_groups: z.record(z.string(), MaterialGroupSchema),
  capability_matrix: z.array(CapabilityRowSchema).min(1),
  k_factor: KFactorSchema,
  hole_to_bend_distance: HoleToBendDistanceSchema,
});

export type BendMachineSpec = z.infer<typeof BendMachineSpecSchema>;

export function loadSpec(yamlText: string): BendMachineSpec {
  const parsed = parse(yamlText);
  return BendMachineSpecSchema.parse(parsed);
}
