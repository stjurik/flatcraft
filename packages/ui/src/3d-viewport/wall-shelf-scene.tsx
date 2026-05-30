"use client";

import type { WallShelfParameters } from "@flatcraft/types";
import { OrbitControls } from "@react-three/drei";
import { Canvas } from "@react-three/fiber";
import { useMemo } from "react";
import { BoxGeometry, CylinderGeometry } from "three";

interface SceneProps {
  readonly parameters: WallShelfParameters;
  readonly thicknessMm: number;
}

/**
 * Wall shelf 3D — 2-3 box union'и + cylinder отвори на back.
 *
 * Coord convention (XY profile, extrude по Z = width):
 *   - Back: x ∈ [0, t], y ∈ [0, back_height], z ∈ [0, width]
 *   - Shelf: x ∈ [0, shelf_depth], y ∈ [0, t]
 *   - Lip (if > 0): x ∈ [shelf_depth - t, shelf_depth], y ∈ [0, front_lip]
 *
 * Mount holes: cylinder axis ‖ X (perpendicular to back face),
 * розподіл grid вздовж back-секції з відступом hole_margin.
 */
function linspace(n: number, lo: number, hi: number): number[] {
  if (n <= 0) return [];
  if (n === 1) return [(lo + hi) / 2];
  const step = (hi - lo) / (n - 1);
  return Array.from({ length: n }, (_, i) => lo + i * step);
}

function WallShelf({ parameters, thicknessMm }: SceneProps) {
  const { boxes, holes } = useMemo(() => {
    const t = thicknessMm;
    const r = parameters.bend_radius_mm;
    const bh = parameters.back_height_mm;
    const sd = parameters.shelf_depth_mm;
    const lip = parameters.front_lip_mm;
    const w = parameters.width_mm;

    const back = {
      geom: new BoxGeometry(t, bh, w),
      pos: [t / 2, bh / 2, 0] as const,
    };
    const shelf = {
      geom: new BoxGeometry(sd, t, w),
      pos: [sd / 2, t / 2, 0] as const,
    };
    const boxes: Array<{ geom: BoxGeometry; pos: readonly [number, number, number] }> = [
      back,
      shelf,
    ];
    if (lip > 0) {
      boxes.push({
        geom: new BoxGeometry(t, lip, w),
        pos: [sd - t / 2, lip / 2, 0] as const,
      });
    }

    // Mount holes на back: розподіл уздовж y (висота) і z (ширина).
    const m = parameters.mount_hole_margin_mm;
    const flatBack = bh - t - r;
    const ys = linspace(parameters.mount_hole_cols, t + r + m, bh - m);
    const zs = linspace(parameters.mount_hole_rows, -w / 2 + m, w / 2 - m);
    const holes: Array<{ pos: readonly [number, number, number] }> = [];
    if (flatBack > 0) {
      for (const y of ys) {
        for (const z of zs) {
          holes.push({ pos: [t / 2, y, z] as const });
        }
      }
    }

    return { boxes, holes };
  }, [parameters, thicknessMm]);

  // Cylinder для всіх отворів (axis ‖ X після rotation Z).
  const cylRadius = parameters.mount_hole_diameter_mm / 2;
  const cylLen = thicknessMm * 1.5;
  const cylGeom = useMemo(
    () => new CylinderGeometry(cylRadius, cylRadius, cylLen, 16),
    [cylRadius, cylLen],
  );

  // Центрування навколо origin для зручного огляду.
  const cx = -parameters.shelf_depth_mm / 2;
  const cy = -Math.max(parameters.back_height_mm, parameters.front_lip_mm) / 2;

  return (
    <group position={[cx, cy, 0]}>
      {boxes.map((b, i) => (
        <mesh key={i} geometry={b.geom} position={b.pos}>
          <meshStandardMaterial color="#94a3b8" metalness={0.5} roughness={0.45} />
        </mesh>
      ))}
      {holes.map((h, i) => (
        <mesh key={`h${i}`} geometry={cylGeom} position={h.pos} rotation={[0, 0, Math.PI / 2]}>
          <meshStandardMaterial color="#fb923c" />
        </mesh>
      ))}
    </group>
  );
}

export function WallShelfScene({ parameters, thicknessMm }: SceneProps) {
  const maxDim = Math.max(
    parameters.shelf_depth_mm,
    parameters.back_height_mm,
    parameters.width_mm,
  );
  const camDist = maxDim * 1.5;
  return (
    <Canvas
      camera={{ position: [camDist, camDist * 0.6, camDist], fov: 35 }}
      data-testid="wall-shelf-canvas"
    >
      <ambientLight intensity={0.55} />
      <directionalLight position={[1, 2, 1.5]} intensity={1.2} />
      <WallShelf parameters={parameters} thicknessMm={thicknessMm} />
      <OrbitControls enablePan={false} />
    </Canvas>
  );
}
