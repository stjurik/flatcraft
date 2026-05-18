import { describe, expect, it } from "vitest";

import { WALL_SHELF_DEFAULT_PARAMETERS, WallShelfParametersSchema } from "./wall-shelf.js";

describe("WallShelfParametersSchema", () => {
  it("приймає дефолтні параметри", () => {
    expect(() => WallShelfParametersSchema.parse(WALL_SHELF_DEFAULT_PARAMETERS)).not.toThrow();
  });

  it("дефолтні значення у межах spec", () => {
    expect(WALL_SHELF_DEFAULT_PARAMETERS.back_height_mm).toBeGreaterThanOrEqual(30);
    expect(WALL_SHELF_DEFAULT_PARAMETERS.shelf_depth_mm).toBeGreaterThanOrEqual(50);
    expect(WALL_SHELF_DEFAULT_PARAMETERS.front_lip_mm).toBe(20);
    expect(WALL_SHELF_DEFAULT_PARAMETERS.bend_angle_deg).toBe(90);
  });

  it("приймає front_lip_mm=0 (L-shape без lip)", () => {
    expect(() =>
      WallShelfParametersSchema.parse({ ...WALL_SHELF_DEFAULT_PARAMETERS, front_lip_mm: 0 }),
    ).not.toThrow();
  });

  it("відхиляє front_lip_mm у проміжку (0, 5) — або 0 або ≥5", () => {
    expect(() =>
      WallShelfParametersSchema.parse({ ...WALL_SHELF_DEFAULT_PARAMETERS, front_lip_mm: 3 }),
    ).toThrow();
  });

  it("відхиляє back_height < 30", () => {
    expect(() =>
      WallShelfParametersSchema.parse({ ...WALL_SHELF_DEFAULT_PARAMETERS, back_height_mm: 20 }),
    ).toThrow();
  });

  it("відхиляє shelf_depth > 500", () => {
    expect(() =>
      WallShelfParametersSchema.parse({ ...WALL_SHELF_DEFAULT_PARAMETERS, shelf_depth_mm: 600 }),
    ).toThrow();
  });

  it("відхиляє front_lip > 100", () => {
    expect(() =>
      WallShelfParametersSchema.parse({ ...WALL_SHELF_DEFAULT_PARAMETERS, front_lip_mm: 150 }),
    ).toThrow();
  });

  it("приймає тільки радіуси {1, 2.5, 4, 5}", () => {
    for (const r of [1, 2.5, 4, 5] as const) {
      expect(() =>
        WallShelfParametersSchema.parse({ ...WALL_SHELF_DEFAULT_PARAMETERS, bend_radius_mm: r }),
      ).not.toThrow();
    }
    expect(() =>
      WallShelfParametersSchema.parse({ ...WALL_SHELF_DEFAULT_PARAMETERS, bend_radius_mm: 3 }),
    ).toThrow();
  });

  it("mount_hole_cols > 5 відхиляє", () => {
    expect(() =>
      WallShelfParametersSchema.parse({ ...WALL_SHELF_DEFAULT_PARAMETERS, mount_hole_cols: 6 }),
    ).toThrow();
  });

  it("mount_hole_diameter < 3 відхиляє", () => {
    expect(() =>
      WallShelfParametersSchema.parse({
        ...WALL_SHELF_DEFAULT_PARAMETERS,
        mount_hole_diameter_mm: 2,
      }),
    ).toThrow();
  });
});
