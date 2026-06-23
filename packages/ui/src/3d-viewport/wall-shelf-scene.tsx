"use client";

import type { WallShelfParameters } from "@flatcraft/types";
import { OrbitControls } from "@react-three/drei";
import { Canvas } from "@react-three/fiber";
import { useMemo } from "react";
import { CylinderGeometry, ExtrudeGeometry, Shape } from "three";

import { useIsMobile } from "../hooks/use-is-mobile.js";
import { useReducedMotion } from "../hooks/use-reduced-motion.js";
import { viewportQuality } from "../lib/viewport-quality.js";
import { computeCameraPlacement } from "./camera-placement.js";
import { buildWallShelfShapeCommands } from "./geometry.js";

interface SceneProps {
  readonly parameters: WallShelfParameters;
  readonly thicknessMm: number;
}

/**
 * Wall-shelf 3D — один ExtrudeGeometry з Shape, що має 1 або 2 round inner
 * bends (back→shelf завжди; shelf→lip опційно при front_lip>0). Phase 2.14.b
 * замінив попередню реалізацію з 3 BoxGeometry на профіль з округлими
 * гибами у перерізі. Mount-holes на back-секції лишаються як CylinderGeometry.
 *
 * Координати profile (XY, extrude по Z = width_mm):
 *   - Back:  X ∈ [0, t],   Y ∈ [0, back_height]
 *   - Shelf: X ∈ [0, sd],  Y ∈ [0, t]
 *   - Lip (if>0): X ∈ [sd-t, sd], Y ∈ [0, front_lip]
 * Mount-holes axis ‖ X (нормаль до back-стінки), розподіл grid вздовж y-z.
 */
function linspace(n: number, lo: number, hi: number): number[] {
  if (n <= 0) return [];
  if (n === 1) return [(lo + hi) / 2];
  const step = (hi - lo) / (n - 1);
  return Array.from({ length: n }, (_, i) => lo + i * step);
}

function compileShape(parameters: WallShelfParameters, thicknessMm: number): Shape {
  const cmds = buildWallShelfShapeCommands({ parameters, thicknessMm });
  const shape = new Shape();
  for (const cmd of cmds) {
    switch (cmd.kind) {
      case "moveTo":
        shape.moveTo(cmd.x, cmd.y);
        break;
      case "lineTo":
        shape.lineTo(cmd.x, cmd.y);
        break;
      case "absarc":
        shape.absarc(cmd.cx, cmd.cy, cmd.radius, cmd.startAngleRad, cmd.endAngleRad, cmd.clockwise);
        break;
      case "closePath":
        shape.closePath();
        break;
    }
  }
  return shape;
}

interface WallShelfBodyProps extends SceneProps {
  readonly curveSegments: number;
}

function WallShelf({ parameters, thicknessMm, curveSegments }: WallShelfBodyProps) {
  const { geometry, holes } = useMemo(() => {
    const shape = compileShape(parameters, thicknessMm);
    const geom = new ExtrudeGeometry(shape, {
      depth: parameters.width_mm,
      bevelEnabled: false,
      curveSegments,
    });

    const t = thicknessMm;
    const r = parameters.bend_radius_mm;
    const bh = parameters.back_height_mm;
    const w = parameters.width_mm;
    const m = parameters.mount_hole_margin_mm;
    const flatBack = bh - t - r;
    const ys = linspace(parameters.mount_hole_cols, t + r + m, bh - m);
    const zs = linspace(parameters.mount_hole_rows, -w / 2 + m, w / 2 - m);
    const holes: Array<{ pos: readonly [number, number, number] }> = [];
    if (flatBack > 0) {
      for (const y of ys) {
        for (const z of zs) {
          // Hole-center розташовуємо у середині товщини back (x=t/2).
          // Після центрування geom (translate за boundingBox.center), всі
          // позиції живуть у тій же системі координат — group-position
          // компенсує зсув.
          holes.push({ pos: [t / 2, y, w / 2 + z] as const });
        }
      }
    }
    return { geometry: geom, holes };
  }, [parameters, thicknessMm, curveSegments]);

  geometry.computeBoundingBox();
  const bb = geometry.boundingBox;
  const cx = bb ? -((bb.max.x + bb.min.x) / 2) : 0;
  const cy = bb ? -((bb.max.y + bb.min.y) / 2) : 0;
  const cz = bb ? -((bb.max.z + bb.min.z) / 2) : 0;

  const cylRadius = parameters.mount_hole_diameter_mm / 2;
  const cylLen = thicknessMm * 1.5;
  const cylGeom = useMemo(
    () => new CylinderGeometry(cylRadius, cylRadius, cylLen, 16),
    [cylRadius, cylLen],
  );

  return (
    <group position={[cx, cy, cz]}>
      <mesh geometry={geometry}>
        <meshStandardMaterial color="#94a3b8" metalness={0.5} roughness={0.45} />
      </mesh>
      {holes.map((h, i) => (
        <mesh key={`h${i}`} geometry={cylGeom} position={h.pos} rotation={[0, 0, Math.PI / 2]}>
          <meshStandardMaterial color="#fb923c" />
        </mesh>
      ))}
    </group>
  );
}

export function WallShelfScene({ parameters, thicknessMm }: SceneProps) {
  const isMobile = useIsMobile();
  const reduced = useReducedMotion();
  const quality = useMemo(() => viewportQuality({ isMobile, reduced }), [isMobile, reduced]);

  // PR 8a: bbox-aware камера (wall_shelf: shelf_depth по X, back_height по Y, width — extrude по Z).
  const placement = useMemo(
    () =>
      computeCameraPlacement({
        x: parameters.shelf_depth_mm,
        y: parameters.back_height_mm,
        z: parameters.width_mm,
      }),
    [parameters.shelf_depth_mm, parameters.back_height_mm, parameters.width_mm],
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
      data-testid="wall-shelf-canvas"
    >
      <ambientLight intensity={0.55} />
      <directionalLight position={[1, 2, 1.5]} intensity={1.2} />
      <WallShelf
        parameters={parameters}
        thicknessMm={thicknessMm}
        curveSegments={quality.curveSegments}
      />
      <OrbitControls
        enablePan={false}
        enableZoom={quality.enableZoom}
        enableRotate={quality.enableRotate}
      />
    </Canvas>
  );
}
