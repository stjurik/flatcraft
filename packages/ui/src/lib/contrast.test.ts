import { describe, it, expect } from "vitest";

import { contrastRatio } from "./contrast.js";

describe("contrastRatio", () => {
  it("white vs black ≈ 21 (max possible)", () => {
    expect(contrastRatio("#ffffff", "#000000")).toBeCloseTo(21, 1);
  });

  it("is symmetric (order-independent)", () => {
    expect(contrastRatio("#000000", "#ffffff")).toBeCloseTo(21, 1);
  });

  it("identical colors = 1", () => {
    expect(contrastRatio("#7f7f7f", "#7f7f7f")).toBeCloseTo(1, 2);
  });

  it("accepts 3-digit hex", () => {
    expect(contrastRatio("#fff", "#000")).toBeCloseTo(21, 1);
  });

  it("parses oklch(L C H) for pure black/white", () => {
    expect(contrastRatio("oklch(1 0 0)", "oklch(0 0 0)")).toBeCloseTo(21, 1);
  });

  it("known WCAG pair: #767676 on white ≈ 4.54", () => {
    expect(contrastRatio("#767676", "#ffffff")).toBeCloseTo(4.54, 1);
  });

  it("warm-charcoal text on warm off-white bg passes AA body (≥4.5)", () => {
    const ratio = contrastRatio("oklch(0.22 0.015 50)", "oklch(0.985 0.005 80)");
    expect(ratio).toBeGreaterThan(4.5);
  });

  it("ember primary vs white passes AA large (≥3)", () => {
    const ratio = contrastRatio("oklch(1 0 0)", "oklch(0.66 0.17 50)");
    expect(ratio).toBeGreaterThan(3);
  });

  it("throws on unsupported format", () => {
    expect(() => contrastRatio("rgb(0,0,0)", "#fff")).toThrow();
    expect(() => contrastRatio("#fff", "hsl(0 0% 0%)")).toThrow();
  });

  it("hex and oklch agree on equivalent white/black", () => {
    const hex = contrastRatio("#ffffff", "#000000");
    const oklch = contrastRatio("oklch(1 0 0)", "oklch(0 0 0)");
    expect(Math.abs(hex - oklch)).toBeLessThan(0.05);
  });
});
