"use client";

import type { ZBracketParameters } from "@flatcraft/types";
import { OrbitControls } from "@react-three/drei";
import { Canvas } from "@react-three/fiber";
import { useMemo } from "react";
import { ExtrudeGeometry, Shape } from "three";

import { useIsMobile } from "../hooks/use-is-mobile.js";
import { useReducedMotion } from "../hooks/use-reduced-motion.js";
import { viewportQuality } from "../lib/viewport-quality.js";
import { buildZBracketShapeCommands } from "./geometry.js";

interface SceneProps {
  readonly parameters: ZBracketParameters;
  readonly thicknessMm: number;
}

/**
 * 3D Z-bracket — один ExtrudeGeometry з Shape, що має два round inner bends.
 * Phase 2.14.b замінив попередню реалізацію (3 union'ані BoxGeometry з
 * прямими стиками) — щоб гиби виглядали реалістично у перерізі.
 */
function compileShape(parameters: ZBracketParameters, thicknessMm: number): Shape {
  const cmds = buildZBracketShapeCommands({ parameters, thicknessMm });
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

interface BracketProps extends SceneProps {
  readonly curveSegments: number;
}

function Bracket({ parameters, thicknessMm, curveSegments }: BracketProps) {
  const geometry = useMemo(() => {
    const shape = compileShape(parameters, thicknessMm);
    return new ExtrudeGeometry(shape, {
      depth: parameters.width_mm,
      bevelEnabled: false,
      curveSegments,
    });
  }, [parameters, thicknessMm, curveSegments]);

  geometry.computeBoundingBox();
  const bb = geometry.boundingBox;
  const cx = bb ? -((bb.max.x + bb.min.x) / 2) : 0;
  const cy = bb ? -((bb.max.y + bb.min.y) / 2) : 0;
  const cz = bb ? -((bb.max.z + bb.min.z) / 2) : 0;

  return (
    <mesh geometry={geometry} position={[cx, cy, cz]}>
      <meshStandardMaterial color="#94a3b8" metalness={0.5} roughness={0.45} />
    </mesh>
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
      <Bracket
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
