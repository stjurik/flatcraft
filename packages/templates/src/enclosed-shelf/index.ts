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
 * `validators: []` — на відміну від l_bracket/z_bracket/wall_shelf/
 * corner_angle/perforated_panel, `validateProfile` НЕ підтримує
 * `templateSlug: "enclosed_shelf"` (нема запису у `ProfileValidationInput`
 * union, `packages/cad-engine/src/validators/profile.ts`). Це не прогалина
 * цієї міграції — те саме задокументоване рішення вже лежить у
 * `export-gate.ts` (`case "enclosed_shelf": return []` — "profile-валідатор
 * для cross-розгортки поки не моделюється, Zod-min ranges відсіюють
 * невалідне ще на API") і в `template-studio.tsx` (`SLUGS_WITH_PROFILE` не
 * містить `enclosed_shelf`). CLAUDE.md §7 забороняє чіпати render-gate
 * `validateProfile` цією задачею — тож `[]` тут, а не новий case.
 */
import { ENCLOSED_SHELF_DEFAULT_PARAMETERS, EnclosedShelfParametersSchema } from "@flatcraft/types";
import type { EnclosedShelfParameters } from "@flatcraft/types";
import type { z } from "zod";

import type { TemplateDefinition } from "../definition.js";

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
  validators: [],
  capabilities: ["bends"],
};
