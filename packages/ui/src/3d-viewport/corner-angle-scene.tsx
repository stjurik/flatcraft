"use client";

import type { CornerAngleParameters } from "@flatcraft/types";
import { OrbitControls } from "@react-three/drei";
import { Canvas } from "@react-three/fiber";
import { useMemo } from "react";
import { CylinderGeometry, ExtrudeGeometry, Shape } from "three";

import { useIsMobile } from "../hooks/use-is-mobile.js";
import { useReducedMotion } from "../hooks/use-reduced-motion.js";
import { viewportQuality } from "../lib/viewport-quality.js";
import { computeCameraPlacement } from "./camera-placement.js";
import { buildLBracketShapeCommands } from "./geometry.js";

interface SceneProps {
  readonly parameters: CornerAngleParameters;
  readonly thicknessMm: number;
}

/**
 * Corner_angle 3D — L-shape (reuse buildLBracketShapeCommands) +
 * cylinder-отвори, видимі на обох полицях. Hole positions у preview
 * — приблизні (margin + linspace), точні координати — у DXF/PDF.
 *
 * Координати profile (з l-bracket-scene): X = leg_b, Y = leg_a, Z = width.
 * Bottom flange B: y ∈ [0, t], x ∈ [0, b]. Cylinder axis ‖ Y.
 * Vertical flange A: x ∈ [0, t], y ∈ [0, a]. Cylinder axis ‖ X.
 */
function linspace(n: number, lo: number, hi: number): number[] {
  if (n <= 0) return [];
  if (n === 1) return [(lo + hi) / 2];
  const step = (hi - lo) / (n - 1);
  return Array.from({ length: n }, (_, i) => lo + i * step);
}

function CornerAngle({ parameters, thicknessMm }: SceneProps) {
  const { profileGeom, holesB, holesA } = useMemo(() => {
    const cmds = buildLBracketShapeCommands({
      parameters: {
        legA_mm: parameters.legA_mm,
        legB_mm: parameters.legB_mm,
        bend_radius_mm: parameters.bend_radius_mm,
        bend_angle_deg: parameters.bend_angle_deg,
        width_mm: parameters.width_mm,
        holes: [],
      },
      thicknessMm,
    });
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
          shape.absarc(
            cmd.cx,
            cmd.cy,
            cmd.radius,
            cmd.startAngleRad,
            cmd.endAngleRad,
            cmd.clockwise,
          );
          break;
        case "closePath":
          shape.closePath();
          break;
      }
    }
    const geom = new ExtrudeGeometry(shape, {
      depth: parameters.width_mm,
      bevelEnabled: false,
    });

    // Hole positions (приблизні для preview).
    const t = thicknessMm;
    const r = parameters.bend_radius_mm;
    const m = parameters.hole_margin_mm;
    const cylRadius = parameters.hole_diameter_mm / 2;
    const cylLen = t * 1.5;

    // Уздовж ширини Z — однакова для обох полиць.
    const zs = linspace(parameters.hole_rows, m, parameters.width_mm - m);

    // Flange B: x уздовж [t+r+m, b-m] (flat region з відступом).
    const xs_b = linspace(parameters.hole_cols, t + r + m, parameters.legB_mm - m);
    // Flange A: y уздовж [t+r+m, a-m].
    const ys_a = linspace(parameters.hole_cols, t + r + m, parameters.legA_mm - m);

    const cyl = new CylinderGeometry(cylRadius, cylRadius, cylLen, 16);
    const holesB: { pos: readonly [number, number, number] }[] = [];
    for (const x of xs_b) {
      for (const z of zs) {
        // Y is center of bottom flange thickness.
        holesB.push({ pos: [x, t / 2, z] as const });
      }
    }
    const holesA: { pos: readonly [number, number, number] }[] = [];
    for (const y of ys_a) {
      for (const z of zs) {
        holesA.push({ pos: [t / 2, y, z] as const });
      }
    }

    return { profileGeom: geom, holesB, holesA, cylGeom: cyl };
  }, [parameters, thicknessMm]);

  profileGeom.computeBoundingBox();
  const bb = profileGeom.boundingBox;
  const cx = bb ? -((bb.max.x + bb.min.x) / 2) : 0;
  const cy = bb ? -((bb.max.y + bb.min.y) / 2) : 0;
  const cz = bb ? -((bb.max.z + bb.min.z) / 2) : 0;

  // Cylinder shared geometry — нова instance на кожен render не критична
  // (R3F dispose'не геометрії), але reuse покращує перформанс.
  const cylRadius = parameters.hole_diameter_mm / 2;
  const cylLen = thicknessMm * 1.5;
  const cylGeom = useMemo(
    () => new CylinderGeometry(cylRadius, cylRadius, cylLen, 16),
    [cylRadius, cylLen],
  );

  return (
    <group position={[cx, cy, cz]}>
      <mesh geometry={profileGeom}>
        <meshStandardMaterial color="#94a3b8" metalness={0.5} roughness={0.45} />
      </mesh>
      {holesB.map((h, i) => (
        <mesh key={`b${i}`} geometry={cylGeom} position={h.pos}>
          {/* CylinderGeometry default axis = Y → flange B (axis ‖ Y) — без rotation. */}
          <meshStandardMaterial color="#fb923c" />
        </mesh>
      ))}
      {holesA.map((h, i) => (
        <mesh key={`a${i}`} geometry={cylGeom} position={h.pos} rotation={[0, 0, Math.PI / 2]}>
          {/* Поворот на 90° навколо Z → axis ‖ X (flange A). */}
          <meshStandardMaterial color="#fb923c" />
        </mesh>
      ))}
    </group>
  );
}

export function CornerAngleScene({ parameters, thicknessMm }: SceneProps) {
  const isMobile = useIsMobile();
  const reduced = useReducedMotion();
  const quality = useMemo(() => viewportQuality({ isMobile, reduced }), [isMobile, reduced]);

  // PR 8a: bbox-aware камера (corner_angle: legA × legB по X/Y, width — extrude по Z).
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
      data-testid="corner-angle-canvas"
    >
      <ambientLight intensity={0.55} />
      <directionalLight position={[1, 2, 1.5]} intensity={1.2} />
      <CornerAngle parameters={parameters} thicknessMm={thicknessMm} />
      <OrbitControls
        enablePan={false}
        enableZoom={quality.enableZoom}
        enableRotate={quality.enableRotate}
      />
    </Canvas>
  );
}
