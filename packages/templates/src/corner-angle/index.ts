/**
 * Кутник — TemplateDefinition (ADR-033).
 *
 * Run 7 Master Registry Track, Етап 2 — друга міграція (docs/12 §6). Джерело
 * поведінки — наявні `apps/web/src/components/corner-angle-{studio,editor,viewport}.tsx`
 * (видалені цим PR) + `packages/ui/src/3d-viewport/corner-angle-scene.tsx`
 * (лишається — підключається через `@flatcraft/ui` `COMPOSED_SCENES['corner_angle']`).
 *
 * `kind: "composed"`, НЕ "extrude" (хоч профіль — L-shape, теоретично 2D
 * `ShapeCommand[]`): `CornerAngleScene` поверх `buildLBracketShapeCommands`
 * ще домальовує auto-grid отворів як окремі `CylinderGeometry`-меші
 * (наближене прев'ю, точні координати — лише у DXF/PDF) — `SceneBuilderKind.extrude`
 * несе ЛИШЕ `build: (params, t) => ShapeCommand[]` (чистий 2D-контур, без
 * концепції отворів/декорацій, ADR-033 §1 Рішення 4). Розширювати цей
 * контракт заради 2 шаблонів (corner_angle, wall_shelf — та сама
 * hole-cylinder композиція) — зміна docs/12-контракту (STOP-тригер).
 * `composed` вже підтримує довільну композицію без змін контракту, тому
 * дешевший шлях — класифікувати обидва як `composed` (мій дефолт;
 * альтернатива — розширити extrude полем `holes?`, див. PR "Опитування").
 * Справжня "extrude" генерик-сцена (чистий контур без декорацій)
 * реалізується разом з l_bracket — першим шаблоном без жодних декорацій.
 */
import { profileIssueToProblem, validateProfile } from "@flatcraft/cad-engine";
import {
  CORNER_ANGLE_DEFAULT_PARAMETERS,
  CornerAngleParametersSchema,
  type CornerAngleParameters,
} from "@flatcraft/types";
import type { z } from "zod";

import type { ProfileValidator, TemplateDefinition } from "../definition.js";

/** Профіль-валідатор (leg >= t+r) — паритет з наявним editor/viewport render-gate. */
const profileValidator: ProfileValidator<CornerAngleParameters> = (params, thicknessMm) =>
  validateProfile({
    templateSlug: "corner_angle",
    parameters: params,
    thicknessMm,
  }).map(profileIssueToProblem);

/** Grid-сумарі — паритет з наявним `corner-angle-editor.tsx` (testid `hole-grid-summary`). */
function holeGridSummary(p: CornerAngleParameters): string {
  const total = 2 * p.hole_rows * p.hole_cols;
  return `Grid: ${p.hole_rows}×${p.hole_cols} на полицю · всього ${total} отворів Ø${p.hole_diameter_mm} мм.`;
}

// Hotfix 2.10.e: bend_direction — частина моделі (дефолт 'down', рендериться
// лише на кресленні), але generic-редактор його не показує — паритет з
// наявним `CornerAngleParametersSchema.omit({ bend_direction: true })`.
const VISIBLE_FIELDS = Object.keys(CornerAngleParametersSchema.shape).filter(
  (field) => field !== "bend_direction",
);

export const cornerAngleDefinition: TemplateDefinition<CornerAngleParameters> = {
  slug: "corner_angle",
  process: "sheet_metal",
  labels: { uk: "Кутник", en: "Corner angle" },
  // Каст: `bend_direction` має `.default("down")` → Zod input-тип
  // `"up"|"down"|undefined` ≠ output-тип (CornerAngleParameters, звідки
  // undefined виключено, z.infer бере output-бік). `schema: z.ZodType<Params>`
  // (1 type-param) вимагає input=output=Params — сама схема коректно
  // ПАРСИТЬ/ПРОДУКУЄ валідні CornerAngleParameters, це суто номінальна
  // невідповідність варіантності, не контрактна зміна.
  schema: CornerAngleParametersSchema as unknown as z.ZodType<CornerAngleParameters>,
  defaults: CORNER_ANGLE_DEFAULT_PARAMETERS,
  ui: {
    scene: { kind: "composed" },
    extraControls: [{ kind: "summary", render: holeGridSummary, testId: "hole-grid-summary" }],
    visibleFields: VISIBLE_FIELDS,
    thumbSlug: "corner_angle",
  },
  validators: [profileValidator],
  capabilities: ["bends", "profile", "mount_holes"],
};
