import type { LBracketParameters, WallShelfParameters, ZBracketParameters } from "@flatcraft/types";
import { describe, expect, it } from "vitest";

import {
  buildLBracketShapeCommands,
  buildWallShelfShapeCommands,
  buildZBracketShapeCommands,
  type ShapeCommand,
} from "./geometry.js";

const baseParams: LBracketParameters = {
  legA_mm: 60,
  legB_mm: 60,
  bend_radius_mm: 2.5,
  bend_angle_deg: 90,
  bend_direction: "down",
  width_mm: 100,
  holes: [],
};

describe("buildLBracketShapeCommands", () => {
  it("повертає 8 команд: moveTo + 5 ліній + arc + closePath", () => {
    const commands = buildLBracketShapeCommands({
      parameters: baseParams,
      thicknessMm: 2,
    });
    expect(commands).toHaveLength(8);
    expect(commands[0]?.kind).toBe("moveTo");
    expect(commands[commands.length - 1]?.kind).toBe("closePath");
    const arcs = commands.filter(
      (c): c is Extract<ShapeCommand, { kind: "absarc" }> => c.kind === "absarc",
    );
    expect(arcs).toHaveLength(1);
  });

  it("вершини відповідають CadQuery-профілю (legA=60, legB=60, t=2, r=2.5)", () => {
    const commands = buildLBracketShapeCommands({
      parameters: baseParams,
      thicknessMm: 2,
    });
    expect(commands[0]).toEqual({ kind: "moveTo", x: 0, y: 0 });
    expect(commands[1]).toEqual({ kind: "lineTo", x: 60, y: 0 });
    expect(commands[2]).toEqual({ kind: "lineTo", x: 60, y: 2 });
    expect(commands[3]).toEqual({ kind: "lineTo", x: 4.5, y: 2 });
    expect(commands[4]).toEqual({
      kind: "absarc",
      cx: 4.5,
      cy: 4.5,
      radius: 2.5,
      startAngleRad: -Math.PI / 2,
      endAngleRad: Math.PI,
      clockwise: true,
    });
    expect(commands[5]).toEqual({ kind: "lineTo", x: 2, y: 60 });
    expect(commands[6]).toEqual({ kind: "lineTo", x: 0, y: 60 });
  });

  it("асиметричні полиці змінюють відповідні координати", () => {
    const commands = buildLBracketShapeCommands({
      parameters: { ...baseParams, legA_mm: 40, legB_mm: 80 },
      thicknessMm: 1.5,
    });
    // Кінець полиці B = legB_mm
    expect(commands[1]).toEqual({ kind: "lineTo", x: 80, y: 0 });
    // Верхня точка полиці A = legA_mm
    expect(commands[6]).toEqual({ kind: "lineTo", x: 0, y: 40 });
  });

  it("кидає на нульовій або від'ємній товщині", () => {
    expect(() => buildLBracketShapeCommands({ parameters: baseParams, thicknessMm: 0 })).toThrow(
      /thicknessMm/,
    );
    expect(() => buildLBracketShapeCommands({ parameters: baseParams, thicknessMm: -1 })).toThrow(
      /thicknessMm/,
    );
  });

  it("кидає, якщо leg < thickness + radius (профіль invalid)", () => {
    // legA=5, t=8, R=5 → t+R=13 > 5: throws.
    expect(() =>
      buildLBracketShapeCommands({
        parameters: { ...baseParams, legA_mm: 5, bend_radius_mm: 5 },
        thicknessMm: 8,
      }),
    ).toThrow(/legA_mm/);
    expect(() =>
      buildLBracketShapeCommands({
        parameters: { ...baseParams, legB_mm: 5, bend_radius_mm: 5 },
        thicknessMm: 8,
      }),
    ).toThrow(/legB_mm/);
  });
});

// ─── Z-bracket ─────────────────────────────────────────────────────────────

const baseZ: ZBracketParameters = {
  bottom_flange_mm: 60,
  top_flange_mm: 60,
  offset_mm: 40,
  bend_radius_mm: 2.5,
  bend_angle_deg: 90,
  bends: [{ direction: "down" }, { direction: "down" }],
  width_mm: 100,
  holes: [],
};

describe("buildZBracketShapeCommands", () => {
  it("повертає 11 команд (moveTo + 7 lineTo + 2 absarc + closePath) — 2 inner bends", () => {
    const cmds = buildZBracketShapeCommands({ parameters: baseZ, thicknessMm: 2 });
    expect(cmds).toHaveLength(11);
    expect(cmds[0]?.kind).toBe("moveTo");
    expect(cmds[cmds.length - 1]?.kind).toBe("closePath");
    const arcs = cmds.filter(
      (c): c is Extract<ShapeCommand, { kind: "absarc" }> => c.kind === "absarc",
    );
    expect(arcs).toHaveLength(2);
  });

  it("start у (0,0), bottom edge до (bf, 0)", () => {
    const cmds = buildZBracketShapeCommands({ parameters: baseZ, thicknessMm: 2 });
    expect(cmds[0]).toEqual({ kind: "moveTo", x: 0, y: 0 });
    expect(cmds[1]).toEqual({ kind: "lineTo", x: 60, y: 0 });
  });

  it("bend 2 (between middle і top): inner concave корнер у (bf, off)", () => {
    const cmds = buildZBracketShapeCommands({ parameters: baseZ, thicknessMm: 2 });
    // bend 2: approach (bf, off-r) → arc center (bf+r, off-r) → (bf+r, off)
    const arc2 = cmds.find(
      (c): c is Extract<ShapeCommand, { kind: "absarc" }> =>
        c.kind === "absarc" && c.cx === 60 + 2.5,
    );
    expect(arc2).toBeDefined();
    expect(arc2).toMatchObject({
      cx: 62.5,
      cy: 40 - 2.5,
      radius: 2.5,
      startAngleRad: Math.PI,
      endAngleRad: Math.PI / 2,
      clockwise: true,
    });
  });

  it("bend 1 (between middle і bottom): inner concave корнер у (bf-t, t)", () => {
    const cmds = buildZBracketShapeCommands({ parameters: baseZ, thicknessMm: 2 });
    // bend 1: center (bf-t-r, t+r)
    const arc1 = cmds.find(
      (c): c is Extract<ShapeCommand, { kind: "absarc" }> =>
        c.kind === "absarc" && c.cx === 60 - 2 - 2.5,
    );
    expect(arc1).toBeDefined();
    expect(arc1).toMatchObject({
      cx: 55.5,
      cy: 2 + 2.5,
      radius: 2.5,
      startAngleRad: 0,
      endAngleRad: -Math.PI / 2,
      clockwise: true,
    });
  });

  it("асиметричний top_flange зміщує координати top-right", () => {
    const cmds = buildZBracketShapeCommands({
      parameters: { ...baseZ, top_flange_mm: 100 },
      thicknessMm: 2,
    });
    // top-right corner у (bf - t + tf, off+t) = (60-2+100, 42) = (158, 42)
    const found = cmds.some((c) => c.kind === "lineTo" && c.x === 158 && c.y === 42);
    expect(found).toBe(true);
  });

  it("кидає при тонкому offset (off ≤ r)", () => {
    expect(() =>
      buildZBracketShapeCommands({
        parameters: { ...baseZ, offset_mm: 2, bend_radius_mm: 4 },
        thicknessMm: 2,
      }),
    ).toThrow(/offset/);
  });

  it("кидає при недостатньому top_flange (tf ≤ t+r)", () => {
    // tf=4, t=2, r=4: tf=4 ≤ t+r=6 → throws.
    expect(() =>
      buildZBracketShapeCommands({
        parameters: { ...baseZ, top_flange_mm: 4, bend_radius_mm: 4 },
        thicknessMm: 2,
      }),
    ).toThrow(/top_flange/);
  });
});

// ─── Wall shelf ────────────────────────────────────────────────────────────

const baseShelf: WallShelfParameters = {
  back_height_mm: 80,
  shelf_depth_mm: 150,
  front_lip_mm: 20,
  bend_radius_mm: 2.5,
  bend_angle_deg: 90,
  bends: [{ direction: "down" }, { direction: "down" }],
  width_mm: 300,
  mount_hole_diameter_mm: 6,
  mount_hole_rows: 2,
  mount_hole_cols: 2,
  mount_hole_margin_mm: 15,
};

describe("buildWallShelfShapeCommands", () => {
  it("з front_lip>0: 2 inner bends, 10 команд", () => {
    const cmds = buildWallShelfShapeCommands({ parameters: baseShelf, thicknessMm: 2 });
    const arcs = cmds.filter(
      (c): c is Extract<ShapeCommand, { kind: "absarc" }> => c.kind === "absarc",
    );
    expect(arcs).toHaveLength(2);
    expect(cmds[0]?.kind).toBe("moveTo");
    expect(cmds[cmds.length - 1]?.kind).toBe("closePath");
  });

  it("з front_lip=0: лише 1 inner bend (L-shape вироджена)", () => {
    const cmds = buildWallShelfShapeCommands({
      parameters: { ...baseShelf, front_lip_mm: 0 },
      thicknessMm: 2,
    });
    const arcs = cmds.filter(
      (c): c is Extract<ShapeCommand, { kind: "absarc" }> => c.kind === "absarc",
    );
    expect(arcs).toHaveLength(1);
  });

  it("bend back-shelf: inner корнер у (t, t)", () => {
    const cmds = buildWallShelfShapeCommands({ parameters: baseShelf, thicknessMm: 2 });
    const arcBack = cmds.find(
      (c): c is Extract<ShapeCommand, { kind: "absarc" }> =>
        c.kind === "absarc" && c.cx === 2 + 2.5 && c.cy === 2 + 2.5,
    );
    expect(arcBack).toMatchObject({
      cx: 4.5,
      cy: 4.5,
      radius: 2.5,
      startAngleRad: -Math.PI / 2,
      endAngleRad: Math.PI,
      clockwise: true,
    });
  });

  it("bend shelf-lip: inner корнер у (sd-t, t)", () => {
    const cmds = buildWallShelfShapeCommands({ parameters: baseShelf, thicknessMm: 2 });
    const arcLip = cmds.find(
      (c): c is Extract<ShapeCommand, { kind: "absarc" }> =>
        c.kind === "absarc" && c.cx === 150 - 2 - 2.5,
    );
    expect(arcLip).toMatchObject({
      cx: 145.5,
      cy: 4.5,
      radius: 2.5,
      startAngleRad: 0,
      endAngleRad: -Math.PI / 2,
      clockwise: true,
    });
  });

  it("кидає коли shelf_depth ≤ 2(t+r) — bends перекриваються", () => {
    expect(() =>
      buildWallShelfShapeCommands({
        parameters: { ...baseShelf, shelf_depth_mm: 10, bend_radius_mm: 4 },
        thicknessMm: 4,
      }),
    ).toThrow(/shelf_depth/);
  });

  it("кидає коли back_height ≤ t+r", () => {
    expect(() =>
      buildWallShelfShapeCommands({
        parameters: { ...baseShelf, back_height_mm: 5, bend_radius_mm: 5 },
        thicknessMm: 5,
      }),
    ).toThrow(/back_height/);
  });
});
