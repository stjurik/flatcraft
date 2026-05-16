/**
 * Pure 2D-builder для L-bracket профілю.
 *
 * Повторює профіль з `workers/cad/templates/l_bracket.py`:
 * 6 ліній + дуга у внутрішньому куті радіусом R, у площині XY.
 * ExtrudeGeometry з depth=width_mm дає 3D-mesh.
 *
 * Pure-функція (без React/R3F runtime) — типобезпечно юніт-тестується
 * без jsdom або WebGL. Споживачі (Scene component) обгортають у
 * THREE.ExtrudeGeometry; будь-яка інша 3D-tooling може використати ту
 * саму послідовність команд.
 */
import type { LBracketParameters } from "@flatcraft/types";

export type ShapeCommand =
  | { readonly kind: "moveTo"; readonly x: number; readonly y: number }
  | { readonly kind: "lineTo"; readonly x: number; readonly y: number }
  | {
      readonly kind: "absarc";
      readonly cx: number;
      readonly cy: number;
      readonly radius: number;
      readonly startAngleRad: number;
      readonly endAngleRad: number;
      readonly clockwise: boolean;
    }
  | { readonly kind: "closePath" };

export interface LBracketGeometryInputs {
  readonly parameters: LBracketParameters;
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
