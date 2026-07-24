/**
 * Pure 2D-builders для extrude-профілів (L/Z-bracket, wall-shelf).
 *
 * Повторюють профілі з `workers/cad/templates/*.py` у площині XY;
 * ExtrudeGeometry з depth=width_mm дає 3D-mesh.
 *
 * Pure-функції (без React/R3F runtime) — типобезпечно юніт-тестуються
 * без jsdom або WebGL. Споживачі (Scene component) обгортають у
 * THREE.ExtrudeGeometry; будь-яка інша 3D-tooling може використати ту
 * саму послідовність команд.
 */
import type { ShapeCommand } from "@flatcraft/cad-engine/geometry";
import type { WallShelfParameters, ZBracketParameters } from "@flatcraft/types";

// Реекспорт для наявних споживачів (`./geometry.js` → `3d-viewport/index.ts` →
// `@flatcraft/ui`) — тип тепер живе у `@flatcraft/cad-engine` (ADR-033 §1,
// PR 2): це data-контракт для sceneBuilder-ів, не UI-код.
export type { ShapeCommand };

// buildLBracketShapeCommands/LBracketGeometryInputs переїхали у
// `@flatcraft/cad-engine/geometry` (Run 7 Етап 2, міграція l_bracket) —
// `TemplateDefinition.ui.scene.build` (`packages/templates`, react-free)
// потребує прямого доступу без залежності на `@flatcraft/ui`. Реекспорт тут
// — щоб наявні споживачі (`LBracketScene`, `CornerAngleScene`, тести) не
// міняли import-шлях.
export {
  buildLBracketShapeCommands,
  type LBracketGeometryInputs,
} from "@flatcraft/cad-engine/geometry";

/**
 * Z-bracket cross-section (Phase 2.14.b) — 3 секції з 2 round inner bends.
 *
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

/**
 * Wall-shelf cross-section (Phase 2.14.b) — back + shelf + (optional) front_lip.
 *
 * Coord convention (XY, extrude по Z = width_mm):
 *   - Back:  X ∈ [0, t],   Y ∈ [0, back_height]
 *   - Shelf: X ∈ [0, sd],  Y ∈ [0, t]
 *   - Lip (if >0): X ∈ [sd-t, sd], Y ∈ [0, front_lip]
 *
 * Bends:
 *   - back→shelf: inner concave у (t, t) — завжди є.
 *   - shelf→lip:  inner concave у (sd-t, t) — лише якщо front_lip > 0.
 *
 * При front_lip=0 виходить L-shape (back + shelf без переднього губу).
 */
export interface WallShelfGeometryInputs {
  readonly parameters: Omit<WallShelfParameters, "bends">;
  readonly thicknessMm: number;
}

export function buildWallShelfShapeCommands(inputs: WallShelfGeometryInputs): ShapeCommand[] {
  const bh = inputs.parameters.back_height_mm;
  const sd = inputs.parameters.shelf_depth_mm;
  const lip = inputs.parameters.front_lip_mm;
  const r = inputs.parameters.bend_radius_mm;
  const t = inputs.thicknessMm;

  if (t <= 0) throw new Error(`thicknessMm must be > 0, got ${t}`);
  if (bh <= t + r) {
    throw new Error(
      `back_height_mm (${bh}) too small for thickness+radius (${t}+${r}); profile invalid`,
    );
  }
  // Для front_lip > 0 потрібно щоб shelf вистачило на 2 bends.
  if (lip > 0 && sd <= 2 * (t + r)) {
    throw new Error(
      `shelf_depth_mm (${sd}) too small for two round bends (need > 2·(t+r) = ${2 * (t + r)})`,
    );
  }
  if (lip === 0 && sd <= t + r) {
    throw new Error(`shelf_depth_mm (${sd}) too small for one round bend (need > t+r = ${t + r})`);
  }

  const cmds: ShapeCommand[] = [{ kind: "moveTo", x: 0, y: 0 }];

  if (lip > 0) {
    // bottom of shelf
    cmds.push({ kind: "lineTo", x: sd, y: 0 });
    // right edge of lip
    cmds.push({ kind: "lineTo", x: sd, y: lip });
    // top of lip
    cmds.push({ kind: "lineTo", x: sd - t, y: lip });
    // left edge of lip down до bend "shelf→lip" approach
    cmds.push({ kind: "lineTo", x: sd - t, y: t + r });
    // bend shelf→lip: inner concave at (sd-t, t)
    cmds.push({
      kind: "absarc",
      cx: sd - t - r,
      cy: t + r,
      radius: r,
      startAngleRad: 0,
      endAngleRad: -Math.PI / 2,
      clockwise: true,
    });
    // shelf top edge: from end of bend (sd-t-r, t) до bend "back→shelf" approach (t+r, t)
    cmds.push({ kind: "lineTo", x: t + r, y: t });
  } else {
    // front_lip=0: shelf bottom → shelf right edge → shelf top → bend approach
    cmds.push({ kind: "lineTo", x: sd, y: 0 });
    cmds.push({ kind: "lineTo", x: sd, y: t });
    cmds.push({ kind: "lineTo", x: t + r, y: t });
  }

  // bend back→shelf: inner concave at (t, t) — однаковий незалежно від lip
  cmds.push({
    kind: "absarc",
    cx: t + r,
    cy: t + r,
    radius: r,
    startAngleRad: -Math.PI / 2,
    endAngleRad: Math.PI,
    clockwise: true,
  });
  // back right edge from end of bend (t, t+r) до back's top
  cmds.push({ kind: "lineTo", x: t, y: bh });
  // back top edge
  cmds.push({ kind: "lineTo", x: 0, y: bh });
  cmds.push({ kind: "closePath" });

  return cmds;
}
