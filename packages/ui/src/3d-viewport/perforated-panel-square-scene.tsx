"use client";

import type { PerforatedPanelSquareParameters } from "@flatcraft/types";
import { OrbitControls } from "@react-three/drei";
import { Canvas } from "@react-three/fiber";
import { useMemo } from "react";
import { BoxGeometry } from "three";

import { useIsMobile } from "../hooks/use-is-mobile.js";
import { useReducedMotion } from "../hooks/use-reduced-motion.js";
import { viewportQuality } from "../lib/viewport-quality.js";
import { computeCameraPlacement } from "./camera-placement.js";
import { computeHoleGrid } from "./hole-grid.js";
import { InstancedHoles } from "./instanced-holes.js";

interface SceneProps {
  readonly parameters: PerforatedPanelSquareParameters;
  readonly thicknessMm: number;
}

/**
 * Perforated panel SQUARE 3D — плоский box + box-отвори за обчисленим grid
 * (Phase 3.0 PR 5, ADR-027 Рішення 6).
 *
 * Аналог PerforatedPanelScene, але hole overlay — BoxGeometry замість
 * CylinderGeometry, бо квадратні отвори. Отвори рендеряться через InstancedHoles
 * (1 draw call); великі grid'и граційно проріджуються (`computeHoleGrid`), а не
 * гасяться повністю.
 */
function PerforatedPanelSquare({ parameters, thicknessMm }: SceneProps) {
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

  // Box overlay для square hole — той самий розмір по X/Z (side length), Y
  // трохи довший за товщину для візуальної проколу.
  const side = parameters.hole_size_mm;
  const holeLen = t * 1.5;
  const holeGeom = useMemo(() => new BoxGeometry(side, holeLen, side), [side, holeLen]);

  return (
    <group>
      <mesh geometry={boxGeom}>
        <meshStandardMaterial color="#94a3b8" metalness={0.5} roughness={0.45} />
      </mesh>
      <InstancedHoles geometry={holeGeom} positions={positions} />
    </group>
  );
}

export function PerforatedPanelSquareScene({ parameters, thicknessMm }: SceneProps) {
  const isMobile = useIsMobile();
  const reduced = useReducedMotion();
  const quality = useMemo(() => viewportQuality({ isMobile, reduced }), [isMobile, reduced]);

  // PR 8a: bbox-aware камера (perforated_panel_square: плоский лист L × t × W).
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
