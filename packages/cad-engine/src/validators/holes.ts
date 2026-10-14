/**
 * Перевіряє відстань отворів від лінії гиба.
 *
 * Формула з docs/07 і bend-machine-esi.yaml:
 *   min_distance_mm = a * thickness_mm + inner_radius_mm
 * де `a` — коефіцієнт за матеріалом (2.0 для cold-rolled, 1.5 для алюмінію тощо).
 *
 * Не перевіряємо діаметр / накладання отворів / геометричні колізії —
 * це робить CadQuery isValid на сервері (Phase 1.5+).
 */
import type { BendMachineSpec } from "../spec.js";

import { fail, ok, type ValidationError, type ValidationResult } from "./types.js";

/**
 * Допуск на представлення чисел із рухомою крапкою (CLAUDE.md §7 — межа «від
 * краю»). `distanceFromBendMm` зазвичай похідне від `distance_from_bend_mm −
 * diameter_mm / 2` (export-gate.ts), і для чисел «рівно на межі» (напр.
 * 9.7 − 3.2) IEEE-754 дає 6.499999999999999 замість 6.5 — без допуску гейт
 * хибно блокує геометрично валідний отвір. 1e-9 на кілька порядків менший за
 * будь-яку значущу відстань у мм, тож справжні порушення (напр. 9.69/Ø6.4)
 * усе ще ловляться.
 */
const EDGE_DISTANCE_EPSILON_MM = 1e-9;

export interface HoleInput {
  /** Відстань від найближчого краю отвору до лінії гиба, мм. */
  readonly distanceFromBendMm: number;
  readonly diameterMm: number;
}

export interface HolesInput {
  readonly materialCode: string;
  readonly thicknessMm: number;
  readonly innerRadiusMm: number;
  readonly holes: readonly HoleInput[];
}

export function validateHoles(input: HolesInput, spec: BendMachineSpec): ValidationResult {
  const coeff = spec.hole_to_bend_distance.coefficient_by_material[input.materialCode];
  if (coeff === undefined) {
    return fail({
      code: "holes.material_coefficient_missing",
      message_uk: `Для матеріалу ${input.materialCode} немає коефіцієнта відстані отвору від гиба.`,
      message_en: `No hole-to-bend distance coefficient configured for material ${input.materialCode}.`,
      fields: ["materialCode"],
    });
  }

  const minDistance = coeff * input.thicknessMm + input.innerRadiusMm;
  const errors: ValidationError[] = [];

  input.holes.forEach((hole, idx) => {
    if (hole.distanceFromBendMm < minDistance - EDGE_DISTANCE_EPSILON_MM) {
      errors.push({
        code: "holes.too_close_to_bend",
        message_uk: `Отвір #${idx + 1}: відстань від краю до гиба ${hole.distanceFromBendMm} мм менша за мінімальну ${minDistance.toFixed(2)} мм (a×t+R = ${coeff}×${input.thicknessMm}+${input.innerRadiusMm}).`,
        message_en: `Hole #${idx + 1}: edge-to-bend distance ${hole.distanceFromBendMm} mm is below minimum ${minDistance.toFixed(2)} mm (a×t+R = ${coeff}×${input.thicknessMm}+${input.innerRadiusMm}).`,
        fields: [`holes[${idx}].distanceFromBendMm`],
      });
    }
  });

  return errors.length === 0 ? ok() : fail(...errors);
}
