/**
 * `ShapeCommand` — data-контракт для 2D-профілів (moveTo/lineTo/absarc/
 * closePath), який sceneBuilder-и (`kind: 'extrude'`, ADR-033 §1 Рішення 4)
 * перетворюють у THREE.Shape/ExtrudeGeometry.
 *
 * Переїхав з `packages/ui/src/3d-viewport/geometry.ts` (ADR-033 §1, PR 2):
 * це data-контракт для sceneBuilder-ів, не UI-код — `packages/templates`
 * (react-free) посилається на нього для `TemplateDefinition.ui.scene`, тому
 * тип має жити у browser-safe `@flatcraft/cad-engine`, не в `@flatcraft/ui`.
 */
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
