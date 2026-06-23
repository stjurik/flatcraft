"use client";

import type { PerforatedPanelSquareParameters } from "@flatcraft/types";
import { OrbitControls } from "@react-three/drei";
import { Canvas } from "@react-three/fiber";
import { useMemo } from "react";
import { BoxGeometry } from "three";

import { useIsMobile } from "../hooks/use-is-mobile.js";
import { useReducedMotion } from "../hooks/use-reduced-motion.js";
import { viewportQuality } from "../lib/viewport-quality.js";

interface SceneProps {
  readonly parameters: PerforatedPanelSquareParameters;
  readonly thicknessMm: number;
}

const MAX_HOLES_PREVIEW = 500;

/**
 * Perforated panel SQUARE 3D — плоский box + box-отвори за обчисленим grid
 * (Phase 3.0 PR 5, ADR-027 Рішення 6).
 *
 * Аналог PerforatedPanelScene, але hole overlay — BoxGeometry замість
 * CylinderGeometry, бо квадратні отвори.
 */
function PerforatedPanelSquare({ parameters, thicknessMm }: SceneProps) {
  const { boxGeom, holes } = useMemo(() => {
    const t = thicknessMm;
    const L = parameters.length_mm;
    const W = parameters.width_mm;
    const px = parameters.pitch_x_mm;
    const py = parameters.pitch_y_mm;
    const m = parameters.margin_mm;

    const boxGeom = new BoxGeometry(L, t, W);

    const availX = L - 2 * m;
    const availY = W - 2 * m;
    const nCols = Math.max(1, Math.floor(availX / px) + 1);
    const nRows = Math.max(1, Math.floor(availY / py) + 1);
    const effMarginX = (L - (nCols - 1) * px) / 2;
    const effMarginY = (W - (nRows - 1) * py) / 2;

    const total = nCols * nRows;
    const holes: Array<{ pos: readonly [number, number, number] }> = [];
    if (total <= MAX_HOLES_PREVIEW) {
      for (let i = 0; i < nCols; i++) {
        const x = effMarginX + i * px - L / 2;
        for (let j = 0; j < nRows; j++) {
          const z = effMarginY + j * py - W / 2;
          holes.push({ pos: [x, t / 2, z] as const });
        }
      }
    }
    return { boxGeom, holes };
  }, [parameters, thicknessMm]);

  // Box overlay для square hole — той самий розмір по X/Z (side length), Y
  // трохи довший за товщину для візуальної проколу.
  const side = parameters.hole_size_mm;
  const holeLen = thicknessMm * 1.5;
  const holeGeom = useMemo(() => new BoxGeometry(side, holeLen, side), [side, holeLen]);

  return (
    <group>
      <mesh geometry={boxGeom}>
        <meshStandardMaterial color="#94a3b8" metalness={0.5} roughness={0.45} />
      </mesh>
      {holes.map((h, i) => (
        <mesh key={i} geometry={holeGeom} position={h.pos}>
          <meshStandardMaterial color="#fb923c" />
        </mesh>
      ))}
    </group>
  );
}

export function PerforatedPanelSquareScene({ parameters, thicknessMm }: SceneProps) {
  const isMobile = useIsMobile();
  const reduced = useReducedMotion();
  const quality = useMemo(() => viewportQuality({ isMobile, reduced }), [isMobile, reduced]);

  const maxDim = Math.max(parameters.length_mm, parameters.width_mm);
  const camDist = maxDim * 1.5;
  return (
    <Canvas
      dpr={[...quality.dpr]}
      camera={{ position: [camDist, camDist * 0.6, camDist], fov: 35 }}
      data-testid="perforated-panel-square-canvas"
    >
      <ambientLight intensity={0.55} />
      <directionalLight position={[1, 2, 1.5]} intensity={1.2} />
      <PerforatedPanelSquare parameters={parameters} thicknessMm={thicknessMm} />
      <OrbitControls
        enablePan={false}
        enableZoom={quality.enableZoom}
        enableRotate={quality.enableRotate}
      />
    </Canvas>
  );
}
