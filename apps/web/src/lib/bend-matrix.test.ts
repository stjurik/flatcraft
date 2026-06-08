/**
 * Hotfix 2.9.c (ADR-022): клієнтська обгортка матричної валідації гибу.
 * Перевіряємо, що bend-matrix.ts ловить ту саму помилку, що й серверний gate,
 * на запеченому snapshot (browser-safe, без node:fs).
 */
import { L_BRACKET_DEFAULT_PARAMETERS, type ExportRequest } from "@flatcraft/types";
import { describe, expect, it } from "vitest";

import { bendMatrixIssues, firstMatrixMessage } from "./bend-matrix";

function lBracket(thickness_mm: number, bend_radius_mm: 1 | 2.5 | 4 | 5): ExportRequest {
  return {
    template_slug: "l_bracket",
    parameters: { ...L_BRACKET_DEFAULT_PARAMETERS, bend_radius_mm },
    material_code: "cold_rolled_steel",
    thickness_mm,
  };
}

describe("bendMatrixIssues", () => {
  it("t=5 / R=2.5 → RADIUS_NOT_ALLOWED з allowed [4, 5]", () => {
    const issues = bendMatrixIssues(lBracket(5, 2.5));
    expect(issues).toHaveLength(1);
    expect(issues[0]?.code).toBe("RADIUS_NOT_ALLOWED");
    expect(issues[0]?.allowed).toEqual([4, 5]);
  });

  it("t=5 / R=4 → валідно", () => {
    expect(bendMatrixIssues(lBracket(5, 4))).toEqual([]);
  });
});

describe("firstMatrixMessage", () => {
  it("повертає дружнє повідомлення першої помилки", () => {
    const msg = firstMatrixMessage(bendMatrixIssues(lBracket(5, 2.5)));
    expect(msg).toMatch(/радіус/i);
  });

  it("null коли помилок немає", () => {
    expect(firstMatrixMessage(bendMatrixIssues(lBracket(5, 4)))).toBeNull();
  });
});
