"use client";

import { useLayoutEffect, useMemo, useRef } from "react";
import { type BufferGeometry, type InstancedMesh, MeshStandardMaterial, Object3D } from "three";

interface InstancedHolesProps {
  /** Геометрія одного отвору (Box для квадратних, Cylinder для круглих). */
  readonly geometry: BufferGeometry;
  /** Позиції центрів отворів у локальних координатах групи. */
  readonly positions: ReadonlyArray<readonly [number, number, number]>;
  /** Колір overlay-отворів (за замовч. помаранчевий бренд-акцент). */
  readonly color?: string;
}

// Спільний dummy для обчислення матриць — без алокацій у циклі.
const dummy = new Object3D();

/**
 * Рендерить grid отворів-overlay через `InstancedMesh` — один draw call на всі
 * отвори (раніше: окремий `<mesh>` на кожен отвір + жорсткий cap, що при
 * перевищенні гасив усю перфорацію). Кількість інстансів фіксується при
 * ініціалізації через args[2], тож `key={positions.length}` пересоздає mesh,
 * коли кількість змінюється (зміна розмірів/кроку).
 */
export function InstancedHoles({ geometry, positions, color = "#fb923c" }: InstancedHolesProps) {
  const ref = useRef<InstancedMesh>(null);
  const material = useMemo(() => new MeshStandardMaterial({ color }), [color]);

  useLayoutEffect(() => {
    const mesh = ref.current;
    if (!mesh) return;
    for (let i = 0; i < positions.length; i++) {
      const p = positions[i];
      if (!p) continue;
      dummy.position.set(p[0], p[1], p[2]);
      dummy.updateMatrix();
      mesh.setMatrixAt(i, dummy.matrix);
    }
    mesh.instanceMatrix.needsUpdate = true;
  }, [positions]);

  return (
    <instancedMesh key={positions.length} ref={ref} args={[geometry, material, positions.length]} />
  );
}
