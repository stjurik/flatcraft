import { describe, expect, it } from "vitest";

import { computeKFactor } from "./k-factor.js";
import { loadSpecFromFile } from "./spec.js";

const spec = await loadSpecFromFile();

describe("computeKFactor", () => {
  it("cold_rolled_steel t=2, R=2 → ratio=1.0, multiplier=1.0, K=0.40", () => {
    const k = computeKFactor(
      { materialCode: "cold_rolled_steel", thicknessMm: 2, innerRadiusMm: 2 },
      spec,
    );
    expect(k).toBeCloseTo(0.4, 5);
  });

  it("cold_rolled_steel t=2, R=1 → ratio=0.5, multiplier=0.85", () => {
    const k = computeKFactor(
      { materialCode: "cold_rolled_steel", thicknessMm: 2, innerRadiusMm: 1 },
      spec,
    );
    expect(k).toBeCloseTo(0.4 * 0.85, 5);
  });

  it("aluminum_5754 t=2, R=10 → ratio=5, multiplier=1.10", () => {
    const k = computeKFactor(
      { materialCode: "aluminum_5754", thicknessMm: 2, innerRadiusMm: 10 },
      spec,
    );
    expect(k).toBeCloseTo(0.33 * 1.1, 5);
  });

  it("stainless_304 t=1, R=2.5 → ratio=2.5, multiplier=1.0", () => {
    const k = computeKFactor(
      { materialCode: "stainless_304", thicknessMm: 1, innerRadiusMm: 2.5 },
      spec,
    );
    expect(k).toBeCloseTo(0.45, 5);
  });

  it("кидає на невідомому матеріалі", () => {
    expect(() =>
      computeKFactor({ materialCode: "unobtanium", thicknessMm: 2, innerRadiusMm: 2 }, spec),
    ).toThrowError(/material/i);
  });

  it("кидає на нульовій або від'ємній товщині (ділення на 0)", () => {
    expect(() =>
      computeKFactor({ materialCode: "cold_rolled_steel", thicknessMm: 0, innerRadiusMm: 2 }, spec),
    ).toThrow();
  });

  it("кидає на ratio поза будь-яким діапазоном (>=999)", () => {
    expect(() =>
      computeKFactor(
        { materialCode: "cold_rolled_steel", thicknessMm: 1, innerRadiusMm: 1000 },
        spec,
      ),
    ).toThrowError(/ratio/i);
  });

  it("межа діапазону: ratio=1.0 → multiplier=1.0 (inclusive lower)", () => {
    const k = computeKFactor(
      { materialCode: "cold_rolled_steel", thicknessMm: 2, innerRadiusMm: 2 },
      spec,
    );
    // Якщо це попало у [0, 1), результат був би 0.4*0.85=0.34 — перевіряємо що ні.
    expect(k).toBeGreaterThan(0.34);
  });
});
