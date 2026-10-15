/**
 * L-кронштейн — TemplateDefinition (ADR-033).
 *
 * Run 7 Master Registry Track, Етап 2 — третя міграція (docs/12 §6 PR 5).
 * Джерело поведінки — наявні
 * `apps/web/src/components/l-bracket-{studio,editor,viewport}.tsx`
 * (видалені цим PR) + `packages/ui/src/3d-viewport/l-bracket-scene.tsx`
 * (лишається — окремий консюмер `hero-loop-demo.tsx` на лендінгу, поза
 * Template Registry; див. «Опитування» у PR-description).
 *
 * `kind: "extrude"` — l_bracket першим використовує цей SceneBuilderKind:
 * чистий 2D-контур без декорацій (на відміну від composed corner_angle/
 * perforated_panel). `build` — тонка обгортка над
 * `buildLBracketShapeCommands` (`@flatcraft/cad-engine/geometry`, переїхала
 * туди цим PR з `packages/ui` — react-free вимога `packages/templates`,
 * ADR-033 §1 Рішення 1).
 *
 * `holes` (масив, ручне розміщення) — AutoForm не має редактора для
 * array-полів, приховано з `visibleFields` (`HIDDEN_FIELDS`). Issue #247
 * ч.1: summary-плейсхолдер, що обіцяв майбутній редактор отворів, видалено —
 * редактора отворів немає, а DXF/PDF (#247 ч.2) отвори ще не рендерять,
 * напис обіцяв неіснуючу функціональність. Схема й API не змінені.
 */
import { buildLBracketShapeCommands, type ShapeCommand } from "@flatcraft/cad-engine/geometry";
import { profileIssueToProblem, validateProfile } from "@flatcraft/cad-engine";
import {
  LBracketParametersSchema,
  L_BRACKET_DEFAULT_PARAMETERS,
  type LBracketParameters,
} from "@flatcraft/types";

import type { z } from "zod";

import type { ProfileValidator, TemplateDefinition } from "../definition.js";

/** Профіль-валідатор (leg >= t+r) — паритет з наявним editor/viewport render-gate. */
const profileValidator: ProfileValidator<LBracketParameters> = (params, thicknessMm) =>
  validateProfile({
    templateSlug: "l_bracket",
    parameters: params,
    thicknessMm,
  }).map(profileIssueToProblem);

function buildShapeCommands(params: LBracketParameters, thicknessMm: number): ShapeCommand[] {
  return buildLBracketShapeCommands({ parameters: params, thicknessMm });
}

// Hotfix 2.10.e: bend_direction — частина моделі (дефолт 'down'), генерик-
// редактор його не показує — паритет з наявним `LBracketParametersSchema.omit`.
// `holes` — прихований, редактора немає (issue #247 ч.1, див. докстрінг).
const HIDDEN_FIELDS = new Set(["bend_direction", "holes"]);
const VISIBLE_FIELDS = Object.keys(LBracketParametersSchema.shape).filter(
  (field) => !HIDDEN_FIELDS.has(field),
);

export const lBracketDefinition: TemplateDefinition<LBracketParameters> = {
  slug: "l_bracket",
  process: "sheet_metal",
  labels: { uk: "L-кронштейн", en: "L-bracket" },
  // Каст: `bend_direction` має `.default("down")` → Zod input-тип
  // `"up"|"down"|undefined` ≠ output-тип (LBracketParameters, звідки
  // undefined виключено, z.infer бере output-бік) — та сама номінальна
  // невідповідність варіантності, що й у `corner-angle/index.ts` (не
  // контрактна зміна, сама схема ПАРСИТЬ/ПРОДУКУЄ валідні LBracketParameters).
  schema: LBracketParametersSchema as unknown as z.ZodType<LBracketParameters>,
  defaults: L_BRACKET_DEFAULT_PARAMETERS,
  ui: {
    scene: { kind: "extrude", build: buildShapeCommands },
    visibleFields: VISIBLE_FIELDS,
    thumbSlug: "l_bracket",
  },
  validators: [profileValidator],
  capabilities: ["bends", "profile", "mount_holes"],
};
