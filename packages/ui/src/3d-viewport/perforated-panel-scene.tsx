"use client";

import type { PerforatedPanelParameters } from "@flatcraft/types";
import { OrbitControls } from "@react-three/drei";
import { Canvas } from "@react-three/fiber";
import { useMemo } from "react";
import { BoxGeometry, CylinderGeometry } from "three";

import { useIsMobile } from "../hooks/use-is-mobile.js";
import { useReducedMotion } from "../hooks/use-reduced-motion.js";
import { viewportQuality } from "../lib/viewport-quality.js";
import { computeCameraPlacement } from "./camera-placement.js";
import { computeHoleGrid } from "./hole-grid.js";
import { InstancedHoles } from "./instanced-holes.js";

interface SceneProps {
  readonly parameters: PerforatedPanelParameters;
  readonly thicknessMm: number;
}

/**
 * Perforated panel 3D — плоский box + cylinder-отвори за обчисленим grid.
 *
 * Layout повторює `unfold_perforated_panel`: центрований grid з pitch'ом.
 * Cylinders — orange overlay через InstancedHoles (1 draw call, без CSG).
 * Великі grid'и граційно проріджуються (`computeHoleGrid`), а не гасяться —
 * раніше `total > cap` робив усю панель суцільною. Точна геометрія — у DXF.
 */
function PerforatedPanel({ parameters, thicknessMm }: SceneProps) {
  const t = thicknessMm;
  const boxGeom = useMemo(
    () => new BoxGeometry(parameters.length_mm, t, parameters.width_mm),
    [parameters.length_mm, parameters.width_mm, t],
  );

  const positions = useMemo(() => {
    const { cells } = computeHoleGrid({
      lengthMm: parameters.length_mm,
      widthMm: parameters.width_mm,
      pitchXMm: parameters.pitch_x_mm,
      pitchYMm: parameters.pitch_y_mm,
      marginMm: parameters.margin_mm,
    });
    return cells.map((c) => [c.u, t / 2, c.v] as const);
  }, [
    parameters.length_mm,
    parameters.width_mm,
    parameters.pitch_x_mm,
    parameters.pitch_y_mm,
    parameters.margin_mm,
    t,
  ]);

  const cylRadius = parameters.hole_diameter_mm / 2;
  const cylLen = t * 1.5;
  const cylGeom = useMemo(
    () => new CylinderGeometry(cylRadius, cylRadius, cylLen, 16),
    [cylRadius, cylLen],
  );

  return (
    <group>
      <mesh geometry={boxGeom}>
        <meshStandardMaterial color="#94a3b8" metalness={0.5} roughness={0.45} />
      </mesh>
      <InstancedHoles geometry={cylGeom} positions={positions} />
    </group>
  );
}

export function PerforatedPanelScene({ parameters, thicknessMm }: SceneProps) {
  const isMobile = useIsMobile();
  const reduced = useReducedMotion();
  const quality = useMemo(() => viewportQuality({ isMobile, reduced }), [isMobile, reduced]);

  // PR 8a: bbox-aware камера (perforated_panel: плоский лист L × t × W).
  const placement = useMemo(
    () =>
      computeCameraPlacement({
        x: parameters.length_mm,
        y: thicknessMm,
        z: parameters.width_mm,
      }),
    [parameters.length_mm, parameters.width_mm, thicknessMm],
  );
  return (
    <Canvas
      dpr={[...quality.dpr]}
      camera={{
        position: [...placement.position],
        fov: placement.fov,
        near: placement.near,
        far: placement.far,
      }}
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
