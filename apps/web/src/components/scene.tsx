"use client";

import { OrbitControls } from "@react-three/drei";
import { Canvas, useFrame } from "@react-three/fiber";
import { useRef } from "react";
import type { Mesh } from "three";

function Cube() {
  const ref = useRef<Mesh>(null);
  useFrame((_, delta) => {
    if (ref.current) {
      ref.current.rotation.x += delta * 0.6;
      ref.current.rotation.y += delta * 0.4;
    }
  });
  return (
    <mesh ref={ref}>
      <boxGeometry args={[1.6, 1.6, 1.6]} />
      <meshStandardMaterial color="#22c55e" metalness={0.3} roughness={0.4} />
    </mesh>
  );
}

export function Scene() {
  return (
    <Canvas camera={{ position: [3.5, 2.5, 3.5], fov: 45 }} data-testid="r3f-canvas">
      <ambientLight intensity={0.6} />
      <directionalLight position={[5, 8, 4]} intensity={1.2} />
      <Cube />
      <OrbitControls enablePan={false} />
    </Canvas>
  );
}
