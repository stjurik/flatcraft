/**
 * Lookup для `kind: 'composed'` сцен (ADR-033 §1 Рішення 4 + STOP-знахідка
 * docs/12_TEMPLATE_CONTRACT.md §1, Run 7 Етап 2, PR `perforated_panel`,
 * рішення yurii 2026-07-21).
 *
 * Реальний React-компонент для `composed`-шаблонів (perforated_panel,
 * enclosed_shelf) живе ТУТ (`packages/ui` вже має `react`/three.js), а не у
 * react-free `packages/templates`. Generic-viewport (`apps/web`) дивиться
 * `def.ui.scene.kind === "composed"` і шукає компонент тут за slug.
 * Populated по одному запису на PR міграції (Run 7 Етап 2).
 */
import type { ComponentType } from "react";

import { CornerAngleScene } from "./corner-angle-scene.js";
import { PerforatedPanelScene } from "./perforated-panel-scene.js";

export interface ComposedSceneProps {
  readonly parameters: unknown;
  readonly thicknessMm: number;
}

export type ComposedSceneComponent = ComponentType<ComposedSceneProps>;

export const COMPOSED_SCENES: Partial<Record<string, ComposedSceneComponent>> = {
  // Каст безпечний: реєстр (`packages/templates`) типізує `parameters` для
  // slug'а `perforated_panel` саме як `PerforatedPanelParameters` — це той
  // самий тип, під який `PerforatedPanelScene` уже написана; generic-viewport
  // передає параметри лише того slug'а, під який їх узяв з реєстру.
  perforated_panel: PerforatedPanelScene as ComposedSceneComponent,
  // corner_angle — L-shape extrude + auto-grid hole cylinders overlay
  // (наближене прев'ю); "composed", не "extrude" — docs/12 §1, коментар у
  // `packages/templates/src/corner-angle/index.ts`.
  corner_angle: CornerAngleScene as ComposedSceneComponent,
};
