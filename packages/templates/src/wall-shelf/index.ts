/**
 * Настінна полиця — TemplateDefinition (ADR-033).
 *
 * Run 7 Master Registry Track, Етап 2 — п'ята міграція (docs/12 §6 PR 6).
 * Джерело поведінки — наявні
 * `apps/web/src/components/wall-shelf-{studio,editor,viewport}.tsx` +
 * `packages/ui/src/3d-viewport/wall-shelf-scene.tsx` (сцена лишається —
 * підключається через `@flatcraft/ui` `COMPOSED_SCENES['wall_shelf']`, той
 * самий підхід, що й corner_angle).
 *
 * `kind: "composed"`, НЕ "extrude" — `WallShelfScene` поверх
 * `buildWallShelfShapeCommands` домальовує mount-hole grid як окремі
 * `CylinderGeometry`-меші (наближене прев'ю, той самий паттерн, що й
 * `corner_angle`; докладніше — коментар у `packages/templates/src/corner-angle/index.ts`).
 *
 * `bends` (масив напрямів 1-2 гибів, дефолт [down, down]) — рендериться лише
 * на кресленні (Hotfix 2.10.e), не в редакторі: паритет з наявним
 * `WallShelfParametersBaseSchema.omit({ bends: true })`. Grid-поля
 * (`mount_hole_*`) — прості number-поля, AutoForm показує їх напряму (той
 * самий підхід, що й `corner_angle`, на відміну від z_bracket/l_bracket, де
 * `holes` — ручний масив).
 *
 * `schema` — повна refined Zod (`WallShelfParametersSchema`, `.refine()` на
 * `front_lip_mm` — 0 АБО ≥5): ЄДИНИЙ шаблон Етапу 2 з ZodEffects, а не plain
 * ZodObject (ADR-033 §2 ALT-C дозволяє). `RegistryTemplateEditor` розгортає
 * ZodEffects до базового ZodObject для AutoForm/`shape`, а повну refined-схему
 * лишає для `safeParse` (інакше cross-field-помилка на `front_lip_mm` губиться).
 */
import { profileIssueToProblem, validateProfile } from "@flatcraft/cad-engine";
import {
  WALL_SHELF_DEFAULT_PARAMETERS,
  WallShelfParametersBaseSchema,
  WallShelfParametersSchema,
  type WallShelfParameters,
} from "@flatcraft/types";

import type { z } from "zod";

import type { ProfileValidator, TemplateDefinition } from "../definition.js";

/** Профіль-валідатор (back_height/shelf_depth >= t+r) — паритет з наявним editor/viewport render-gate. */
const profileValidator: ProfileValidator<WallShelfParameters> = (params, thicknessMm) =>
  validateProfile({
    templateSlug: "wall_shelf",
    parameters: params,
    thicknessMm,
  }).map(profileIssueToProblem);

/** Summary — паритет з наявним `wall-shelf-editor.tsx` (testId `shelf-summary`). */
function shelfSummary(p: WallShelfParameters): string {
  const totalHoles = p.mount_hole_rows * p.mount_hole_cols;
  const lipNote =
    p.front_lip_mm === 0 ? "1 гиб (без front lip)" : `2 гиби (front lip ${p.front_lip_mm} мм)`;
  return `${lipNote} · ${totalHoles} mounting holes Ø${p.mount_hole_diameter_mm} мм на back.`;
}

// Hotfix 2.10.e: bends — частина моделі (дефолт [down, down]), генерик-редактор
// їх не показує — паритет з наявним `WallShelfParametersBaseSchema.omit({ bends: true })`.
const HIDDEN_FIELDS = new Set(["bends"]);
const VISIBLE_FIELDS = Object.keys(WallShelfParametersBaseSchema.shape).filter(
  (field) => !HIDDEN_FIELDS.has(field),
);

export const wallShelfDefinition: TemplateDefinition<WallShelfParameters> = {
  slug: "wall_shelf",
  process: "sheet_metal",
  labels: { uk: "Полиця настінна", en: "Wall shelf" },
  // Каст: `bends` має `.default(...)` → Zod input-тип з undefined-полем ≠
  // output-тип (WallShelfParameters, звідки undefined виключено, z.infer бере
  // output-бік) — та сама номінальна невідповідність варіантності, що й у
  // `z-bracket/index.ts`. `ZodEffects` (refine) теж парсить/продукує валідні
  // `WallShelfParameters` — не контрактна зміна.
  schema: WallShelfParametersSchema as unknown as z.ZodType<WallShelfParameters>,
  defaults: WALL_SHELF_DEFAULT_PARAMETERS,
  ui: {
    scene: { kind: "composed" },
    extraControls: [{ kind: "summary", render: shelfSummary, testId: "shelf-summary" }],
    visibleFields: VISIBLE_FIELDS,
    thumbSlug: "wall_shelf",
  },
  validators: [profileValidator],
  capabilities: ["bends", "profile", "mount_holes"],
};
