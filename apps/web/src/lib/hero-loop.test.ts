import { describe, expect, it } from "vitest";

import { nextDemoParams, HERO_LOOP_PERIOD_MS } from "./hero-loop.js";

describe("nextDemoParams — детермінований 16-секундний loop для hero demo", () => {
  it("t=0 → початкові значення фази 1 (legA=50)", () => {
    const p = nextDemoParams(0);
    expect(p.legA_mm).toBe(50);
    expect(p.legB_mm).toBe(50);
    expect(p.bend_radius_mm).toBe(2.5);
    expect(p.bend_angle_deg).toBe(90);
    expect(p.width_mm).toBe(100);
    expect(p.holes).toEqual([]);
  });

  it("t=2000 (середина фази 1) → legA=125 (50 + 0.5 × 150)", () => {
    expect(nextDemoParams(2000).legA_mm).toBeCloseTo(125, 6);
  });

  it("t=4000 (початок фази 2) → legA=200, legB ще 50", () => {
    const p = nextDemoParams(4000);
    expect(p.legA_mm).toBe(200);
    expect(p.legB_mm).toBe(50);
  });

  it("t=6000 (середина фази 2) → legB=125", () => {
    expect(nextDemoParams(6000).legB_mm).toBeCloseTo(125, 6);
  });

  it("t=8000 (початок фази 3) → bend_radius = RADII[0] = 1", () => {
    const p = nextDemoParams(8000);
    expect(p.legA_mm).toBe(200);
    expect(p.legB_mm).toBe(200);
    expect(p.bend_radius_mm).toBe(1);
  });

  it("t=10000 (фаза 3, 2с після старту) → bend_radius = RADII[2] = 4", () => {
    expect(nextDemoParams(10000).bend_radius_mm).toBe(4);
  });

  it("t=12000 (початок фази 4) → width=100, bend_radius=5 (фінал фази 3)", () => {
    const p = nextDemoParams(12000);
    expect(p.bend_radius_mm).toBe(5);
    expect(p.width_mm).toBe(100);
  });

  it("t=14000 (середина фази 4) → width=200", () => {
    expect(nextDemoParams(14000).width_mm).toBeCloseTo(200, 6);
  });

  it("t=16000 → loop, еквівалентно t=0", () => {
    expect(nextDemoParams(16000)).toEqual(nextDemoParams(0));
  });

  it("t=20000 → loop через mod, еквівалентно t=4000", () => {
    expect(nextDemoParams(20000)).toEqual(nextDemoParams(4000));
  });

  it("period константа = 16000мс", () => {
    expect(HERO_LOOP_PERIOD_MS).toBe(16000);
  });

  it("усі повернуті значення проходять LBracketParametersSchema", async () => {
    const { LBracketParametersSchema } = await import("@flatcraft/types");
    const samples = [0, 2000, 4000, 6000, 8000, 10000, 12000, 14000, 15999];
    for (const t of samples) {
      const result = LBracketParametersSchema.safeParse(nextDemoParams(t));
      expect(result.success, `failed at t=${t}: ${JSON.stringify(result)}`).toBe(true);
    }
  });
});
