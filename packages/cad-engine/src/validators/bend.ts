/**
 * Перевіряє один гиб (товщина + матеріал + радіус + кут + полиця + довжина).
 * Не перевіряє листову заготовку (validateSheet) і отвори (validateHoles).
 */
import type { BendMachineSpec } from "../spec.js";

import { fail, ok, type ValidationError, type ValidationResult } from "./types.js";

export interface BendInput {
  readonly materialCode: string;
  readonly thicknessMm: number;
  readonly innerRadiusMm: number;
  readonly angleDeg: number;
  /** Ширина полиці після гиба, мм. */
  readonly flangeMm: number;
  /** Довжина лінії гиба, мм. */
  readonly bendLengthMm: number;
}

export function validateBend(input: BendInput, spec: BendMachineSpec): ValidationResult {
  const row = spec.capability_matrix.find((r) => r.thickness_mm === input.thicknessMm);
  if (!row) {
    return fail({
      code: "bend.thickness_unsupported",
      message_uk: `Товщина гиба ${input.thicknessMm} мм не підтримується.`,
      message_en: `Bend thickness ${input.thicknessMm} mm is not supported.`,
      fields: ["thicknessMm"],
    });
  }

  const errors: ValidationError[] = [];

  const group = spec.material_groups[row.group];
  if (group && !group.members.includes(input.materialCode)) {
    errors.push({
      code: "bend.material_not_in_group",
      message_uk: `Матеріал ${input.materialCode} не підтримується для гиба товщиною ${input.thicknessMm} мм.`,
      message_en: `Material ${input.materialCode} is not supported for a ${input.thicknessMm} mm bend.`,
      fields: ["materialCode"],
    });
  }

  if (!row.allowed_inner_radius_mm.includes(input.innerRadiusMm)) {
    errors.push({
      code: "bend.inner_radius_not_allowed",
      message_uk: `Внутрішній радіус ${input.innerRadiusMm} мм недопустимий для товщини ${input.thicknessMm} мм. Дозволено: ${row.allowed_inner_radius_mm.join(", ")} мм.`,
      message_en: `Inner radius ${input.innerRadiusMm} mm is not allowed for ${input.thicknessMm} mm. Allowed: ${row.allowed_inner_radius_mm.join(", ")} mm.`,
      fields: ["innerRadiusMm"],
    });
  }

  if (!spec.global.allowed_angles_deg.includes(input.angleDeg)) {
    errors.push({
      code: "bend.angle_not_allowed",
      message_uk: `Кут ${input.angleDeg}° недопустимий. Дозволено: ${spec.global.allowed_angles_deg.join(", ")}°.`,
      message_en: `Angle ${input.angleDeg}° is not allowed. Allowed: ${spec.global.allowed_angles_deg.join(", ")}°.`,
      fields: ["angleDeg"],
    });
  }

  if (input.flangeMm < spec.global.min_flange_mm) {
    errors.push({
      code: "bend.flange_too_short",
      message_uk: `Полиця після гиба ${input.flangeMm} мм коротша за мінімальну ${spec.global.min_flange_mm} мм.`,
      message_en: `Flange after bend ${input.flangeMm} mm is shorter than minimum ${spec.global.min_flange_mm} mm.`,
      fields: ["flangeMm"],
    });
  }

  if (input.bendLengthMm > row.max_bend_length_mm) {
    errors.push({
      code: "bend.exceeds_max_bend_length",
      message_uk: `Довжина гиба ${input.bendLengthMm} мм перевищує максимум ${row.max_bend_length_mm} мм для товщини ${input.thicknessMm} мм.`,
      message_en: `Bend length ${input.bendLengthMm} mm exceeds max ${row.max_bend_length_mm} mm for thickness ${input.thicknessMm} mm.`,
      fields: ["bendLengthMm"],
    });
  }

  return errors.length === 0 ? ok() : fail(...errors);
}
