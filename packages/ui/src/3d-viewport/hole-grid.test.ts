/**
 * Тести computeHoleGrid — preview-grid отворів перфо-виробів.
 *
 * Головний регрес: раніше при `total > cap` сцена рендерила НУЛЬ отворів →
 * панель виглядала суцільною (баг: ширина 579.5→580 «гасила» перфорацію).
 * Тепер grid граційно проріджується, але cells ніколи не порожніє.
 */
import { describe, expect, it } from "vitest";

import { computeHoleGrid, DEFAULT_MAX_HOLES_PREVIEW } from "./hole-grid.js";

const BASE = { pitchXMm: 25, pitchYMm: 25, marginMm: 15 } as const;

describe("computeHoleGrid — count math", () => {
  it("рахує centered grid: floor((dim−2m)/pitch)+1 по кожній осі", () => {
    const g = computeHoleGrid({ lengthMm: 200, widthMm: 150, ...BASE });
    // 200−30=170 → floor(170/25)+1 = 7; 150−30=120 → floor(120/25)+1 = 5.
    expect(g.nCols).toBe(7);
    expect(g.nRows).toBe(5);
    expect(g.total).toBe(35);
    expect(g.cells).toHaveLength(35);
    expect(g.decimated).toBe(false);
  });

  it("grid центрований навколо 0: межі симетричні", () => {
    const g = computeHoleGrid({ lengthMm: 200, widthMm: 150, ...BASE });
    const us = g.cells.map((c) => c.u);
    const vs = g.cells.map((c) => c.v);
    expect(Math.min(...us)).toBeCloseTo(-Math.max(...us));
    expect(Math.min(...vs)).toBeCloseTo(-Math.max(...vs));
  });
});

describe("computeHoleGrid — регрес 579.5→580 (отвори не зникають)", () => {
  it("579.5×579.5 показує повний grid (без децимації)", () => {
    const g = computeHoleGrid({ lengthMm: 579.5, widthMm: 579.5, ...BASE });
    // 549.5/25 → 21+1 = 22 по обох осях = 484 отвори.
    expect(g.total).toBe(484);
    expect(g.cells.length).toBe(484);
    expect(g.decimated).toBe(false);
  });

  it("579.5×580 — раніше total=506>500 гасив усе; тепер показуються всі 506", () => {
    const g = computeHoleGrid({ lengthMm: 579.5, widthMm: 580, ...BASE });
    expect(g.total).toBe(506); // 22 × 23
    // Ключове: cells НЕ порожні (раніше тут було 0 → суцільна плита).
    expect(g.cells.length).toBeGreaterThan(0);
    // 506 < 8000 → показуються всі, без проріджування.
    expect(g.cells.length).toBe(506);
    expect(g.decimated).toBe(false);
  });
});

describe("computeHoleGrid — децимація гігантських grid'ів", () => {
  it("понад ліміт → проріджує, але cells ≤ maxHoles і > 0", () => {
    // 3000×3000, pitch 10, margin 5 → ~300×300 = 90000 отворів.
    const g = computeHoleGrid({
      lengthMm: 3000,
      widthMm: 3000,
      pitchXMm: 10,
      pitchYMm: 10,
      marginMm: 5,
    });
    expect(g.total).toBeGreaterThan(DEFAULT_MAX_HOLES_PREVIEW);
    expect(g.decimated).toBe(true);
    expect(g.cells.length).toBeGreaterThan(0);
    expect(g.cells.length).toBeLessThanOrEqual(DEFAULT_MAX_HOLES_PREVIEW);
  });

  it("кастомний maxHoles теж дотримується (enclosed_shelf: /2 на дві боковини)", () => {
    const g = computeHoleGrid({
      lengthMm: 1000,
      widthMm: 1000,
      pitchXMm: 10,
      pitchYMm: 10,
      marginMm: 5,
      maxHoles: 100,
    });
    expect(g.cells.length).toBeLessThanOrEqual(100);
    expect(g.cells.length).toBeGreaterThan(0);
  });
});
