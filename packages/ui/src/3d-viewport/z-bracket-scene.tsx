"use client";

import type { ZBracketParameters } from "@flatcraft/types";
import { OrbitControls } from "@react-three/drei";
import { Canvas } from "@react-three/fiber";
import { useMemo } from "react";
import { BoxGeometry } from "three";

import { useIsMobile } from "../hooks/use-is-mobile.js";
import { useReducedMotion } from "../hooks/use-reduced-motion.js";
import { viewportQuality } from "../lib/viewport-quality.js";

interface SceneProps {
  readonly parameters: ZBracketParameters;
  readonly thicknessMm: number;
}

/**
 * 3D-mesh Z-bracket — три плити union'ані координатно (бо three.js
 * не має готового boolean без CSG-бібліотеки; для preview overlap не
 * критичний). Точна геометрія для DXF — server-side через CadQuery.
 *
 *       ─────────────  ← top_flange (y = offset)
 *                   │
 *                   │  ← vertical middle
 *                   │
 *                   ─────────────  ← bottom_flange (y = 0)
 */
function Bracket({ parameters, thicknessMm }: SceneProps) {
  const meshes = useMemo(() => {
    const t = thicknessMm;
    const bf = parameters.bottom_flange_mm;
    const tf = parameters.top_flange_mm;
    const off = parameters.offset_mm;
    const w = parameters.width_mm;

    // BoxGeometry центрується в origin → translate'имо через position.
    return {
      bottom: {
        geom: new BoxGeometry(bf, t, w),
        pos: [bf / 2, t / 2, 0] as const,
      },
      middle: {
        geom: new BoxGeometry(t, off + t, w),
        pos: [bf - t / 2, (off + t) / 2, 0] as const,
      },
      top: {
        geom: new BoxGeometry(tf, t, w),
        pos: [bf - t + tf / 2, off + t / 2, 0] as const,
      },
    };
  }, [parameters, thicknessMm]);

  // Центруємо bracket навколо origin для приємного огляду.
  const cx = -(parameters.bottom_flange_mm - thicknessMm + parameters.top_flange_mm) / 2;
  const cy = -(parameters.offset_mm + thicknessMm) / 2;

  return (
    <group position={[cx, cy, 0]}>
      <mesh geometry={meshes.bottom.geom} position={meshes.bottom.pos}>
        <meshStandardMaterial color="#94a3b8" metalness={0.5} roughness={0.45} />
      </mesh>
      <mesh geometry={meshes.middle.geom} position={meshes.middle.pos}>
        <meshStandardMaterial color="#94a3b8" metalness={0.5} roughness={0.45} />
      </mesh>
      <mesh geometry={meshes.top.geom} position={meshes.top.pos}>
        <meshStandardMaterial color="#94a3b8" metalness={0.5} roughness={0.45} />
      </mesh>
    </group>
  );
}

export function ZBracketScene({ parameters, thicknessMm }: SceneProps) {
  const isMobile = useIsMobile();
  const reduced = useReducedMotion();
  const quality = useMemo(() => viewportQuality({ isMobile, reduced }), [isMobile, reduced]);

  const maxDim = Math.max(
    parameters.bottom_flange_mm + parameters.top_flange_mm,
    parameters.offset_mm,
    parameters.width_mm,
  );
  const camDist = maxDim * 1.5;
  return (
    <Canvas
      dpr={[...quality.dpr]}
      camera={{ position: [camDist, camDist * 0.8, camDist], fov: 35 }}
      data-testid="z-bracket-canvas"
    >
      <ambientLight intensity={0.55} />
      <directionalLight position={[1, 2, 1.5]} intensity={1.2} />
      <Bracket parameters={parameters} thicknessMm={thicknessMm} />
      <OrbitControls
        enablePan={false}
        enableZoom={quality.enableZoom}
        enableRotate={quality.enableRotate}
      />
    </Canvas>
  );
}
