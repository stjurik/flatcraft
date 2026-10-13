/**
 * Регресія issue #93: `HeroLoopDemo` рендерить `ExtrudeScene` (generic,
 * Run 7 Master Registry Track) замість видаленої L-bracket-специфічної
 * сцени — геометрія, камера, RAF-анімація, hover-пауза і reduced-motion
 * лишаються ідентичними, змінюється лише те, який компонент малює сцену.
 *
 * SSR (renderToStaticMarkup, web-suite без jsdom) — `@flatcraft/ui`
 * підмінено vi.mock, лишаючи справжній `buildLBracketShapeCommands`
 * (`@flatcraft/cad-engine/geometry`), щоб перевірити byte-equal команди.
 */
import { buildLBracketShapeCommands } from "@flatcraft/cad-engine/geometry";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

const calls = vi.hoisted(() => [] as Array<Record<string, unknown>>);

vi.mock("@flatcraft/ui", async () => {
  const geometry = await import("@flatcraft/cad-engine/geometry");
  return {
    Activity: () => null,
    useReducedMotion: () => false,
    buildLBracketShapeCommands: geometry.buildLBracketShapeCommands,
    ExtrudeScene: (props: Record<string, unknown>) => {
      calls.push(props);
      return null;
    },
  };
});

import { nextDemoParams } from "../lib/hero-loop";
import { HeroLoopDemo } from "./hero-loop-demo";

describe("HeroLoopDemo", () => {
  it("рендерить рівно одну ExtrudeScene з профілем, глибиною і testId L-кронштейна", () => {
    renderToStaticMarkup(<HeroLoopDemo />);
    const p = nextDemoParams(0);

    expect(calls).toHaveLength(1);
    expect(calls[0]?.["testId"]).toBe("l-bracket-canvas");
    expect(calls[0]?.["depthMm"]).toBe(p.width_mm);
    expect(calls[0]?.["commands"]).toEqual(
      buildLBracketShapeCommands({ parameters: p, thicknessMm: 2.0 }),
    );
  });
});
