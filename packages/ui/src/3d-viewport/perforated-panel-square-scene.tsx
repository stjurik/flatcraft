"use client";

import type { PerforatedPanelSquareParameters } from "@flatcraft/types";
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
  readonly parameters: PerforatedPanelSquareParameters;
  readonly thicknessMm: number;
}

// ADR-030 worker-константи, віддзеркалені для прев'ю (не у Zod-параметрах).
const CORNER_HOLE_DIAMETER_MM = 5.5;
const CORNER_HOLE_INSET_MM = 12;

/**
 * Перфо-монтажна панель 3D — ГНУТИЙ ЛОТОК (ADR-030): перфо-площина + 4 ребра
 * (фланці вгору) + 4 кутові установочні отвори. Квадратні перфо-отвори —
 * InstancedHoles (1 draw call); ребра — box-стінки по краях (дзеркало
 * enclosed-shelf). Перфорація прорідж. на великих grid'ах (`computeHoleGrid`).
 */
function PerforatedPanelSquare({ parameters, thicknessMm }: SceneProps) {
  const t = thicknessMm;
  const { length_mm: L, width_mm: W, rib_height_mm: rib } = parameters;

  const faceGeom = useMemo(() => new BoxGeometry(L, t, W), [L, W, t]);
  // Ребра по краях ширини (front/back) і довжини (left/right); підняті вгору (+Y).
  const ribLenGeom = useMemo(() => new BoxGeometry(L, rib, t), [L, rib, t]);
  const ribWidGeom = useMemo(() => new BoxGeometry(t, rib, W), [W, rib, t]);
  const ribY = t / 2 + rib / 2;

  const positions = useMemo(() => {
    const { cells } = computeHoleGrid({
      lengthMm: L,
      widthMm: W,
      pitchXMm: parameters.pitch_x_mm,
      pitchYMm: parameters.pitch_y_mm,
      marginMm: parameters.margin_mm,
    });
    return cells.map((c) => [c.u, t / 2, c.v] as const);
  }, [L, W, parameters.pitch_x_mm, parameters.pitch_y_mm, parameters.margin_mm, t]);

  const side = parameters.hole_size_mm;
  const holeGeom = useMemo(() => new BoxGeometry(side, t * 1.5, side), [side, t]);

  // 4 кутові установочні отвори (Ø5.5) — циліндри крізь площину.
  const cornerGeom = useMemo(
    () =>
      new CylinderGeometry(CORNER_HOLE_DIAMETER_MM / 2, CORNER_HOLE_DIAMETER_MM / 2, t * 1.5, 16),
    [t],
  );
  const ins = CORNER_HOLE_INSET_MM;
  const cornerPositions = useMemo(
    () =>
      [
        [-(L / 2 - ins), t / 2, -(W / 2 - ins)],
        [L / 2 - ins, t / 2, -(W / 2 - ins)],
        [-(L / 2 - ins), t / 2, W / 2 - ins],
        [L / 2 - ins, t / 2, W / 2 - ins],
      ] as const,
    [L, W, t, ins],
  );

  return (
    <group>
      <mesh geometry={faceGeom}>
        <meshStandardMaterial color="#94a3b8" metalness={0.5} roughness={0.45} />
      </mesh>
      {/* 4 ребра жорсткості (фланці вгору) */}
      <mesh geometry={ribLenGeom} position={[0, ribY, W / 2 - t / 2]}>
        <meshStandardMaterial color="#7c8aa0" metalness={0.5} roughness={0.45} />
      </mesh>
      <mesh geometry={ribLenGeom} position={[0, ribY, -(W / 2 - t / 2)]}>
        <meshStandardMaterial color="#7c8aa0" metalness={0.5} roughness={0.45} />
      </mesh>
      <mesh geometry={ribWidGeom} position={[L / 2 - t / 2, ribY, 0]}>
        <meshStandardMaterial color="#7c8aa0" metalness={0.5} roughness={0.45} />
      </mesh>
      <mesh geometry={ribWidGeom} position={[-(L / 2 - t / 2), ribY, 0]}>
        <meshStandardMaterial color="#7c8aa0" metalness={0.5} roughness={0.45} />
      </mesh>
      <InstancedHoles geometry={holeGeom} positions={positions} />
      <InstancedHoles geometry={cornerGeom} positions={cornerPositions} color="#dc2626" />
    </group>
  );
}

export function PerforatedPanelSquareScene({ parameters, thicknessMm }: SceneProps) {
  const isMobile = useIsMobile();
  const reduced = useReducedMotion();
  const quality = useMemo(() => viewportQuality({ isMobile, reduced }), [isMobile, reduced]);

  // ADR-030: bbox-aware камера (лоток L × (t+rib) × W — ребра підняли висоту).
  const placement = useMemo(
    () =>
      computeCameraPlacement({
        x: parameters.length_mm,
        y: thicknessMm + parameters.rib_height_mm,
        z: parameters.width_mm,
      }),
    [parameters.length_mm, parameters.width_mm, parameters.rib_height_mm, thicknessMm],
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
