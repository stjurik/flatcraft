import { describe, expect, it } from "vitest";

import {
  holeShapeFromSlug,
  holeSizeFieldFor,
  initialPerforationParams,
  normalizeVisibleFields,
  schemaForHoleShape,
  slugForHoleShape,
  syncHoleKeys,
  type PerforationParameters,
} from "./perforation-shape";

const BASE: PerforationParameters = {
  length_mm: 200,
  width_mm: 150,
  hole_diameter_mm: 8,
  hole_size_mm: 8,
  pitch_x_mm: 25,
  pitch_y_mm: 25,
  margin_mm: 15,
  // ADR-030: квадратна форма тепер ребриста монтажна панель — її поля присутні
  // у спільному стані (для круглої форми відкидаються при safeParse/export).
  rib_height_mm: 30,
  bend_radius_mm: 2.5,
  bend_angle_deg: 90,
};

describe("slug ↔ holeShape mapping", () => {
  it("slugForHoleShape", () => {
    expect(slugForHoleShape("circle")).toBe("perforated_panel");
    expect(slugForHoleShape("square")).toBe("perforated_panel_square");
  });
  it("holeShapeFromSlug", () => {
    expect(holeShapeFromSlug("perforated_panel")).toBe("circle");
    expect(holeShapeFromSlug("perforated_panel_square")).toBe("square");
    expect(holeShapeFromSlug("anything_else")).toBe("circle");
  });
  it("holeSizeFieldFor", () => {
    expect(holeSizeFieldFor("circle")).toBe("hole_diameter_mm");
    expect(holeSizeFieldFor("square")).toBe("hole_size_mm");
  });
  it("schemaForHoleShape parses the matching key", () => {
    expect(schemaForHoleShape("circle").safeParse(BASE).success).toBe(true);
    expect(schemaForHoleShape("square").safeParse(BASE).success).toBe(true);
  });
});

describe("syncHoleKeys", () => {
  it("circle: дзеркалить hole_diameter_mm → hole_size_mm", () => {
    const out = syncHoleKeys({ ...BASE, hole_diameter_mm: 12, hole_size_mm: 8 }, "circle");
    expect(out.hole_diameter_mm).toBe(12);
    expect(out.hole_size_mm).toBe(12);
  });
  it("square: дзеркалить hole_size_mm → hole_diameter_mm", () => {
    const out = syncHoleKeys({ ...BASE, hole_diameter_mm: 8, hole_size_mm: 20 }, "square");
    expect(out.hole_diameter_mm).toBe(20);
    expect(out.hole_size_mm).toBe(20);
  });
  it("не чіпає спільні поля", () => {
    const out = syncHoleKeys({ ...BASE, pitch_x_mm: 40, margin_mm: 30 }, "circle");
    expect(out.pitch_x_mm).toBe(40);
    expect(out.margin_mm).toBe(30);
  });
});

describe("initialPerforationParams", () => {
  it("circle route: обидва ключі = діаметр з base", () => {
    const p = initialPerforationParams("circle", { hole_diameter_mm: 6, pitch_x_mm: 20 });
    expect(p.hole_diameter_mm).toBe(6);
    expect(p.hole_size_mm).toBe(6);
    expect(p.pitch_x_mm).toBe(20);
  });
  it("square route: обидва ключі = сторона з base", () => {
    const p = initialPerforationParams("square", { hole_size_mm: 10 });
    expect(p.hole_diameter_mm).toBe(10);
    expect(p.hole_size_mm).toBe(10);
  });
  it("завжди має повний набір полів", () => {
    const p = initialPerforationParams("circle", {});
    expect(p).toMatchObject({
      length_mm: expect.any(Number),
      width_mm: expect.any(Number),
      pitch_x_mm: expect.any(Number),
      pitch_y_mm: expect.any(Number),
      margin_mm: expect.any(Number),
      hole_diameter_mm: expect.any(Number),
      hole_size_mm: expect.any(Number),
    });
  });
});

describe("normalizeVisibleFields", () => {
  it("мапить ключ розміру на активний (square список → circle форма)", () => {
    const out = normalizeVisibleFields(["length_mm", "hole_size_mm", "pitch_x_mm"], "circle");
    expect(out).toContain("hole_diameter_mm");
    expect(out).not.toContain("hole_size_mm");
    expect(out).toContain("length_mm");
  });
  it("undefined лишається undefined (part-mode — усі поля)", () => {
    expect(normalizeVisibleFields(undefined, "circle")).toBeUndefined();
  });
  it("дедуплікує, якщо вже містить активний ключ", () => {
    const out = normalizeVisibleFields(["hole_diameter_mm", "hole_size_mm"], "circle");
    expect(out).toEqual(["hole_diameter_mm"]);
  });
});
