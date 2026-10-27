/**
 * Enclosed shelf — TemplateDefinition (ADR-033).
 *
 * Run 7 Master Registry Track, Етап 2 — шоста (остання) міграція (docs/12 §6
 * PR 8). Джерело поведінки — наявні
 * `apps/web/src/components/enclosed-shelf-{studio,editor,viewport}.tsx` +
 * `packages/ui/src/3d-viewport/enclosed-shelf-scene.tsx` (сцена лишається —
 * підключається через `@flatcraft/ui` `COMPOSED_SCENES['enclosed_shelf']`,
 * той самий підхід, що й wall_shelf/corner_angle/perforated_panel).
 *
 * `kind: "composed"` — 4-5 BoxGeometry-сегментів (bottom/back/left/right +
 * опційний rib), не 2D-профіль (cross-розгортка, не лінійний unfold).
 *
 * `bends`, `side_perforation`, `stiffening_rib` — поза generic AutoForm
 * (масив напрямів і вкладені nullable-об'єкти): паритет з наявним
 * `EnclosedShelfParametersSchema.omit({ bends: true, side_perforation: true,
 * stiffening_rib: true })` у видаленому `enclosed-shelf-editor.tsx`.
 *
 * `validators` (issue #237 п.2, render-gate ADR-026; доробка #275 — рецензії
 * Flash і Argon Medium, PR #275#issuecomment-6410942324): на відміну від
 * l_bracket/z_bracket/wall_shelf/corner_angle/perforated_panel,
 * `validateProfile` НЕ підтримує `templateSlug: "enclosed_shelf"` (нема
 * запису у `ProfileValidationInput` union,
 * `packages/cad-engine/src/validators/profile.ts`) — те саме задокументоване
 * рішення вже лежить у `export-gate.ts` (`case "enclosed_shelf": return []`)
 * і в `template-studio.tsx` (`SLUGS_WITH_PROFILE` не містить
 * `enclosed_shelf`). CLAUDE.md §7 забороняє чіпати render-gate
 * `validateProfile` цією задачею — тож тут НЕ profile-валідатор, а чотири
 * інші, що НЕ потребують cross-розгортки:
 *   - `schemaValidator` — Zod `.safeParse` проти `EnclosedShelfParametersSchema`
 *     (діапазони width_mm/depth_mm/stiffening_rib.height_mm, literal
 *     bend_angle_deg) — те, що раніше відсіювалось лише на API/сервері, render-gate
 *     тепер ловить ДО рендера сцени (студія не мала показувати 3D на
 *     width_mm=50 — сервер усе одно заблокував би експорт, UI розходився);
 *   - `thicknessSupportedValidator` — товщина має рядок у
 *     `bakedSpec.capability_matrix` (лише наявність `thickness_mm`, БЕЗ пари з
 *     радіусом — студія не має бути суворішою за `export-gate.ts`, де
 *     bend-матрична перевірка для `enclosed_shelf` теж не чіпається цією
 *     задачею);
 *   - `stiffeningRibValidator` — Argon-контрприклад 1: `height_mm <= t + r`
 *     дає `flat_rib_y <= 0` у `unfold.py` (`_build_enclosed_shelf_cross`,
 *     `workers/cad/flatcraft_cad/unfold.py:799-805`) → `ValueError`, 500 у
 *     воркері (`server.py:345` поза `try`, окреме issue #283 — тут лише
 *     render-gate, без серверного боку);
 *   - `sidePerforationValidator` — Argon-контрприклади 2 і 3: `side_rect.w_mm`
 *     у `_enclosed_shelf_side_holes` (`unfold.py:626-640`) — це
 *     `depth_mm - (t + r)`, не `depth_mm` (3D-сцена рахує отвори від повного
 *     `depth_mm` — те саме розходження, що й розгортка з 0 отворів); а
 *     `pitch_x/y_mm <= hole_size_mm` чи `margin_mm < hole_size_mm / 2` дають
 *     отвори, що зливаються або виходять за контур боковини (DXF
 *     `export/dxf.py:384-391` малює їх як є, без перевірки).
 */
import { bakedSpec, type ProblemError } from "@flatcraft/cad-engine";
import { ENCLOSED_SHELF_DEFAULT_PARAMETERS, EnclosedShelfParametersSchema } from "@flatcraft/types";
import type { EnclosedShelfParameters } from "@flatcraft/types";
import type { z } from "zod";

import type { ProfileValidator, TemplateDefinition } from "../definition.js";

/** Округлення до 0.001 мм без хвостових нулів — для повідомлень. */
function fmt(n: number): string {
  return String(Math.round(n * 1000) / 1000);
}

/**
 * Zod-валідатор поверх повної `EnclosedShelfParametersSchema` (діапазони,
 * literal `bend_angle_deg: 90`) — `ProblemError.field` = `issue.path.join(".")`
 * (без префіксів, напр. `stiffening_rib.height_mm`). Повідомлення — сирий
 * Zod `issue.message`, не доменна підказка: `RegistryTemplateEditor` вже
 * показує той самий Zod-issue через `zodErrorStrings` (`def.schema.safeParse`),
 * тож `allErrors` дедуплікує за `field` (Flash #1, `registry-template-editor.tsx`),
 * щоб користувач не бачив той самий constraint двічі різними рядками.
 */
const schemaValidator: ProfileValidator<EnclosedShelfParameters> = (params) => {
  const result = EnclosedShelfParametersSchema.safeParse(params);
  if (result.success) return [];
  return result.error.issues.map((issue) => ({
    field: issue.path.join("."),
    code: "INVALID_PARAMETER",
    message: issue.message,
  }));
};

/**
 * Товщина має рядок у bend-matrix — лише наявність `thickness_mm`, БЕЗ пари з
 * радіусом (та перевірка лишається серверу, `validateExportBends`/
 * `export-gate.ts`, щоб студія не стала суворішою за експорт).
 */
const thicknessSupportedValidator: ProfileValidator<EnclosedShelfParameters> = (
  _params,
  thicknessMm,
) => {
  const supported = bakedSpec.capability_matrix.some((row) => row.thickness_mm === thicknessMm);
  if (supported) return [];
  return [
    {
      field: "thickness_mm",
      code: "THICKNESS_NOT_SUPPORTED",
      value: thicknessMm,
      message: `Товщина ${thicknessMm} мм не підтримується верстатом.`,
    },
  ];
};

/**
 * Ребро жорсткості (front lip, опційний 4-й гиб) — Argon-контрприклад 1
 * (PR #275#issuecomment-6410942324): `unfold.py:799-805` рахує
 * `flat_rib_y = height_mm - (t + r)` і кидає `ValueError` при
 * `flat_rib_y <= 0`, тобто `height_mm <= t + r` — той самий inclusive-порядок,
 * що й `rib_height`/`back_height` у `packages/cad-engine/src/validators/profile.ts`
 * (`FLANGE_TOO_SHORT`, `<=` → invalid).
 */
const stiffeningRibValidator: ProfileValidator<EnclosedShelfParameters> = (params, thicknessMm) => {
  const rib = params.stiffening_rib;
  if (!rib) return [];
  const min = thicknessMm + params.bend_radius_mm;
  if (rib.height_mm > min) return [];
  return [
    {
      field: "stiffening_rib.height_mm",
      code: "FLANGE_TOO_SHORT",
      value: rib.height_mm,
      message:
        `Збільшіть «Висота ребра» до більше ${fmt(min)} мм ` +
        `(товщина ${fmt(thicknessMm)} + радіус ${fmt(params.bend_radius_mm)}) — ` +
        `інакше гиб ребра вироджується (нульова чи від'ємна полиця після гибу).`,
    },
  ];
};

/**
 * Перфорація боковин (опційна) — Argon-контрприклади 2 і 3
 * (PR #275#issuecomment-6410942324). Межі боковини для отворів —
 * `side_rect.w_mm = depth_mm - (t + r)` у `_enclosed_shelf_side_holes`
 * (`unfold.py:626-640`, викликається з `left`/`right` rect
 * `unfold.py:755-788`), НЕ повний `depth_mm` — 3D-сцена (`enclosed-shelf-scene.tsx`)
 * бере повний `depth_mm`, тож без цього валідатора студія показує отвори, яких
 * розгортка не дає (margin занадто великий → 0 отворів), або отвори, що
 * зливаються/виходять за межі боковини в DXF/PDF.
 */
const sidePerforationValidator: ProfileValidator<EnclosedShelfParameters> = (
  params,
  thicknessMm,
) => {
  const sp = params.side_perforation;
  if (!sp) return [];
  const issues: ProblemError[] = [];

  const effSideWidth = params.depth_mm - (thicknessMm + params.bend_radius_mm);
  if (2 * sp.margin_mm > effSideWidth) {
    issues.push({
      field: "side_perforation.margin_mm",
      code: "HOLES_NO_ROOM",
      value: sp.margin_mm,
      message:
        `Зменшіть «Відступ від країв»: при глибині ${fmt(params.depth_mm)} мм і гибі ` +
        `(товщина ${fmt(thicknessMm)} + радіус ${fmt(params.bend_radius_mm)}) робоча ширина ` +
        `боковини — ${fmt(effSideWidth)} мм, а відступ ${fmt(sp.margin_mm)} мм з обох боків не влазить.`,
    });
  }

  const axisLabel: Record<"pitch_x_mm" | "pitch_y_mm", string> = {
    pitch_x_mm: "Pitch X",
    pitch_y_mm: "Pitch Y",
  };
  for (const axis of ["pitch_x_mm", "pitch_y_mm"] as const) {
    const pitch = sp[axis];
    if (pitch <= sp.hole_size_mm) {
      issues.push({
        field: `side_perforation.${axis}`,
        code: "HOLES_OVERLAP",
        value: pitch,
        message:
          `Збільшіть «${axisLabel[axis]}»: крок ${fmt(pitch)} мм має бути більший за сторону ` +
          `отвору ${fmt(sp.hole_size_mm)} мм — інакше сусідні отвори перетинаються.`,
      });
    }
  }

  const minMargin = sp.hole_size_mm / 2;
  if (sp.margin_mm < minMargin) {
    issues.push({
      field: "side_perforation.margin_mm",
      code: "HOLES_OUT_OF_BOUNDS",
      value: sp.margin_mm,
      message:
        `Збільшіть «Відступ від країв» до мінімум ${fmt(minMargin)} мм ` +
        `(половина сторони отвору ${fmt(sp.hole_size_mm)} мм) — інакше отвір виходить за межі боковини.`,
    });
  }

  return issues;
};

/** Summary — паритет з наявним `enclosed-shelf-editor.tsx` (testId `enclosed-shelf-summary`). */
function shelfSummary(p: EnclosedShelfParameters): string {
  const bendCount = p.stiffening_rib ? 4 : 3;
  return p.side_perforation
    ? `${bendCount} гиби UP · перфорація боковин ${p.side_perforation.hole_size_mm}мм`
    : `${bendCount} гиби UP · без перфорації`;
}

// Паритет з наявним `EnclosedShelfParametersSchema.omit({ bends: true,
// side_perforation: true, stiffening_rib: true })` у видаленому
// enclosed-shelf-editor.tsx: масив напрямів і 2 вкладені nullable-об'єкти —
// поза generic AutoForm.
const HIDDEN_FIELDS = new Set(["bends", "side_perforation", "stiffening_rib"]);
const VISIBLE_FIELDS = Object.keys(EnclosedShelfParametersSchema.shape).filter(
  (field) => !HIDDEN_FIELDS.has(field),
);

export const enclosedShelfDefinition: TemplateDefinition<EnclosedShelfParameters> = {
  slug: "enclosed_shelf",
  process: "sheet_metal",
  labels: { uk: "Закрита полиця", en: "Enclosed shelf" },
  // Каст: `bends`/`side_perforation`/`stiffening_rib` мають `.default(...)` →
  // Zod input-тип з опційними полями ≠ output-тип (EnclosedShelfParameters,
  // звідки undefined виключено, z.infer бере output-бік) — та сама номінальна
  // невідповідність варіантності, що й у z-bracket/corner-angle/wall-shelf.
  schema: EnclosedShelfParametersSchema as unknown as z.ZodType<EnclosedShelfParameters>,
  defaults: ENCLOSED_SHELF_DEFAULT_PARAMETERS,
  ui: {
    scene: { kind: "composed" },
    extraControls: [{ kind: "summary", render: shelfSummary, testId: "enclosed-shelf-summary" }],
    visibleFields: VISIBLE_FIELDS,
    thumbSlug: "enclosed_shelf",
  },
  validators: [
    schemaValidator,
    thicknessSupportedValidator,
    stiffeningRibValidator,
    sidePerforationValidator,
  ],
  capabilities: ["bends"],
};
