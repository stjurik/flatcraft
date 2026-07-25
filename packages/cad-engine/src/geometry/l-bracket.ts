/**
 * Pure 2D-builder для L-bracket профілю.
 *
 * Повторює профіль з `workers/cad/templates/l_bracket.py`:
 * 6 ліній + дуга у внутрішньому куті радіусом R, у площині XY.
 * ExtrudeGeometry з depth=width_mm дає 3D-mesh.
 *
 * Переїхав з `packages/ui/src/3d-viewport/geometry.ts` (Run 7 Master
 * Registry Track, Етап 2, міграція l_bracket) — `TemplateDefinition.ui.scene`
 * (`kind: 'extrude'`) вимагає `build: (params, thicknessMm) => ShapeCommand[]`
 * прямо у `packages/templates` (react-free, ADR-033 §1 Рішення 1: deps лише
 * `@flatcraft/types` + `@flatcraft/cad-engine`, НЕ `@flatcraft/ui`).
 * `packages/ui/src/3d-viewport/geometry.ts` ре-експортує звідси для наявних
 * споживачів (`LBracketScene`, `CornerAngleScene`).
 *
 * Pure-функція (без React/R3F runtime) — типобезпечно юніт-тестується без
 * jsdom або WebGL.
 */
import type { LBracketParameters } from "@flatcraft/types";

import type { ShapeCommand } from "./shape-command.js";

export interface LBracketGeometryInputs {
  // Геометрія не залежить від bend_direction (рендериться лише на креслі) —
  // Omit дозволяє синтетичним preview-об'єктам не нести напрям (Hotfix 2.10.e).
  readonly parameters: Omit<LBracketParameters, "bend_direction">;
  readonly thicknessMm: number;
}

export function buildLBracketShapeCommands(inputs: LBracketGeometryInputs): ShapeCommand[] {
  const a = inputs.parameters.legA_mm;
  const b = inputs.parameters.legB_mm;
  const r = inputs.parameters.bend_radius_mm;
  const t = inputs.thicknessMm;

  if (t <= 0) throw new Error(`thicknessMm must be > 0, got ${t}`);
  if (t + r > a) {
    throw new Error(
      `legA_mm (${a}) too small for thickness+radius (${t}+${r}); profile would be invalid`,
    );
  }
  if (t + r > b) {
    throw new Error(
      `legB_mm (${b}) too small for thickness+radius (${t}+${r}); profile would be invalid`,
    );
  }

  // Конвенція координат: X по полиці B, Y по полиці A.
  // Внутрішній кут (0..t, 0..t) — заповнений; arc з'єднує (t+r, t) ↔ (t, t+r).
  return [
    { kind: "moveTo", x: 0, y: 0 },
    { kind: "lineTo", x: b, y: 0 },
    { kind: "lineTo", x: b, y: t },
    { kind: "lineTo", x: t + r, y: t },
    {
      kind: "absarc",
      cx: t + r,
      cy: t + r,
      radius: r,
      startAngleRad: -Math.PI / 2,
      endAngleRad: Math.PI,
      clockwise: true,
    },
    { kind: "lineTo", x: t, y: a },
    { kind: "lineTo", x: 0, y: a },
    { kind: "closePath" },
  ];
}
