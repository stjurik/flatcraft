"use client";

import type { LBracketParameters } from "@flatcraft/types";
import { OrbitControls } from "@react-three/drei";
import { Canvas } from "@react-three/fiber";
import { useMemo } from "react";
import { ExtrudeGeometry, Shape } from "three";

import { useIsMobile } from "../hooks/use-is-mobile.js";
import { useReducedMotion } from "../hooks/use-reduced-motion.js";
import { viewportQuality } from "../lib/viewport-quality.js";
import { computeCameraPlacement } from "./camera-placement.js";
import { buildLBracketShapeCommands } from "./geometry.js";

interface SceneProps {
  readonly parameters: LBracketParameters;
  /** Товщина листа, мм. UI вибір — Phase 2.4 (MaterialPicker). */
  readonly thicknessMm: number;
}

function compileShape(parameters: LBracketParameters, thicknessMm: number): Shape {
  const cmds = buildLBracketShapeCommands({ parameters, thicknessMm });
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

export function LBracketScene({ parameters, thicknessMm }: SceneProps) {
  const isMobile = useIsMobile();
  const reduced = useReducedMotion();
  const quality = useMemo(() => viewportQuality({ isMobile, reduced }), [isMobile, reduced]);

  // PR 8a: bbox-aware камера (L-bracket: legA × legB по X/Y, width — extrude по Z).
  const placement = useMemo(
    () =>
      computeCameraPlacement({
        x: parameters.legA_mm,
        y: parameters.legB_mm,
        z: parameters.width_mm,
      }),
    [parameters.legA_mm, parameters.legB_mm, parameters.width_mm],
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
      data-testid="l-bracket-canvas"
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
