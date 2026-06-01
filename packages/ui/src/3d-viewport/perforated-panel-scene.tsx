"use client";

import type { PerforatedPanelParameters } from "@flatcraft/types";
import { OrbitControls } from "@react-three/drei";
import { Canvas } from "@react-three/fiber";
import { useMemo } from "react";
import { BoxGeometry, CylinderGeometry } from "three";

import { useIsMobile } from "../hooks/use-is-mobile.js";
import { useReducedMotion } from "../hooks/use-reduced-motion.js";
import { viewportQuality } from "../lib/viewport-quality.js";

interface SceneProps {
  readonly parameters: PerforatedPanelParameters;
  readonly thicknessMm: number;
}

const MAX_HOLES_PREVIEW = 500;

/**
 * Perforated panel 3D — плоский box + cylinder-отвори за обчисленим grid.
 *
 * Layout повторює `unfold_perforated_panel`: центрований grid з pitch'ом.
 * Cylinders побудовано як orange overlay (без CSG difference — швидше).
 * Якщо обчислений grid перевищує MAX_HOLES_PREVIEW, отвори не рендеряться
 * (UI показує summary). Для laser-cutter точна геометрія у DXF.
 */
function PerforatedPanel({ parameters, thicknessMm }: SceneProps) {
  const { boxGeom, holes } = useMemo(() => {
    const t = thicknessMm;
    const L = parameters.length_mm;
    const W = parameters.width_mm;
    const px = parameters.pitch_x_mm;
    const py = parameters.pitch_y_mm;
    const m = parameters.margin_mm;

    const boxGeom = new BoxGeometry(L, t, W);

    // Centered grid (idempotent з Python unfold_perforated_panel).
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
        const x = effMarginX + i * px - L / 2; // re-center around origin
        for (let j = 0; j < nRows; j++) {
          const z = effMarginY + j * py - W / 2;
          holes.push({ pos: [x, t / 2, z] as const });
        }
      }
    }
    return { boxGeom, holes };
  }, [parameters, thicknessMm]);

  const cylRadius = parameters.hole_diameter_mm / 2;
  const cylLen = thicknessMm * 1.5;
  const cylGeom = useMemo(
    () => new CylinderGeometry(cylRadius, cylRadius, cylLen, 16),
    [cylRadius, cylLen],
  );

  return (
    <group>
      <mesh geometry={boxGeom}>
        <meshStandardMaterial color="#94a3b8" metalness={0.5} roughness={0.45} />
      </mesh>
      {holes.map((h, i) => (
        <mesh key={i} geometry={cylGeom} position={h.pos}>
          <meshStandardMaterial color="#fb923c" />
        </mesh>
      ))}
    </group>
  );
}

export function PerforatedPanelScene({ parameters, thicknessMm }: SceneProps) {
  const isMobile = useIsMobile();
  const reduced = useReducedMotion();
  const quality = useMemo(() => viewportQuality({ isMobile, reduced }), [isMobile, reduced]);

  const maxDim = Math.max(parameters.length_mm, parameters.width_mm);
  const camDist = maxDim * 1.5;
  return (
    <Canvas
      dpr={[...quality.dpr]}
      camera={{ position: [camDist, camDist * 0.6, camDist], fov: 35 }}
      data-testid="perforated-panel-canvas"
    >
      <ambientLight intensity={0.55} />
      <directionalLight position={[1, 2, 1.5]} intensity={1.2} />
      <PerforatedPanel parameters={parameters} thicknessMm={thicknessMm} />
      <OrbitControls
        enablePan={false}
        enableZoom={quality.enableZoom}
        enableRotate={quality.enableRotate}
      />
    </Canvas>
  );
}
