import { LBracketParametersSchema } from "@flatcraft/types";
import { describe, expect, it } from "vitest";

import { zodIssuesToFieldErrors } from "./zod-errors.js";

describe("zodIssuesToFieldErrors", () => {
  it("порожній масив issues → порожній record", () => {
    expect(zodIssuesToFieldErrors([])).toEqual({});
  });

  it("один issue на top-level полі → { name: [msg] }", () => {
    const result = LBracketParametersSchema.safeParse({
      legA_mm: 10,
      legB_mm: 60,
      bend_radius_mm: 2.5,
      bend_angle_deg: 90,
      width_mm: 100,
      holes: [],
    });
    expect(result.success).toBe(false);
    if (!result.success) {
      const errors = zodIssuesToFieldErrors(result.error.issues);
      expect(Object.keys(errors)).toEqual(["legA_mm"]);
      expect(errors["legA_mm"]?.length).toBe(1);
    }
  });

  it("декілька issues на різних полях групуються окремо", () => {
    const result = LBracketParametersSchema.safeParse({
      legA_mm: 10,
      legB_mm: 600,
      bend_radius_mm: 3,
      bend_angle_deg: 90,
      width_mm: 100,
      holes: [],
    });
    expect(result.success).toBe(false);
    if (!result.success) {
      const errors = zodIssuesToFieldErrors(result.error.issues);
      expect(Object.keys(errors).sort()).toEqual(["bend_radius_mm", "legA_mm", "legB_mm"]);
    }
  });

  it("nested path (holes[0].leg) групується під top-level 'holes'", () => {
    const result = LBracketParametersSchema.safeParse({
      legA_mm: 60,
      legB_mm: 60,
      bend_radius_mm: 2.5,
      bend_angle_deg: 90,
      width_mm: 100,
      holes: [
        // невалідний leg → issue.path = ["holes", 0, "leg"]
        { leg: "C", distance_from_edge_mm: 10, distance_from_bend_mm: 10, diameter_mm: 5 },
      ],
    });
    expect(result.success).toBe(false);
    if (!result.success) {
      const errors = zodIssuesToFieldErrors(result.error.issues);
      expect(errors["holes"]).toBeDefined();
      expect(errors["holes"]?.length).toBeGreaterThanOrEqual(1);
    }
  });

  it("issue з порожнім path (form-level) пропускається", () => {
    // Сінтезований issue — Zod зазвичай завжди ставить path для shape-схем.
    const errors = zodIssuesToFieldErrors([
      {
        code: "custom",
        path: [],
        message: "form-level",
      } as never,
    ]);
    expect(errors).toEqual({});
  });

  it("декілька issues на одному полі зберігаються у порядку появи", () => {
    const errors = zodIssuesToFieldErrors([
      { code: "too_small", path: ["x"], message: "min" } as never,
      { code: "too_big", path: ["x"], message: "max" } as never,
    ]);
    expect(errors["x"]).toEqual(["min", "max"]);
  });
});
