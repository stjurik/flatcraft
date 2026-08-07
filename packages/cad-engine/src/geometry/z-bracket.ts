/**
 * Pure 2D-builder для Z-bracket профілю (3 секції, 2 round inner bends).
 *
 * Повторює профіль з `workers/cad/flatcraft_cad/templates/z_bracket.py`
 * (union 3 box-ів; тут — точний контур з round inner bends для preview),
 * у площині XY. ExtrudeGeometry з depth=width_mm дає 3D-mesh.
 *
 * Переїхав з `packages/ui/src/3d-viewport/geometry.ts` (Run 7 Master
 * Registry Track, Етап 2, міграція z_bracket) — `TemplateDefinition.ui.scene`
 * (`kind: 'extrude'`) вимагає `build: (params, thicknessMm) => ShapeCommand[]`
 * прямо у `packages/templates` (react-free, ADR-033 §1 Рішення 1: deps лише
 * `@flatcraft/types` + `@flatcraft/cad-engine`, НЕ `@flatcraft/ui`).
 * `packages/ui/src/3d-viewport/geometry.ts` ре-експортує звідси для наявних
 * споживачів (тестів geometry.test.ts — власного Scene-компонента у z_bracket
 * більше нема, `z-bracket-scene.tsx` видалено цим PR: на відміну від
 * l_bracket, тут немає незалежного консюмера поза Template Registry).
 *
 * Pure-функція (без React/R3F runtime) — типобезпечно юніт-тестується без
 * jsdom або WebGL.
 */
import type { ZBracketParameters } from "@flatcraft/types";

import type { ShapeCommand } from "./shape-command.js";

/**
 * Coord convention (XY, extrude по Z = width_mm):
 *   - Bottom flange: X ∈ [0, bf],     Y ∈ [0, t]
 *   - Middle vertical: X ∈ [bf-t, bf], Y ∈ [0, off+t]
 *   - Top flange:    X ∈ [bf-t, bf-t+tf], Y ∈ [off, off+t]
 *
 * Outer outline CCW з двома round inner bends (radius r):
 *  1. bend "bottom→middle" — concave корнер (bf-t, t)
 *  2. bend "middle→top"    — concave корнер (bf, off)
 *
 * Зовнішні опуклі кути лишаються гострими (як у L-bracket builder) — t малий
 * проти лінійних розмірів, точне округлення зовнішнього кута безкорисне для
 * preview. Точна геометрія для DXF — у CadQuery server-side.
 */
export interface ZBracketGeometryInputs {
  readonly parameters: Omit<ZBracketParameters, "bends">;
  readonly thicknessMm: number;
}

export function buildZBracketShapeCommands(inputs: ZBracketGeometryInputs): ShapeCommand[] {
  const bf = inputs.parameters.bottom_flange_mm;
  const tf = inputs.parameters.top_flange_mm;
  const off = inputs.parameters.offset_mm;
  const r = inputs.parameters.bend_radius_mm;
  const t = inputs.thicknessMm;

  if (t <= 0) throw new Error(`thicknessMm must be > 0, got ${t}`);
  if (off <= r) {
    throw new Error(`offset_mm (${off}) must be > bend_radius_mm (${r}) для round bend 2`);
  }
  if (tf <= t + r) {
    throw new Error(
      `top_flange_mm (${tf}) too small for thickness+radius (${t}+${r}); profile invalid`,
    );
  }
  if (bf <= t + r) {
    throw new Error(
      `bottom_flange_mm (${bf}) too small for thickness+radius (${t}+${r}); profile invalid`,
    );
  }

  return [
    { kind: "moveTo", x: 0, y: 0 },
    // Bottom flange — outer-bottom edge.
    { kind: "lineTo", x: bf, y: 0 },
    // Middle right edge, up to bend 2 approach.
    { kind: "lineTo", x: bf, y: off - r },
    // Bend 2 (middle → top flange): inner concave at (bf, off).
    {
      kind: "absarc",
      cx: bf + r,
      cy: off - r,
      radius: r,
      startAngleRad: Math.PI,
      endAngleRad: Math.PI / 2,
      clockwise: true,
    },
    // Top flange bottom edge (from end of bend 2 до right-bottom of top).
    { kind: "lineTo", x: bf - t + tf, y: off },
    // Top flange right edge.
    { kind: "lineTo", x: bf - t + tf, y: off + t },
    // Top flange top edge.
    { kind: "lineTo", x: bf - t, y: off + t },
    // Middle left edge (going down from top of middle до bend 1 approach).
    { kind: "lineTo", x: bf - t, y: t + r },
    // Bend 1 (middle → bottom flange): inner concave at (bf-t, t).
    {
      kind: "absarc",
      cx: bf - t - r,
      cy: t + r,
      radius: r,
      startAngleRad: 0,
      endAngleRad: -Math.PI / 2,
      clockwise: true,
    },
    // Bottom flange top edge (after bend 1 до lower-left).
    { kind: "lineTo", x: 0, y: t },
    { kind: "closePath" },
  ];
}
