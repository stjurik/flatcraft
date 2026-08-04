/**
 * Z-кронштейн — TemplateDefinition (ADR-033).
 *
 * Run 7 Master Registry Track, Етап 2 — четверта міграція (docs/12 §6 PR 6).
 * Джерело поведінки — наявні
 * `apps/web/src/components/z-bracket-{studio,editor,viewport}.tsx` +
 * `packages/ui/src/3d-viewport/z-bracket-scene.tsx` (усі видалені цим PR).
 * На відміну від l_bracket, `z-bracket-scene.tsx` не мав жодного незалежного
 * консюмера поза Template Registry (нема hero-demo-подібного споживача) —
 * тому DoD `docs/12` §6 (рядок 295, `~~<slug>-scene.tsx~~`) виконано ПОВНІСТЮ
 * для z_bracket, на відміну від l_bracket (issue #93 — окремий tech-debt).
 *
 * `kind: "extrude"` — чистий 2D-контур (3 секції, 2 round inner bends) без
 * декорацій, той самий патерн, що й l_bracket. `build` — тонка обгортка над
 * `buildZBracketShapeCommands` (`@flatcraft/cad-engine/geometry`, переїхала
 * туди цим PR з `packages/ui`).
 *
 * `bends` (масив напрямів 2 гибів, дефолт [down, up]) — рендериться лише на
 * кресленні (Hotfix 2.10.e), не в редакторі: паритет з наявним
 * `ZBracketParametersSchema.omit({ bends: true })`. `holes` (ручний масив,
 * не auto-grid) — AutoForm не має array-редактора (Phase 2.7 placeholder),
 * той самий підхід, що й l_bracket: приховано з `visibleFields`, показано
 * через `extraControls` summary з тим самим testId (`auto-form-holes-placeholder`).
 */
import { buildZBracketShapeCommands, type ShapeCommand } from "@flatcraft/cad-engine/geometry";
import { profileIssueToProblem, validateProfile } from "@flatcraft/cad-engine";
import {
  ZBracketParametersSchema,
  Z_BRACKET_DEFAULT_PARAMETERS,
  type ZBracketParameters,
} from "@flatcraft/types";

import type { z } from "zod";

import type { ProfileValidator, TemplateDefinition } from "../definition.js";

/** Профіль-валідатор (флянці >= t+r, offset > r) — паритет з наявним editor/viewport render-gate. */
const profileValidator: ProfileValidator<ZBracketParameters> = (params, thicknessMm) =>
  validateProfile({
    templateSlug: "z_bracket",
    parameters: params,
    thicknessMm,
  }).map(profileIssueToProblem);

/** Placeholder-сумарі для `holes[]` — паритет з `z-bracket-editor.tsx` (Phase 2.7). */
function holesPlaceholderSummary(p: ZBracketParameters): string {
  return `Отвори (${p.holes.length}) — редактор у Phase 2.7.`;
}

function buildShapeCommands(params: ZBracketParameters, thicknessMm: number): ShapeCommand[] {
  return buildZBracketShapeCommands({ parameters: params, thicknessMm });
}

// Hotfix 2.10.e: bends — частина моделі (дефолт [down, up]), генерик-редактор
// їх не показує — паритет з наявним `ZBracketParametersSchema.omit({ bends: true })`.
// `holes` — окремий summary-плейсхолдер замість AutoForm-поля (див. докстрінг).
const HIDDEN_FIELDS = new Set(["bends", "holes"]);
const VISIBLE_FIELDS = Object.keys(ZBracketParametersSchema.shape).filter(
  (field) => !HIDDEN_FIELDS.has(field),
);

export const zBracketDefinition: TemplateDefinition<ZBracketParameters> = {
  slug: "z_bracket",
  process: "sheet_metal",
  labels: { uk: "Z-кронштейн", en: "Z-bracket" },
  // Каст: `bends` має `.default(...)` → Zod input-тип з undefined-полем ≠
  // output-тип (ZBracketParameters, звідки undefined виключено, z.infer бере
  // output-бік) — та сама номінальна невідповідність варіантності, що й у
  // `l-bracket/index.ts`/`corner-angle/index.ts` (не контрактна зміна, сама
  // схема ПАРСИТЬ/ПРОДУКУЄ валідні ZBracketParameters).
  schema: ZBracketParametersSchema as unknown as z.ZodType<ZBracketParameters>,
  defaults: Z_BRACKET_DEFAULT_PARAMETERS,
  ui: {
    scene: { kind: "extrude", build: buildShapeCommands },
    extraControls: [
      { kind: "summary", render: holesPlaceholderSummary, testId: "auto-form-holes-placeholder" },
    ],
    visibleFields: VISIBLE_FIELDS,
    thumbSlug: "z_bracket",
  },
  validators: [profileValidator],
  capabilities: ["bends", "profile", "mount_holes"],
};
