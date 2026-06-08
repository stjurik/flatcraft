/**
 * Hotfix 2.9.c (ADR-022): export-gate валідатор має працювати у браузері —
 * без `node:fs`, лише на `bakedSpec`. Browser-safety (відсутність node:* у
 * графі) перевіряється статичним скануванням у `generated/baked-spec.test.ts`;
 * тут — функціональна перевірка, що клієнт ловить ті самі помилки, що й сервер.
 */
import { L_BRACKET_DEFAULT_PARAMETERS, type ExportRequest } from "@flatcraft/types";
import { describe, expect, it } from "vitest";

import { bakedSpec } from "../generated/baked-spec.js";
import { validateExportBends } from "./export-gate.js";

function lBracket(overrides: {
  thickness_mm: number;
  material_code?: string;
  bend_radius_mm?: 1 | 2.5 | 4 | 5;
}): ExportRequest {
  return {
    template_slug: "l_bracket",
    parameters: {
      ...L_BRACKET_DEFAULT_PARAMETERS,
      ...(overrides.bend_radius_mm !== undefined
        ? { bend_radius_mm: overrides.bend_radius_mm }
        : {}),
    },
    material_code: overrides.material_code ?? "cold_rolled_steel",
    thickness_mm: overrides.thickness_mm,
  };
}

describe("validateExportBends (browser, bakedSpec)", () => {
  it("t=5 / R=2.5 cold_rolled_steel → RADIUS_NOT_ALLOWED, allowed [4, 5]", () => {
    const issues = validateExportBends(
      lBracket({ thickness_mm: 5, bend_radius_mm: 2.5 }),
      bakedSpec,
    );
    expect(issues).toHaveLength(1);
    expect(issues[0]?.code).toBe("RADIUS_NOT_ALLOWED");
    expect(issues[0]?.field).toBe("bend_radius_mm");
    expect(issues[0]?.allowed).toEqual([4, 5]);
    expect(issues[0]?.thickness).toBe(5);
    expect(issues[0]?.message).toMatch(/Збільшіть радіус/);
  });

  it("t=5 / R=4 cold_rolled_steel → валідно (порожній список)", () => {
    const issues = validateExportBends(lBracket({ thickness_mm: 5, bend_radius_mm: 4 }), bakedSpec);
    expect(issues).toEqual([]);
  });

  it("невідома товщина → THICKNESS_NOT_SUPPORTED", () => {
    const issues = validateExportBends(lBracket({ thickness_mm: 7 }), bakedSpec);
    expect(issues[0]?.code).toBe("THICKNESS_NOT_SUPPORTED");
  });
});
