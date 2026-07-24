"use client";

/**
 * Generic extrude-сцена (Run 7 Master Registry Track, Етап 2, міграція
 * l_bracket) — рендерить БУДЬ-ЯКИЙ `kind: 'extrude'` шаблон (docs/12 §1
 * Рішення 4 / ADR-033) через `THREE.ExtrudeGeometry` над `ShapeCommand[]`,
 * що поставляє `TemplateDefinition.ui.scene.build(params, thicknessMm)`.
 *
 * Один компонент для ВСІХ extrude-шаблонів (l_bracket зараз, z_bracket/
 * wall_shelf — наступні PR) — аналог `COMPOSED_SCENES`-роутера для
 * `kind:'composed'`, але тут навіть lookup не потрібен: `ShapeCommand[]` і
 * depth (довжина лінії гиба) обчислює викликач (`RegistryTemplateViewport`)
 * з `TemplateDefinition`, самому компоненту імена полів параметрів
 * невідомі.
 *
 * Камера: bbox профілю по X/Y обчислюється з самих `ShapeCommand[]` (без
 * побудови THREE-геометрії) + depth по Z — узгоджено з ADR-033
 * «Єдина консистентна конвенція осей: X×Y = силует профілю, Z = довжина
 * лінії гиба».
 */
import type { ShapeCommand } from "@flatcraft/cad-engine/geometry";
import { OrbitControls } from "@react-three/drei";
import { Canvas } from "@react-three/fiber";
import { useMemo } from "react";
import { ExtrudeGeometry, Shape } from "three";

import { useIsMobile } from "../hooks/use-is-mobile.js";
import { useReducedMotion } from "../hooks/use-reduced-motion.js";
import { viewportQuality } from "../lib/viewport-quality.js";
import { computeCameraPlacement } from "./camera-placement.js";

function compileShape(commands: readonly ShapeCommand[]): Shape {
  const shape = new Shape();
  for (const cmd of commands) {
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

/** Приблизний XY bbox 2D-профілю з raw команд (без THREE) — для камери ДО побудови mesh. */
function commandBoundsXY(commands: readonly ShapeCommand[]): {
  readonly width: number;
  readonly height: number;
} {
  let minX = Infinity;
  let maxX = -Infinity;
  let minY = Infinity;
  let maxY = -Infinity;
  for (const cmd of commands) {
    if (cmd.kind === "moveTo" || cmd.kind === "lineTo") {
      minX = Math.min(minX, cmd.x);
      maxX = Math.max(maxX, cmd.x);
      minY = Math.min(minY, cmd.y);
      maxY = Math.max(maxY, cmd.y);
    } else if (cmd.kind === "absarc") {
      // Консервативна оцінка — коло радіусом навколо центра, не точна дуга.
      minX = Math.min(minX, cmd.cx - cmd.radius);
      maxX = Math.max(maxX, cmd.cx + cmd.radius);
      minY = Math.min(minY, cmd.cy - cmd.radius);
      maxY = Math.max(maxY, cmd.cy + cmd.radius);
    }
  }
  if (!Number.isFinite(minX) || !Number.isFinite(minY)) return { width: 0, height: 0 };
  return { width: maxX - minX, height: maxY - minY };
}

interface ExtrudedMeshProps {
  readonly commands: readonly ShapeCommand[];
  readonly depthMm: number;
  readonly curveSegments: number;
}

function ExtrudedMesh({ commands, depthMm, curveSegments }: ExtrudedMeshProps) {
  const geometry = useMemo(() => {
    const shape = compileShape(commands);
    return new ExtrudeGeometry(shape, { depth: depthMm, bevelEnabled: false, curveSegments });
  }, [commands, depthMm, curveSegments]);

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

export interface ExtrudeSceneProps {
  readonly commands: readonly ShapeCommand[];
  /** Довжина екструзії (лінія гиба), мм — конвенція `width_mm` (ADR-033). */
  readonly depthMm: number;
  readonly testId: string;
}

export function ExtrudeScene({ commands, depthMm, testId }: ExtrudeSceneProps) {
  const isMobile = useIsMobile();
  const reduced = useReducedMotion();
  const quality = useMemo(() => viewportQuality({ isMobile, reduced }), [isMobile, reduced]);

  const bounds = useMemo(() => commandBoundsXY(commands), [commands]);
  const placement = useMemo(
    () => computeCameraPlacement({ x: bounds.width, y: bounds.height, z: depthMm }),
    [bounds.width, bounds.height, depthMm],
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
      data-testid={testId}
    >
      <ambientLight intensity={0.55} />
      <directionalLight position={[1, 2, 1.5]} intensity={1.2} />
      <ExtrudedMesh commands={commands} depthMm={depthMm} curveSegments={quality.curveSegments} />
      <OrbitControls
        enablePan={false}
        enableZoom={quality.enableZoom}
        enableRotate={quality.enableRotate}
      />
    </Canvas>
  );
}
