import type { LBracketParameters } from "@flatcraft/types";
import { describe, expect, it } from "vitest";

import { buildLBracketShapeCommands, type ShapeCommand } from "./geometry.js";

const baseParams: LBracketParameters = {
  legA_mm: 60,
  legB_mm: 60,
  bend_radius_mm: 2.5,
  bend_angle_deg: 90,
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
