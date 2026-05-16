"use client";

import { OrbitControls } from "@react-three/drei";
import { Canvas } from "@react-three/fiber";
import { useMemo } from "react";
import { ExtrudeGeometry, Shape } from "three";

import type { LBracketParameters } from "@flatcraft/types";

interface SceneProps {
  readonly parameters: LBracketParameters;
  /** Товщина листа, мм. Phase 2.4 додасть UI-вибір; поки фіксовано 2.0. */
  readonly thicknessMm: number;
}

/**
 * Будує 3D-mesh L-кронштейна на основі живих параметрів.
 *
 * Геометрія повторює `workers/cad/templates/l_bracket.py`:
 * 2D L-профіль у площині XY (legB по X, legA по Y, внутрішній радіус
 * у куті — `absarc`). ExtrudeGeometry по Z на width_mm.
 *
 * Це швидкий browser-side preview (target <200мс update,
 * CLAUDE.md §9). Точна CAD-геометрія через OpenCascade.js — Phase 2.6.
 */
function buildLBracketShape(params: LBracketParameters, t: number): Shape {
  const a = params.legA_mm;
  const b = params.legB_mm;
  const r = params.bend_radius_mm;
  const shape = new Shape();

  shape.moveTo(0, 0);
  shape.lineTo(b, 0);
  shape.lineTo(b, t);
  shape.lineTo(t + r, t);
  // absarc(centerX, centerY, radius, startAngle, endAngle, clockwise)
  // Дуга від (t+r, t) до (t, t+r) — внутрішній кут, центр у (t+r, t+r).
  shape.absarc(t + r, t + r, r, -Math.PI / 2, Math.PI, true);
  shape.lineTo(t, a);
  shape.lineTo(0, a);
  shape.closePath();
  return shape;
}

function Bracket({ parameters, thicknessMm }: SceneProps) {
  const geometry = useMemo(() => {
    const shape = buildLBracketShape(parameters, thicknessMm);
    return new ExtrudeGeometry(shape, {
      depth: parameters.width_mm,
      bevelEnabled: false,
    });
  }, [parameters, thicknessMm]);

  // Центруємо: ExtrudeGeometry stretches по +Z; зсуваємо у -Z/2 і
  // переносимо origin до центру bounding box у XY для приємного огляду.
  geometry.computeBoundingBox();
  const bb = geometry.boundingBox;
  const cx = bb ? -((bb.max.x + bb.min.x) / 2) : 0;
  const cy = bb ? -((bb.max.y + bb.min.y) / 2) : 0;
  const cz = bb ? -((bb.max.z + bb.min.z) / 2) : 0;

  return (
    <mesh geometry={geometry} position={[cx, cy, cz]}>
      <meshStandardMaterial color="#94a3b8" metalness={0.5} roughness={0.45} />
    </mesh>
  );
}

export function LBracketSceneInner({ parameters, thicknessMm }: SceneProps) {
  // Camera distance залежить від розміру виробу — щоб великі та малі
  // bracket-и однаково помістились.
  const maxDim = Math.max(parameters.legA_mm, parameters.legB_mm, parameters.width_mm);
  const camDist = maxDim * 1.8;
  return (
    <Canvas
      camera={{ position: [camDist, camDist * 0.8, camDist], fov: 35 }}
      data-testid="l-bracket-canvas"
    >
      <ambientLight intensity={0.55} />
      <directionalLight position={[1, 2, 1.5]} intensity={1.2} />
      <Bracket parameters={parameters} thicknessMm={thicknessMm} />
      <OrbitControls enablePan={false} />
    </Canvas>
  );
}
