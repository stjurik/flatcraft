/**
 * Перевіряє заготовку (товщина, матеріал, габарити) проти bend-machine spec.
 *
 * Що НЕ перевіряємо тут:
 *   - Геометричні колізії / перетин отворів — це сервер-side у Python (CadQuery isValid).
 *   - Відстань отворів від лінії гиба — окремий validateHoles.
 *   - Радіус гиба / кут — validateBend.
 */
import type { BendMachineSpec } from "../spec.js";

import { fail, ok, type ValidationResult } from "./types.js";

export interface SheetInput {
  readonly materialCode: string;
  readonly thicknessMm: number;
  readonly widthMm: number;
  readonly heightMm: number;
}

export function validateSheet(input: SheetInput, spec: BendMachineSpec): ValidationResult {
  const row = spec.capability_matrix.find((r) => r.thickness_mm === input.thicknessMm);
  if (!row) {
    const supported = spec.capability_matrix.map((r) => r.thickness_mm).join(", ");
    return fail({
      code: "sheet.thickness_unsupported",
      message_uk: `Товщина ${input.thicknessMm} мм не підтримується. Доступні: ${supported}.`,
      message_en: `Thickness ${input.thicknessMm} mm is not supported. Available: ${supported}.`,
      fields: ["thicknessMm"],
    });
  }

  const errors = [];

  const group = spec.material_groups[row.group];
  if (group && !group.members.includes(input.materialCode)) {
    errors.push({
      code: "sheet.material_not_in_group",
      message_uk: `Матеріал ${input.materialCode} не підтримується для товщини ${input.thicknessMm} мм.`,
      message_en: `Material ${input.materialCode} is not supported for thickness ${input.thicknessMm} mm.`,
      fields: ["materialCode"],
    });
  }

  const maxDim = Math.max(input.widthMm, input.heightMm);
  if (maxDim > row.max_bend_length_mm) {
    errors.push({
      code: "sheet.exceeds_max_bend_length",
      message_uk: `Найбільший габарит ${maxDim} мм перевищує максимальну довжину гиба ${row.max_bend_length_mm} мм для товщини ${input.thicknessMm} мм.`,
      message_en: `Largest dimension ${maxDim} mm exceeds max bend length ${row.max_bend_length_mm} mm for thickness ${input.thicknessMm} mm.`,
      fields: ["widthMm", "heightMm"],
    });
  }

  return errors.length === 0 ? ok() : fail(...errors);
}
