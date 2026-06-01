import { describe, expect, it } from "vitest";

import { viewportQuality } from "./viewport-quality.js";

describe("viewportQuality — адаптивна матриця для 3D-сцен (Phase 2.14)", () => {
  it("desktop (без mobile, без reduced) — повна якість", () => {
    const q = viewportQuality({ isMobile: false, reduced: false });
    expect(q).toEqual({
      dpr: [1, 2],
      enableZoom: true,
      enableRotate: true,
      debounceMs: 100,
      curveSegments: 12,
    });
  });

  it("mobile — knocks debounce + DPR cap + zoom OFF (avoid pinch conflict)", () => {
    const q = viewportQuality({ isMobile: true, reduced: false });
    expect(q.dpr).toEqual([1, 1.5]);
    expect(q.enableZoom).toBe(false);
    expect(q.enableRotate).toBe(true);
    expect(q.debounceMs).toBe(250);
    expect(q.curveSegments).toBe(8);
  });

  it("reduced-motion (desktop) — найжорсткіша економія + rotate OFF", () => {
    const q = viewportQuality({ isMobile: false, reduced: true });
    expect(q.dpr).toEqual([1, 1]);
    expect(q.enableZoom).toBe(false);
    expect(q.enableRotate).toBe(false);
    expect(q.debounceMs).toBe(400);
    expect(q.curveSegments).toBe(6);
  });

  it("mobile + reduced-motion — reduced має пріоритет (найнижчі значення)", () => {
    const q = viewportQuality({ isMobile: true, reduced: true });
    expect(q.dpr).toEqual([1, 1]);
    expect(q.enableRotate).toBe(false);
    expect(q.debounceMs).toBe(400);
    expect(q.curveSegments).toBe(6);
  });

  it("dpr — завжди tuple [lower, upper] з upper ≥ lower", () => {
    for (const isMobile of [false, true]) {
      for (const reduced of [false, true]) {
        const q = viewportQuality({ isMobile, reduced });
        expect(q.dpr[0]).toBeLessThanOrEqual(q.dpr[1]);
        expect(q.dpr[0]).toBeGreaterThan(0);
      }
    }
  });
});
