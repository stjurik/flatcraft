import { describe, expect, it } from "vitest";

import {
  ENCLOSED_SHELF_DEFAULT_PARAMETERS,
  EnclosedShelfParametersSchema,
  EnclosedShelfSidePerforationSchema,
  EnclosedShelfStiffeningRibSchema,
} from "./enclosed-shelf.js";

describe("EnclosedShelfParametersSchema (Phase 3.0 PR 7)", () => {
  it("приймає DEFAULT-параметри (sanity)", () => {
    const parsed = EnclosedShelfParametersSchema.safeParse(ENCLOSED_SHELF_DEFAULT_PARAMETERS);
    expect(parsed.success).toBe(true);
  });

  it("DEFAULT: side_perforation=null, stiffening_rib=null (мінімальна форма)", () => {
    expect(ENCLOSED_SHELF_DEFAULT_PARAMETERS.side_perforation).toBeNull();
    expect(ENCLOSED_SHELF_DEFAULT_PARAMETERS.stiffening_rib).toBeNull();
  });

  it("DEFAULT: 4 bends, всі 'up' (enclosed-форма)", () => {
    expect(ENCLOSED_SHELF_DEFAULT_PARAMETERS.bends).toHaveLength(4);
    for (const b of ENCLOSED_SHELF_DEFAULT_PARAMETERS.bends) {
      expect(b.direction).toBe("up");
    }
  });

  it("приймає мінімальний розмір (300×100)", () => {
    const parsed = EnclosedShelfParametersSchema.safeParse({
      ...ENCLOSED_SHELF_DEFAULT_PARAMETERS,
      width_mm: 300,
      depth_mm: 100,
    });
    expect(parsed.success).toBe(true);
  });

  it("приймає максимальний розмір (1000×300)", () => {
    const parsed = EnclosedShelfParametersSchema.safeParse({
      ...ENCLOSED_SHELF_DEFAULT_PARAMETERS,
      width_mm: 1000,
      depth_mm: 300,
    });
    expect(parsed.success).toBe(true);
  });

  it("відхиляє width_mm < 300", () => {
    const parsed = EnclosedShelfParametersSchema.safeParse({
      ...ENCLOSED_SHELF_DEFAULT_PARAMETERS,
      width_mm: 250,
    });
    expect(parsed.success).toBe(false);
  });

  it("відхиляє depth_mm > 300", () => {
    const parsed = EnclosedShelfParametersSchema.safeParse({
      ...ENCLOSED_SHELF_DEFAULT_PARAMETERS,
      depth_mm: 350,
    });
    expect(parsed.success).toBe(false);
  });

  it("відхиляє bend_radius_mm не з allowed set", () => {
    const parsed = EnclosedShelfParametersSchema.safeParse({
      ...ENCLOSED_SHELF_DEFAULT_PARAMETERS,
      bend_radius_mm: 3,
    });
    expect(parsed.success).toBe(false);
  });

  it("приймає опційний side_perforation", () => {
    const parsed = EnclosedShelfParametersSchema.safeParse({
      ...ENCLOSED_SHELF_DEFAULT_PARAMETERS,
      side_perforation: {
        hole_size_mm: 8,
        pitch_x_mm: 30,
        pitch_y_mm: 30,
        margin_mm: 15,
      },
    });
    expect(parsed.success).toBe(true);
  });

  it("приймає опційний stiffening_rib (5-й сегмент)", () => {
    const parsed = EnclosedShelfParametersSchema.safeParse({
      ...ENCLOSED_SHELF_DEFAULT_PARAMETERS,
      stiffening_rib: { height_mm: 15 },
    });
    expect(parsed.success).toBe(true);
  });

  it("приймає 3-bend варіант (без rib): bends.length === 3", () => {
    const parsed = EnclosedShelfParametersSchema.safeParse({
      ...ENCLOSED_SHELF_DEFAULT_PARAMETERS,
      bends: [{ direction: "up" }, { direction: "up" }, { direction: "up" }],
    });
    expect(parsed.success).toBe(true);
  });

  it("відхиляє bends.length < 3", () => {
    const parsed = EnclosedShelfParametersSchema.safeParse({
      ...ENCLOSED_SHELF_DEFAULT_PARAMETERS,
      bends: [{ direction: "up" }, { direction: "up" }],
    });
    expect(parsed.success).toBe(false);
  });
});

describe("EnclosedShelfSidePerforationSchema", () => {
  it("приймає валідну сітку", () => {
    expect(
      EnclosedShelfSidePerforationSchema.safeParse({
        hole_size_mm: 8,
        pitch_x_mm: 30,
        pitch_y_mm: 30,
        margin_mm: 15,
      }).success,
    ).toBe(true);
  });

  it("відхиляє hole_size_mm > 20", () => {
    expect(
      EnclosedShelfSidePerforationSchema.safeParse({
        hole_size_mm: 25,
        pitch_x_mm: 30,
        pitch_y_mm: 30,
        margin_mm: 15,
      }).success,
    ).toBe(false);
  });
});

describe("EnclosedShelfStiffeningRibSchema", () => {
  it("приймає height_mm у діапазоні [5, 50]", () => {
    expect(EnclosedShelfStiffeningRibSchema.safeParse({ height_mm: 10 }).success).toBe(true);
    expect(EnclosedShelfStiffeningRibSchema.safeParse({ height_mm: 5 }).success).toBe(true);
    expect(EnclosedShelfStiffeningRibSchema.safeParse({ height_mm: 50 }).success).toBe(true);
  });

  it("відхиляє height_mm < 5", () => {
    expect(EnclosedShelfStiffeningRibSchema.safeParse({ height_mm: 3 }).success).toBe(false);
  });
});
