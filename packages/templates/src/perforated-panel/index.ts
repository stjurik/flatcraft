/**
 * Перфо-монтажна панель — TemplateDefinition (ADR-031, ADR-033).
 *
 * Run 7 Master Registry Track, Етап 2 — перша міграція (docs/12 §6: найпростіший
 * shape-wise шаблон з 6, вже після ADR-031-уніфікації форми отвору). Джерело
 * поведінки — наявні `apps/web/src/components/perforated-panel-{studio,editor,viewport}.tsx`
 * (видалені цим PR) + `packages/ui/src/3d-viewport/perforated-panel-scene.tsx`
 * (лишається — composed-сцена тепер підключається через
 * `@flatcraft/ui` `COMPOSED_SCENES['perforated_panel']`, docs/12 §1 STOP-знахідка).
 *
 * `kind: "composed"` — ребриста box-композиція, не 2D-профіль (не мапиться
 * на `ShapeCommand[]`).
 */
import {
  perforationIssueToProblem,
  profileIssueToProblem,
  validatePerforation,
  validateProfile,
} from "@flatcraft/cad-engine";
import {
  HOLE_SHAPES,
  PERFORATED_PANEL_DEFAULT_PARAMETERS,
  PerforatedPanelParametersSchema,
  type PerforatedPanelParameters,
} from "@flatcraft/types";

import type { ProfileValidator, TemplateDefinition } from "../definition.js";

const HOLE_SHAPE_LABELS: Record<(typeof HOLE_SHAPES)[number], string> = {
  circle: "Круглі",
  square: "Квадратні",
};

/**
 * Профіль-валідатор (rib_height > t+r) — паритет з наявним
 * `perforated-panel-viewport`/`TemplateStudio` render-gate шляхом
 * (Hotfix 2.9.f, ADR-026). НОВЕ порівняно з наявним editor-банером
 * (`perforated-panel-editor.tsx` НЕ показував profile-issues у своєму
 * банері, лише блокував export-кнопку через `TemplateStudio`) — generic
 * editor показує ВСІ `def.validators`-issues уніфіковано (Run 7 Етап 2,
 * задокументоване покращення, не regressed поведінка: жоден e2e не
 * перевіряв відсутність цього повідомлення).
 */
const profileValidator: ProfileValidator<PerforatedPanelParameters> = (params, thicknessMm) =>
  validateProfile({
    templateSlug: "perforated_panel",
    parameters: params,
    thicknessMm,
  }).map(profileIssueToProblem);

/** Grid-перетин отворів (pitch <= hole_size) — паритет з наявним editor-банером. */
const perforationValidator: ProfileValidator<PerforatedPanelParameters> = (params) =>
  validatePerforation({
    templateSlug: "perforated_panel",
    parameters: params,
  }).map(perforationIssueToProblem);

/** Centered grid — мусить збігатися з Python `unfold_perforated_panel` (паритет з наявним editor). */
function gridSummary(p: PerforatedPanelParameters): string {
  const availX = p.length_mm - 2 * p.margin_mm;
  const availY = p.width_mm - 2 * p.margin_mm;
  const { cols, rows } =
    availX < 0 || availY < 0
      ? { cols: 0, rows: 0 }
      : {
          cols: Math.max(1, Math.floor(availX / p.pitch_x_mm) + 1),
          rows: Math.max(1, Math.floor(availY / p.pitch_y_mm) + 1),
        };
  const total = cols * rows;
  const glyph = p.hole_shape === "square" ? "□" : "Ø";
  return (
    `Grid: ${cols}×${rows} = ${total} отворів ${glyph}${p.hole_size_mm} мм ` +
    `(centered, pitch_x=${p.pitch_x_mm} pitch_y=${p.pitch_y_mm}).`
  );
}

export const perforatedPanelDefinition: TemplateDefinition<PerforatedPanelParameters> = {
  slug: "perforated_panel",
  process: "sheet_metal",
  labels: { uk: "Перфо-монтажна панель", en: "Perforated mounting panel" },
  schema: PerforatedPanelParametersSchema,
  defaults: PERFORATED_PANEL_DEFAULT_PARAMETERS,
  ui: {
    scene: { kind: "composed" },
    extraControls: [
      {
        kind: "segmented",
        field: "hole_shape",
        options: HOLE_SHAPES.map((value) => ({ value, label: HOLE_SHAPE_LABELS[value] })),
        label: "Тип отвору",
        testId: "hole-shape-toggle",
      },
      { kind: "summary", render: gridSummary, testId: "grid-summary" },
    ],
    thumbSlug: "perforated_panel",
  },
  validators: [profileValidator, perforationValidator],
  products: [
    {
      // Дзеркало packages/db/src/seed-products.ts "perforated-panel-decorative"
      // (Phase 3.0 PR 6, ADR-027 Рішення 6) — DB лишається джерелом істини для
      // isPublished/previewImageUrl/useCases; тут — лише parameter-shape, який
      // потребує generic-студія (fixed + userEditableFields).
      slug: "perforated-panel-decorative",
      name: "Декоративна перфо-панель",
      description:
        "Стильна декоративна панель з квадратними отворами для інтер'єру, офісу та дому. Налаштуйте розмір, крок отворів, висоту ребра і матеріал — отримайте готові креслення для лазерного різання.",
      fixed: {},
      userEditableFields: [
        "length_mm",
        "width_mm",
        "hole_size_mm",
        "pitch_x_mm",
        "pitch_y_mm",
        "margin_mm",
        "rib_height_mm",
      ],
    },
  ],
  capabilities: ["bends", "profile", "perforation"],
};
