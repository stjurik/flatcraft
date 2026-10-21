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

import { computeBendAllowanceMm, computeKFactor } from "../k-factor.js";
import type { BendMachineSpec } from "../spec.js";
import { validateBend, type BendInput } from "./bend.js";
import { validateHoles, type HoleInput } from "./holes.js";
import { validatePerforation, type PerforationIssue } from "./perforation.js";
import { validateProfile, type ProfileIssue } from "./profile.js";
import { validateSheet } from "./sheet.js";
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
 * Перфо-панель (ADR-031) — ребристий лоток з 4 гибами → bend-input береться.
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
    case "perforated_panel": {
      // ADR-030/031: ребриста монтажна панель — 4 однакові 90° гиби (ребра).
      // flangeMm = rib_height; лінія гибу найдовша = max(length, width).
      const p = body.parameters;
      return {
        materialCode,
        thicknessMm,
        innerRadiusMm: p.bend_radius_mm,
        angleDeg: p.bend_angle_deg,
        flangeMm: p.rib_height_mm,
        bendLengthMm: Math.max(p.length_mm, p.width_mm),
      };
    }
    case "enclosed_shelf": {
      // Phase 3.0 PR 7c: 3-4 UP-bends, всі однакові radius/angle. flangeMm
      // — depth_mm (мінімальна сторона back/sides). Rib не bend-flange (мала
      // смужка), у matrix-валідації нерелевантна.
      const p = body.parameters;
      return {
        materialCode,
        thicknessMm,
        innerRadiusMm: p.bend_radius_mm,
        angleDeg: p.bend_angle_deg,
        flangeMm: p.depth_mm,
        bendLengthMm: p.width_mm,
      };
    }
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

/**
 * ProfileIssue → RFC 9457 ProblemError (Hotfix 2.9.f, ADR-026). Export —
 * реєстрові `ProfileValidator<Params>` (ADR-033 §1, `packages/templates`)
 * перевикористовують цю саму мапу, замість дублювання (Run 7 Етап 2).
 */
export function profileIssueToProblem(issue: ProfileIssue): ProblemError {
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
 * валідно. Дзеркало Fastify-gate ↔ браузер.
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
      // ADR-030/031: ребриста монтажна панель — перевіряємо rib_height > t+r.
      return validateProfile({
        templateSlug: "perforated_panel",
        parameters: body.parameters,
        thicknessMm,
      }).map(profileIssueToProblem);
    case "enclosed_shelf":
      // Phase 3.0 PR 7c: profile-валідатор для cross-розгортки поки не
      // моделюється (no flange-after-bend перевірка — depth_mm уже >=100 і
      // bend reduces by t+r≤~6мм, гарантовано >0). Zod-min ranges відсіюють
      // невалідне ще на API. Якщо знадобиться — додаємо у наступному hotfix.
      return [];
  }
}

/** PerforationIssue → RFC 9457 ProblemError. Export — див. `profileIssueToProblem`. */
export function perforationIssueToProblem(issue: PerforationIssue): ProblemError {
  return {
    field: issue.which,
    code: issue.code,
    value: issue.got,
    message: issue.message,
  };
}

/**
 * Геометрична коректність grid перфорації для ExportRequest — та сама
 * `validatePerforation`, що й клієнтський банер. Порожній масив — валідно
 * (усі шаблони без перфорації). Дзеркало Fastify-gate ↔ браузер ↔ Python.
 */
export function validateExportPerforation(body: ExportRequest): ProblemError[] {
  switch (body.template_slug) {
    case "perforated_panel":
      return validatePerforation({
        templateSlug: "perforated_panel",
        parameters: body.parameters as unknown as Readonly<Record<string, number | string>>,
      }).map(perforationIssueToProblem);
    default:
      return [];
  }
}

/** Округлює до 3 знаків і прибирає хвостові нулі — для дружніх повідомлень (6.50 → 6.5). */
function fmtMm(n: number): string {
  return Number(n.toFixed(3)).toString();
}

interface SheetDimensionsMm {
  readonly widthMm: number;
  readonly heightMm: number;
}

/**
 * Bend allowance для (матеріал, товщина, радіус, кут) з export-gate'у — тим
 * самим K-фактором, яким воркер реально будує розгортку (рішення yurii
 * 2026-10-14 «1а», issue #246, ADR-043): `computeKFactor` бере базове K
 * матеріалу з `k_factor.default_by_material` × `ratio_correction(R/t)`, та
 * сама функція, яку `workers/cad/flatcraft_cad/server.py` викликає перед
 * кожним `unfold_*`. Раніше тут був фіксований константний K, однаковий для
 * всіх материалів (той самий, що й старий Pydantic-дефолт воркера); тепер
 * дефолту в воркера немає, `material_code` ОБОВ'ЯЗКОВИЙ в обох, тож гейт і
 * воркер завжди рахують однаковий K. На Zod-валідованих параметрах (реальний
 * шлях) завжди успішний;
 * `null` — лише захист від throw на (теоретично) неможливому вході
 * (невідомий матеріал чи ratio поза діапазоном — інший валідатор
 * (`validateExportBends`/`MATERIAL_NOT_ALLOWED`) уже звітує реальну причину).
 */
function tryComputeBendAllowanceMm(
  materialCode: string,
  thicknessMm: number,
  innerRadiusMm: number,
  angleDeg: number,
  spec: BendMachineSpec,
): number | null {
  try {
    const kFactor = computeKFactor({ materialCode, thicknessMm, innerRadiusMm }, spec);
    return computeBendAllowanceMm(angleDeg, innerRadiusMm, thicknessMm, kFactor);
  } catch {
    return null;
  }
}

/**
 * Габарит розгортки (ширина × висота) для ExportRequest — та сама формула, що
 * й `workers/cad/flatcraft_cad/unfold.py` (кожен `unfold_*`), не грубе
 * «сума полиць без BA». CLAUDE.md §7 п.4: «габарит у площі заготовки ≤ 3050».
 * K-фактор — за матеріалом (`computeKFactor`, ADR-043), тож `spec`
 * обов'язковий параметр.
 *
 * `null` — шаблон геометрично невалідний (полиці закороткі для гибу) або
 * K-фактор нерахований (невідомий матеріал/ratio поза діапазоном): інший
 * валідатор (`validateExportProfile`/`validateExportBends`) уже звітує про
 * реальну причину.
 */
export function sheetDimensionsFor(
  body: ExportRequest,
  spec: BendMachineSpec,
): SheetDimensionsMm | null {
  const t = body.thickness_mm;
  const material = body.material_code;

  switch (body.template_slug) {
    case "l_bracket":
    case "corner_angle": {
      const p = body.parameters;
      const r = p.bend_radius_mm;
      const ba = tryComputeBendAllowanceMm(material, t, r, p.bend_angle_deg, spec);
      if (ba === null) return null;
      const flatA = p.legA_mm - t - r;
      const flatB = p.legB_mm - t - r;
      return { widthMm: p.width_mm, heightMm: flatB + ba + flatA };
    }
    case "z_bracket": {
      const p = body.parameters;
      const r = p.bend_radius_mm;
      const ba = tryComputeBendAllowanceMm(material, t, r, p.bend_angle_deg, spec);
      if (ba === null) return null;
      const flatBottom = p.bottom_flange_mm - t - r;
      const flatMiddle = p.offset_mm - t - r;
      const flatTop = p.top_flange_mm - t - r;
      return { widthMm: p.width_mm, heightMm: flatBottom + ba + flatMiddle + ba + flatTop };
    }
    case "wall_shelf": {
      const p = body.parameters;
      const r = p.bend_radius_mm;
      const ba = tryComputeBendAllowanceMm(material, t, r, p.bend_angle_deg, spec);
      if (ba === null) return null;
      const lipPresent = p.front_lip_mm > 0;
      const flatBack = p.back_height_mm - t - r;
      const flatShelf = p.shelf_depth_mm - (t + r) - (lipPresent ? t + r : 0);
      const heightMm = lipPresent
        ? flatBack + ba + flatShelf + ba + (p.front_lip_mm - t - r)
        : flatBack + ba + flatShelf;
      return { widthMm: p.width_mm, heightMm };
    }
    case "perforated_panel": {
      // Хрест-розгортка (ADR-030/031): 4 ребра однакової висоти → симетричний
      // відступ (ba+flange) з усіх боків центральної площини.
      const p = body.parameters;
      const r = p.bend_radius_mm;
      const ba = tryComputeBendAllowanceMm(material, t, r, p.bend_angle_deg, spec);
      if (ba === null) return null;
      const flange = p.rib_height_mm - (t + r);
      return {
        widthMm: p.length_mm + 2 * (ba + flange),
        heightMm: p.width_mm + 2 * (ba + flange),
      };
    }
    case "enclosed_shelf": {
      // Cross-розгортка (ADR-027 Рішення 5): bottom + back + left + right
      // [+ опц. rib]. bbox — по unfold_enclosed_shelf (left/right симетричні).
      //
      // left/right звисають за межі bottom/back навіть БЕЗ ребра:
      // `leftYOffset = (flatBottomY - depth_mm) / 2` < 0, тож min/max беремо
      // по всіх сегментах (bottom, back, left/right, опц. rib), а не лише по
      // back+bottom (Hotfix — раніше «низ» рахувався від 0, занижуючи
      // габарит на (t+r)/2).
      const p = body.parameters;
      const r = p.bend_radius_mm;
      const ba = tryComputeBendAllowanceMm(material, t, r, p.bend_angle_deg, spec);
      if (ba === null) return null;
      const tr = t + r;
      const flatLeftRight = p.depth_mm - tr;
      const widthMm = p.width_mm - 2 * tr + 2 * ba + 2 * flatLeftRight;
      const ribPresent = p.stiffening_rib !== null;
      const flatBottomY = p.depth_mm - tr - (ribPresent ? tr : 0);
      const flatBackY = p.depth_mm - tr;
      const leftYOffset = (flatBottomY - p.depth_mm) / 2;
      const topCandidates = [flatBottomY, flatBottomY + ba + flatBackY, leftYOffset + p.depth_mm];
      const bottomCandidates = [0, leftYOffset];
      if (ribPresent) {
        bottomCandidates.push(-(ba + (p.stiffening_rib!.height_mm - tr)));
      }
      const heightMm = Math.max(...topCandidates) - Math.min(...bottomCandidates);
      return { widthMm, heightMm };
    }
  }
}

function sheetErrorToProblem(e: ValidationError, dims: SheetDimensionsMm): ProblemError {
  if (e.code === "sheet.exceeds_max_bend_length") {
    const maxDim = Math.max(dims.widthMm, dims.heightMm);
    return {
      field: "width_mm",
      code: "SHEET_EXCEEDS_MAX_LENGTH",
      value: Number(maxDim.toFixed(2)),
      message: `Зменшіть габарити деталі: розгорнута заготовка (${fmtMm(maxDim)} мм) перевищує максимальну довжину гиба верстата для цієї товщини.`,
    };
  }
  if (e.code === "sheet.thickness_unsupported") {
    return { field: "thickness_mm", code: "THICKNESS_NOT_SUPPORTED", message: e.message_uk };
  }
  if (e.code === "sheet.material_not_in_group") {
    return { field: "material_code", code: "MATERIAL_NOT_ALLOWED", message: e.message_uk };
  }
  return { field: "unknown", code: e.code.toUpperCase().replace(/\./g, "_") };
}

/**
 * Габарит розгортки vs можливості верстата для ExportRequest (CLAUDE.md §7
 * п.4) — обгортка `validateSheet` навколо `sheetDimensionsFor`. Порожній
 * масив — валідно (разом з усіма 6 шаблонами; `null` від `sheetDimensionsFor`
 * також дає []).
 *
 * Невідома товщина → [] тут: `validateExportBends` (bend-гейт) уже звітує
 * `THICKNESS_NOT_SUPPORTED` для будь-якого шаблону з bend-полями — без цього
 * early-return той самий код дублювався б двічі в `errors[]` (паритет з
 * Python `validate_sheet`, рядок «row is None → []»).
 *
 * Матеріал поза групою рядка матриці для цієї товщини (issue #257 п.3):
 * `validateExportBends` уже звітує `MATERIAL_NOT_ALLOWED`, тож із результату
 * `validateSheet` відкидаємо лише цей код (решта — зокрема перевищення габариту
 * — лишається); інакше `validateSheet` нижче додав би
 * ТОЙ САМИЙ код удруге (власна перевірка групи у `sheet.ts`). Паритет —
 * Python `validate_sheet` (`validate/sheet.py`).
 */
export function validateExportSheet(body: ExportRequest, spec: BendMachineSpec): ProblemError[] {
  const dims = sheetDimensionsFor(body, spec);
  if (!dims) return [];
  const row = spec.capability_matrix.find((r) => r.thickness_mm === body.thickness_mm);
  if (!row) return [];
  const result = validateSheet(
    {
      materialCode: body.material_code,
      thicknessMm: body.thickness_mm,
      widthMm: dims.widthMm,
      heightMm: dims.heightMm,
    },
    spec,
  );
  if (result.valid) return [];
  // Матеріал поза групою звітує validateExportBends (MATERIAL_NOT_ALLOWED) —
  // тут відкидаємо лише його, а перевищення габариту лишається (#257 п.3;
  // ранній return губив SHEET_EXCEEDS_MAX_LENGTH — контрприклади Argon до #273).
  return result.errors
    .filter((e) => e.code !== "sheet.material_not_in_group")
    .map((e) => sheetErrorToProblem(e, dims));
}

interface HolesContext {
  readonly materialCode: string;
  readonly thicknessMm: number;
  readonly innerRadiusMm: number;
  readonly rawHoles: ReadonlyArray<{
    readonly distance_from_bend_mm: number;
    readonly diameter_mm: number;
  }>;
}

/**
 * Лише l_bracket і z_bracket мають поле `holes[].distance_from_bend_mm`
 * (corner_angle/wall_shelf — auto-grid без цього поля; perforated_panel/
 * enclosed_shelf — отвори не прив'язані до конкретного гиба). Інші слаги → null.
 */
function holesContextFor(body: ExportRequest): HolesContext | null {
  switch (body.template_slug) {
    case "l_bracket":
    case "z_bracket": {
      const p = body.parameters;
      return {
        materialCode: body.material_code,
        thicknessMm: body.thickness_mm,
        innerRadiusMm: p.bend_radius_mm,
        rawHoles: p.holes,
      };
    }
    default:
      return null;
  }
}

function holeErrorToProblem(
  e: ValidationError,
  ctx: HolesContext,
  spec: BendMachineSpec,
): ProblemError {
  if (e.code !== "holes.too_close_to_bend") {
    return {
      field: "material_code",
      code: "HOLE_MATERIAL_COEFFICIENT_MISSING",
      message: e.message_uk,
    };
  }
  const idxMatch = /holes\[(\d+)\]/.exec(e.fields[0] ?? "");
  const idx = idxMatch?.[1] !== undefined ? Number(idxMatch[1]) : 0;
  const hole = ctx.rawHoles[idx];
  const coeff = spec.hole_to_bend_distance.coefficient_by_material[ctx.materialCode] ?? 0;
  const minEdgeMm = coeff * ctx.thicknessMm + ctx.innerRadiusMm;
  const diameterMm = hole?.diameter_mm ?? 0;
  const currentCenterMm = hole?.distance_from_bend_mm ?? 0;
  const minCenterMm = minEdgeMm + diameterMm / 2;
  return {
    field: `holes[${idx}].distance_from_bend_mm`,
    code: "HOLE_TOO_CLOSE_TO_BEND",
    value: currentCenterMm,
    // Рішення yurii 2026-10-11: правило — від краю отвору, але поле у
    // студії/API — від центру (UX). Повідомлення говорить мовою поля, яке
    // користувач бачить: перераховуємо мінімум-від-краю у мінімум-від-центру
    // для цього конкретного діаметра.
    message:
      `Відсуньте отвір №${idx + 1} від лінії гиба: від краю отвору до гиба має бути ` +
      `не менше ${fmtMm(minEdgeMm)} мм, тобто від центру Ø${fmtMm(diameterMm)} — не менше ` +
      `${fmtMm(minCenterMm)} мм (зараз ${fmtMm(currentCenterMm)} мм).`,
  };
}

/**
 * Відстань отворів від лінії гиба (docs/07 §3, CLAUDE.md §7) — l_bracket і
 * z_bracket. Поле `distance_from_bend_mm` — від ЦЕНТРУ отвору (Zod-схема, UI),
 * фізичне правило — від НАЙБЛИЖЧОГО КРАЮ (рішення yurii 2026-10-11, заміняє
 * рішення 2026-10-06). Перераховуємо центр → край ТУТ, в одному місці, перед
 * викликом `validateHoles` — сама `validateHoles` лишається «від краю».
 */
export function validateExportHoles(body: ExportRequest, spec: BendMachineSpec): ProblemError[] {
  const ctx = holesContextFor(body);
  if (!ctx) return [];

  const holes: HoleInput[] = ctx.rawHoles.map((h) => ({
    distanceFromBendMm: h.distance_from_bend_mm - h.diameter_mm / 2,
    diameterMm: h.diameter_mm,
  }));
  const result = validateHoles(
    {
      materialCode: ctx.materialCode,
      thicknessMm: ctx.thicknessMm,
      innerRadiusMm: ctx.innerRadiusMm,
      holes,
    },
    spec,
  );
  if (result.valid) return [];
  return result.errors.map((e) => holeErrorToProblem(e, ctx, spec));
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
