/**
 * Обчислення K-фактора для розгортки гиба.
 *
 * K = K_base(material) * multiplier(ratio)
 * де ratio = innerRadiusMm / thicknessMm,
 *    multiplier береться з ratio_correction діапазонів у bend-machine spec
 *    (за стандартною інтерпретацією — [ratio_min, ratio_max) inclusive lower).
 *
 * Жорсткі помилки (throw) на невідомому матеріалі / нульовій товщині —
 * ці кейси повинні відсікатися на рівні Zod-валідації або validateBend.
 * computeKFactor — це math kernel, не повертає ValidationResult.
 */
import type { BendMachineSpec } from "./spec.js";

export interface KFactorInput {
  readonly materialCode: string;
  readonly thicknessMm: number;
  readonly innerRadiusMm: number;
}

export function computeKFactor(input: KFactorInput, spec: BendMachineSpec): number {
  if (input.thicknessMm <= 0) {
    throw new Error(`computeKFactor: thicknessMm must be > 0, got ${input.thicknessMm}`);
  }
  if (input.innerRadiusMm < 0) {
    throw new Error(`computeKFactor: innerRadiusMm must be >= 0, got ${input.innerRadiusMm}`);
  }

  const baseK = spec.k_factor.default_by_material[input.materialCode];
  if (baseK === undefined) {
    const available = Object.keys(spec.k_factor.default_by_material).join(", ");
    throw new Error(
      `computeKFactor: no base K-factor for material "${input.materialCode}". Available: ${available}`,
    );
  }

  const ratio = input.innerRadiusMm / input.thicknessMm;
  const correction = spec.k_factor.ratio_correction.find(
    (r) => ratio >= r.ratio_min && ratio < r.ratio_max,
  );
  if (!correction) {
    throw new Error(
      `computeKFactor: ratio R/S = ${ratio.toFixed(3)} is outside any configured ratio_correction range`,
    );
  }

  return baseK * correction.multiplier;
}

/**
 * Bend allowance (довжина матеріалу по нейтральній осі гиба), мм.
 *
 * BA = (π/180) · angle · (R + K·t). Дзеркало Python
 * `workers/cad/flatcraft_cad/unfold.py::compute_bend_allowance` — та сама
 * формула, яку розгортка воркера використовує для кожного шаблону. Export-gate
 * (`validateExportSheet`) викликає цю ОДНУ функцію для всіх шаблонів замість
 * дублювання формули BA по кожному з них (як і сам unfold.py робить).
 *
 * Валідація діапазонів — як у Python-версії (однакові межі → throw на тому ж
 * вхідному сміттю). Real-world виклики з export-gate завжди йдуть із вже
 * Zod-валідованих параметрів, тож throw тут практично недосяжний.
 */
export function computeBendAllowanceMm(
  angleDeg: number,
  innerRadiusMm: number,
  thicknessMm: number,
  kFactor: number,
): number {
  if (!(angleDeg > 0 && angleDeg <= 180)) {
    throw new Error(`computeBendAllowanceMm: angleDeg must be in (0, 180], got ${angleDeg}`);
  }
  if (innerRadiusMm < 0) {
    throw new Error(`computeBendAllowanceMm: innerRadiusMm must be >= 0, got ${innerRadiusMm}`);
  }
  if (thicknessMm <= 0) {
    throw new Error(`computeBendAllowanceMm: thicknessMm must be > 0, got ${thicknessMm}`);
  }
  if (!(kFactor > 0 && kFactor <= 1)) {
    throw new Error(`computeBendAllowanceMm: kFactor must be in (0, 1], got ${kFactor}`);
  }

  return (Math.PI / 180) * angleDeg * (innerRadiusMm + kFactor * thicknessMm);
}
