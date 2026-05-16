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
