/**
 * Тести camera-placement helper (PR 8a).
 *
 * Перевіряємо інваріант: при кутовій камері з вказаним fov і safety=1.4
 * далекий кут bbox завжди опиняється у frustum (видимий, не клипається).
 */
import { describe, expect, it } from "vitest";

import { computeCameraPlacement } from "./camera-placement.js";

describe("computeCameraPlacement", () => {
  it("повертає consistent shape для дрібної деталі (100×100×100)", () => {
    const cp = computeCameraPlacement({ x: 100, y: 100, z: 100 });
    expect(cp.position).toHaveLength(3);
    expect(cp.fov).toBe(40);
    expect(cp.near).toBe(1);
    expect(cp.far).toBeGreaterThan(cp.position[0]);
  });

  it("для габаритної деталі (1000×300×300) camDist >> maxDim", () => {
    const cp = computeCameraPlacement({ x: 1000, y: 300, z: 300 });
    // halfDiag = sqrt(500² + 150² + 150²) ≈ 543
    // camDist = 543 / sin(20°) * 1.4 ≈ 2223
    expect(cp.position[0]).toBeGreaterThan(1500);
    expect(cp.far).toBeGreaterThan(8000);
  });

  it("кутове позиціонування за замовчуванням [0.85, 0.6, 0.85]", () => {
    const cp = computeCameraPlacement({ x: 100, y: 100, z: 100 });
    const [x, y, z] = cp.position;
    expect(x).toBeCloseTo(z, 5);
    expect(y).toBeLessThan(x);
  });

  it("frustum гарантовано покриває bbox: half-diag < camDist * sin(fov/2)", () => {
    const sizes: ReadonlyArray<readonly [number, number, number]> = [
      [50, 50, 50],
      [200, 50, 200],
      [600, 200, 300],
      [1000, 300, 1000],
    ];
    for (const [x, y, z] of sizes) {
      const cp = computeCameraPlacement({ x, y, z });
      const halfDiag = Math.sqrt((x / 2) ** 2 + (y / 2) ** 2 + (z / 2) ** 2);
      const camDist = Math.hypot(...cp.position);
      const visibleHalfSize = camDist * Math.sin((cp.fov / 2) * (Math.PI / 180));
      expect(visibleHalfSize).toBeGreaterThan(halfDiag);
    }
  });

  it("custom fovDeg + safetyFactor впливають на camDist", () => {
    const narrow = computeCameraPlacement(
      { x: 200, y: 200, z: 200 },
      { fovDeg: 20, safetyFactor: 1.0 },
    );
    const wide = computeCameraPlacement(
      { x: 200, y: 200, z: 200 },
      { fovDeg: 60, safetyFactor: 1.0 },
    );
    // Вужчий fov → більша відстань для тієї ж frustum.
    expect(narrow.position[0]).toBeGreaterThan(wide.position[0]);
  });

  it("custom angle нормалізовано множиться на camDist", () => {
    const cp = computeCameraPlacement({ x: 100, y: 100, z: 100 }, { angle: [1, 0, 0] });
    expect(cp.position[1]).toBeCloseTo(0, 5);
    expect(cp.position[2]).toBeCloseTo(0, 5);
    expect(cp.position[0]).toBeGreaterThan(0);
  });

  it("zero-dim сторона не падає (clamp на 1мм)", () => {
    const cp = computeCameraPlacement({ x: 0, y: 0, z: 0 });
    expect(cp.position[0]).toBeGreaterThan(0);
    expect(Number.isFinite(cp.position[0])).toBe(true);
  });
});
