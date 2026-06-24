"use client";

import type { EnclosedShelfParameters } from "@flatcraft/types";
import { OrbitControls } from "@react-three/drei";
import { Canvas } from "@react-three/fiber";
import { useMemo } from "react";
import { BoxGeometry } from "three";

import { useIsMobile } from "../hooks/use-is-mobile.js";
import { useReducedMotion } from "../hooks/use-reduced-motion.js";
import { viewportQuality } from "../lib/viewport-quality.js";
import { computeCameraPlacement } from "./camera-placement.js";
import { computeHoleGrid, DEFAULT_MAX_HOLES_PREVIEW } from "./hole-grid.js";
import { InstancedHoles } from "./instanced-holes.js";

interface SceneProps {
  readonly parameters: EnclosedShelfParameters;
  readonly thicknessMm: number;
}

/**
 * Enclosed shelf 3D — 4 (або 5 з rib) BoxGeometry-сегменти у Y-up системі
 * (Phase 3.0 PR 7d, ADR-027 Рішення 5). Паритет з `build_enclosed_shelf`
 * Python-builder'ом, але three.js Y-up:
 *   - X (three) ← x (Python): ширина полиці
 *   - Y (three) ← z (Python): vertical, +Y вгору
 *   - Z (three) ← y (Python): глибина полиці
 *
 * Сегменти центруємо навколо origin для зручної камери.
 *
 * Side perforation — overlay BoxGeometry на боковинах (декоративний preview,
 * не вирізаємо solid; той самий patern, що у PerforatedPanelSquareScene).
 */
function EnclosedShelf({ parameters, thicknessMm }: SceneProps) {
  const t = thicknessMm;
  const w = parameters.width_mm;
  const d = parameters.depth_mm;
  const rh = parameters.stiffening_rib?.height_mm ?? 0;

  const { segments, perforationPositions } = useMemo(() => {
    const bottomGeom = new BoxGeometry(w, t, d);
    const backGeom = new BoxGeometry(w, d, t);
    const sideGeom = new BoxGeometry(t, d, d);

    // Координати центрів сегментів у Python-системі (origin at near-left-bottom),
    // потім зсунемо групу до центру.
    const segs: Array<{
      geom: BoxGeometry;
      pos: readonly [number, number, number];
      key: string;
    }> = [
      // bottom: x∈[0,w], z∈[0,t], y∈[0,d] (Python z→Y, Python y→Z)
      { geom: bottomGeom, pos: [w / 2, t / 2, d / 2] as const, key: "bottom" },
      // back: x∈[0,w], z∈[t,t+d], y∈[d-t,d]
      { geom: backGeom, pos: [w / 2, t + d / 2, d - t / 2] as const, key: "back" },
      // left: x∈[0,t], z∈[t,t+d], y∈[0,d]
      { geom: sideGeom, pos: [t / 2, t + d / 2, d / 2] as const, key: "left" },
      // right: x∈[w-t,w], z∈[t,t+d], y∈[0,d]
      { geom: sideGeom, pos: [w - t / 2, t + d / 2, d / 2] as const, key: "right" },
    ];

    if (parameters.stiffening_rib) {
      const ribGeom = new BoxGeometry(w, rh, t);
      // rib: x∈[0,w], z∈[t,t+rh], y∈[0,t]
      segs.push({ geom: ribGeom, pos: [w / 2, t + rh / 2, t / 2] as const, key: "rib" });
    }

    // Перфорація боковин (left + right), декоративний overlay через
    // InstancedHoles. Великі grid'и граційно проріджуються (`computeHoleGrid`),
    // а не гасяться повністю (раніше total>cap → нуль отворів).
    const perfPositions: Array<readonly [number, number, number]> = [];
    if (parameters.side_perforation) {
      const sp = parameters.side_perforation;
      // sides квадратні d×d; pitch_x вздовж глибини (Y), pitch_y вздовж висоти (Z).
      if (d - 2 * sp.margin_mm >= 0) {
        // maxHoles/2 — бо кожну клітинку дублюємо на left+right боковини.
        const { cells } = computeHoleGrid({
          lengthMm: d,
          widthMm: d,
          pitchXMm: sp.pitch_x_mm,
          pitchYMm: sp.pitch_y_mm,
          marginMm: sp.margin_mm,
          maxHoles: DEFAULT_MAX_HOLES_PREVIEW / 2,
        });
        for (const c of cells) {
          const ydepth = c.u + d / 2; // де-центруємо у локальну систему групи
          const zheight = t + c.v + d / 2;
          // left side: x≈t/2; right side: x≈w−t/2 — overlay прокол по X.
          perfPositions.push([t / 2, zheight, ydepth] as const);
          perfPositions.push([w - t / 2, zheight, ydepth] as const);
        }
      }
    }

    return { segments: segs, perforationPositions: perfPositions };
  }, [w, d, t, rh, parameters.stiffening_rib, parameters.side_perforation]);

  // Геометрія одного бокового отвору (прокол по X; квадрат у площині бічної стінки).
  const sidePerf = parameters.side_perforation;
  const perfGeom = useMemo(
    () =>
      sidePerf ? new BoxGeometry(t * 1.5, sidePerf.hole_size_mm, sidePerf.hole_size_mm) : null,
    [sidePerf, t],
  );

  // Центрування групи навколо origin.
  const cx = -w / 2;
  const cy = -(t + d) / 2;
  const cz = -d / 2;

  return (
    <group position={[cx, cy, cz]}>
      {segments.map((s) => (
        <mesh key={s.key} geometry={s.geom} position={s.pos}>
          <meshStandardMaterial color="#94a3b8" metalness={0.5} roughness={0.45} />
        </mesh>
      ))}
      {perfGeom && perforationPositions.length > 0 ? (
        <InstancedHoles geometry={perfGeom} positions={perforationPositions} />
      ) : null}
    </group>
  );
}

export function EnclosedShelfScene({ parameters, thicknessMm }: SceneProps) {
  const isMobile = useIsMobile();
  const reduced = useReducedMotion();
  const quality = useMemo(() => viewportQuality({ isMobile, reduced }), [isMobile, reduced]);

  // PR 8a: камера з урахуванням реального bbox (W × (t+d+rib) × D). Раніше
  // `camDist = maxDim * 1.6 + fov=35°` клипав габаритну полицю (1000×300).
  const placement = useMemo(
    () =>
      computeCameraPlacement({
        x: parameters.width_mm,
        y: thicknessMm + parameters.depth_mm + (parameters.stiffening_rib?.height_mm ?? 0),
        z: parameters.depth_mm,
      }),
    [parameters.width_mm, parameters.depth_mm, parameters.stiffening_rib, thicknessMm],
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
      data-testid="enclosed-shelf-canvas"
    >
      <ambientLight intensity={0.55} />
      <directionalLight position={[1, 2, 1.5]} intensity={1.2} />
      <EnclosedShelf parameters={parameters} thicknessMm={thicknessMm} />
      <OrbitControls
        enablePan={false}
        enableZoom={quality.enableZoom}
        enableRotate={quality.enableRotate}
      />
    </Canvas>
  );
}
