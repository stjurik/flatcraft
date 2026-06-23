"use client";

import type { EnclosedShelfParameters } from "@flatcraft/types";
import { OrbitControls } from "@react-three/drei";
import { Canvas } from "@react-three/fiber";
import { useMemo } from "react";
import { BoxGeometry } from "three";

import { useIsMobile } from "../hooks/use-is-mobile.js";
import { useReducedMotion } from "../hooks/use-reduced-motion.js";
import { viewportQuality } from "../lib/viewport-quality.js";

interface SceneProps {
  readonly parameters: EnclosedShelfParameters;
  readonly thicknessMm: number;
}

const MAX_PERFORATION_PREVIEW = 200;

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

  const { segments, perforations } = useMemo(() => {
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

    // Перфорація боковин (left + right), декоративний overlay.
    const perfs: Array<{ geom: BoxGeometry; pos: readonly [number, number, number]; key: string }> =
      [];
    if (parameters.side_perforation) {
      const sp = parameters.side_perforation;
      const availYz = d - 2 * sp.margin_mm; // вздовж Y (depth) — sides квадратні d×d
      const availZy = d - 2 * sp.margin_mm;
      if (availYz >= 0 && availZy >= 0) {
        const nCols = Math.max(1, Math.floor(availYz / sp.pitch_x_mm) + 1);
        const nRows = Math.max(1, Math.floor(availZy / sp.pitch_y_mm) + 1);
        const total = nCols * nRows * 2;
        if (total <= MAX_PERFORATION_PREVIEW) {
          const effMarginY = (d - (nCols - 1) * sp.pitch_x_mm) / 2;
          const effMarginZ = (d - (nRows - 1) * sp.pitch_y_mm) / 2;
          const holeLen = t * 1.5;
          const holeGeom = new BoxGeometry(holeLen, sp.hole_size_mm, sp.hole_size_mm);
          for (let i = 0; i < nCols; i++) {
            const ydepth = effMarginY + i * sp.pitch_x_mm;
            for (let j = 0; j < nRows; j++) {
              const zheight = t + effMarginZ + j * sp.pitch_y_mm;
              // left side: x≈t/2 — overlay прокол по X
              perfs.push({
                geom: holeGeom,
                pos: [t / 2, zheight, ydepth] as const,
                key: `pl-${i}-${j}`,
              });
              perfs.push({
                geom: holeGeom,
                pos: [w - t / 2, zheight, ydepth] as const,
                key: `pr-${i}-${j}`,
              });
            }
          }
        }
      }
    }

    return { segments: segs, perforations: perfs };
  }, [w, d, t, rh, parameters.stiffening_rib, parameters.side_perforation]);

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
      {perforations.map((p) => (
        <mesh key={p.key} geometry={p.geom} position={p.pos}>
          <meshStandardMaterial color="#fb923c" />
        </mesh>
      ))}
    </group>
  );
}

export function EnclosedShelfScene({ parameters, thicknessMm }: SceneProps) {
  const isMobile = useIsMobile();
  const reduced = useReducedMotion();
  const quality = useMemo(() => viewportQuality({ isMobile, reduced }), [isMobile, reduced]);

  const maxDim = Math.max(parameters.width_mm, parameters.depth_mm);
  const camDist = maxDim * 1.6;
  return (
    <Canvas
      dpr={[...quality.dpr]}
      camera={{ position: [camDist, camDist * 0.7, camDist], fov: 35 }}
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
