/**
 * Export-gate: матрична валідація гибу для цілого ExportRequest (ADR-019).
 *
 * Дістає представницький bend-input із шаблону і ганяє `validateBend` проти
 * bend-machine spec, мапить помилки у RFC 9457 problem details. ОДНА реалізація,
 * яку ділять Fastify-сервер (`apps/api`, node) і браузер (`apps/web` через
 * `bakedSpec`) — раніше жила лише в apps/api і дублювалася б на клієнті
 * (Hotfix 2.9.c, ADR-022).
 *
 * Browser-safe: жодного `node:*`. Spec передається параметром (сервер читає
 * YAML через `@flatcraft/cad-engine/node`, браузер бере `bakedSpec`).
 *
 * Усі гиби в межах одного шаблону мають однакові (матеріал, товщина, радіус,
 * кут) — `bend_radius_mm`/`bend_angle_deg` спільні, `bends[]` тримає лише
 * напрям. Тож одного виклику `validateBend` достатньо для матричних перевірок.
 */
import type { ExportRequest } from "@flatcraft/types";
import { z } from "zod";

import type { BendMachineSpec } from "../spec.js";
import { validateBend, type BendInput } from "./bend.js";
import { validateProfile, type ProfileIssue } from "./profile.js";
import type { ValidationError } from "./types.js";

export const ProblemErrorSchema = z.object({
  field: z.string(),
  code: z.string(),
  value: z.unknown().optional(),
  /** Дружнє україномовне повідомлення для користувача (підказка, як виправити). */
  message: z.string().optional(),
  /** Для RADIUS_NOT_ALLOWED — допустимі радіуси для цієї товщини. */
  allowed: z.array(z.number()).optional(),
  thickness: z.number().optional(),
  material: z.string().optional(),
});
export type ProblemError = z.infer<typeof ProblemErrorSchema>;

export const ProblemDetailsSchema = z.object({
  type: z.string(),
  title: z.string(),
  status: z.number(),
  detail: z.string(),
  instance: z.string(),
  errors: z.array(ProblemErrorSchema),
});
export type ProblemDetails = z.infer<typeof ProblemDetailsSchema>;

/**
 * Дістає представницький bend-input із шаблону. `flangeMm` — сире (до setback)
 * значення найкоротшої полиці: воно завжди ≥ Zod-min, тож точну перевірку
 * полиці-після-гиба тут не робимо (out of scope матричної валідації).
 *
 * perforated_panel не має гибів → null (валідація гиба пропускається).
 */
export function bendInputFor(body: ExportRequest): BendInput | null {
  const thicknessMm = body.thickness_mm;
  const materialCode = body.material_code;

  switch (body.template_slug) {
    case "l_bracket":
    case "corner_angle": {
      const p = body.parameters;
      return {
        materialCode,
        thicknessMm,
        innerRadiusMm: p.bend_radius_mm,
        angleDeg: p.bend_angle_deg,
        flangeMm: Math.min(p.legA_mm, p.legB_mm),
        bendLengthMm: p.width_mm,
      };
    }
    case "z_bracket": {
      const p = body.parameters;
      return {
        materialCode,
        thicknessMm,
        innerRadiusMm: p.bend_radius_mm,
        angleDeg: p.bend_angle_deg,
        flangeMm: Math.min(p.top_flange_mm, p.bottom_flange_mm, p.offset_mm),
        bendLengthMm: p.width_mm,
      };
    }
    case "wall_shelf": {
      const p = body.parameters;
      const flanges = [p.back_height_mm, p.shelf_depth_mm];
      if (p.front_lip_mm > 0) flanges.push(p.front_lip_mm);
      return {
        materialCode,
        thicknessMm,
        innerRadiusMm: p.bend_radius_mm,
        angleDeg: p.bend_angle_deg,
        flangeMm: Math.min(...flanges),
        bendLengthMm: p.width_mm,
      };
    }
    case "perforated_panel":
    case "perforated_panel_square":
      // Жоден з них не має гибів → пропускаємо matrix-валідацію.
      return null;
  }
}

/**
 * Дружня підказка для недопустимого радіуса. Для дискретного набору
 * `allowed` визначаємо, замалий радіус чи завеликий, і радимо конкретну дію
 * («збільшіть» / «зменшіть» / «оберіть зі списку»).
 */
function radiusMessage(got: number, allowed: readonly number[], thickness: number): string {
  const sorted = [...allowed].sort((a, b) => a - b);
  const lo = sorted[0];
  const hi = sorted[sorted.length - 1];
  const list = sorted.join(", ");
  if (lo !== undefined && got < lo) {
    return `Збільшіть радіус гибки: для товщини ${thickness} мм мінімальний радіус ${lo} мм (дозволено: ${list} мм).`;
  }
  if (hi !== undefined && got > hi) {
    return `Зменшіть радіус гибки: для товщини ${thickness} мм максимальний радіус ${hi} мм (дозволено: ${list} мм).`;
  }
  return `Оберіть дозволений радіус гибки для товщини ${thickness} мм: ${list} мм.`;
}

function mapError(e: ValidationError, input: BendInput, spec: BendMachineSpec): ProblemError {
  switch (e.code) {
    case "bend.inner_radius_not_allowed": {
      const row = spec.capability_matrix.find((r) => r.thickness_mm === input.thicknessMm);
      const allowed = row?.allowed_inner_radius_mm ?? [];
      return {
        field: "bend_radius_mm",
        code: "RADIUS_NOT_ALLOWED",
        value: input.innerRadiusMm,
        message: radiusMessage(input.innerRadiusMm, allowed, input.thicknessMm),
        allowed: [...allowed],
        thickness: input.thicknessMm,
        material: input.materialCode,
      };
    }
    case "bend.thickness_unsupported":
      return {
        field: "thickness_mm",
        code: "THICKNESS_NOT_SUPPORTED",
        value: input.thicknessMm,
        message: `Товщина ${input.thicknessMm} мм не підтримується для гибки.`,
      };
    case "bend.material_not_in_group":
      return {
        field: "material_code",
        code: "MATERIAL_NOT_ALLOWED",
        value: input.materialCode,
        message: `Матеріал не підтримується для гибки товщиною ${input.thicknessMm} мм. Оберіть інший матеріал або товщину.`,
      };
    case "bend.angle_not_allowed":
      return {
        field: "bend_angle_deg",
        code: "ANGLE_NOT_ALLOWED",
        value: input.angleDeg,
        message: `Кут гибки ${input.angleDeg}° не підтримується.`,
      };
    case "bend.flange_too_short":
      return {
        field: "flange",
        code: "FLANGE_TOO_SHORT",
        value: input.flangeMm,
        message: "Збільшіть полицю — після гибки вона занадто коротка.",
      };
    case "bend.exceeds_max_bend_length":
      return {
        field: "width_mm",
        code: "BEND_LENGTH_EXCEEDED",
        value: input.bendLengthMm,
        message: "Зменшіть ширину — довжина лінії гибки перевищує можливості верстата.",
      };
    default:
      return { field: "unknown", code: e.code.toUpperCase().replace(/\./g, "_") };
  }
}

/** Повертає список RFC 9457 errors[] (порожній — гиб валідний). */
export function validateExportBends(body: ExportRequest, spec: BendMachineSpec): ProblemError[] {
  const input = bendInputFor(body);
  if (!input) return [];
  const result = validateBend(input, spec);
  if (result.valid) return [];
  return result.errors.map((e) => mapError(e, input, spec));
}

/** ProfileIssue → RFC 9457 ProblemError (Hotfix 2.9.f, ADR-026). */
function profileIssueToProblem(issue: ProfileIssue): ProblemError {
  return {
    field: issue.which,
    code: issue.code,
    value: issue.got,
    message: issue.message,
  };
}

/**
 * Геометрична валідність профілю для ExportRequest (Hotfix 2.9.f, ADR-026) —
 * та сама `validateProfile`, що й render-gate у браузері. Порожній масив —
 * валідно (perforated_panel завжди порожній). Дзеркало Fastify-gate ↔ браузер.
 */
export function validateExportProfile(body: ExportRequest): ProblemError[] {
  const thicknessMm = body.thickness_mm;
  switch (body.template_slug) {
    case "l_bracket":
    case "corner_angle":
      return validateProfile({
        templateSlug: body.template_slug,
        parameters: body.parameters,
        thicknessMm,
      }).map(profileIssueToProblem);
    case "z_bracket":
      return validateProfile({
        templateSlug: "z_bracket",
        parameters: body.parameters,
        thicknessMm,
      }).map(profileIssueToProblem);
    case "wall_shelf":
      return validateProfile({
        templateSlug: "wall_shelf",
        parameters: body.parameters,
        thicknessMm,
      }).map(profileIssueToProblem);
    case "perforated_panel":
    case "perforated_panel_square":
      return [];
  }
}

export function buildProblem(errors: ProblemError[], instance: string): ProblemDetails {
  const first = errors[0];
  // detail (RFC 9457 human-readable) — дружнє повідомлення першої помилки;
  // fallback на код, якщо message відсутній.
  const detail =
    first?.message ??
    (first ? `Гиб не відповідає обмеженням машини (${first.code}).` : "Validation failed");
  return {
    type: "https://flatcraft.io/errors/validation",
    title: "Validation failed",
    status: 422,
    detail,
    instance,
    errors,
  };
}
