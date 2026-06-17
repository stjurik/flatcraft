/**
 * Hotfix 2.9.f (ADR-026): render-gate у 4 гибових viewport'ах.
 *
 * SSR-рендер (renderToString — web-suite без jsdom). Невалідна геометрія →
 * InvalidParametersFallback замість сцени (НЕ монтуємо <Canvas> → нема throw з
 * build*ShapeCommands → нема R3F-крашу). Валідна → dynamic(ssr:false) показує
 * loading-плейсхолдер (сцена вантажиться лише в браузері).
 *
 * @flatcraft/ui аліасовано на стаб (vitest.config.ts): R3FErrorBoundary —
 * passthrough, Scene — плейсхолдери. validateProfile береться з РЕАЛЬНОГО
 * @flatcraft/cad-engine.
 */
import {
  CORNER_ANGLE_DEFAULT_PARAMETERS,
  L_BRACKET_DEFAULT_PARAMETERS,
  WALL_SHELF_DEFAULT_PARAMETERS,
  Z_BRACKET_DEFAULT_PARAMETERS,
} from "@flatcraft/types";
import { renderToString } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { CornerAngleViewport } from "./corner-angle-viewport";
import { LBracketViewport } from "./l-bracket-viewport";
import { WallShelfViewport } from "./wall-shelf-viewport";
import { ZBracketViewport } from "./z-bracket-viewport";

const T = 2; // t+r = 2 + 2.5 = 4.5 для default bend_radius_mm.
const FALLBACK = "Виправте параметри у формі";
const LOADING = "Завантаження 3D";

describe("render-gate: corner_angle", () => {
  it("невалідний legA → fallback, без сцени", () => {
    const html = renderToString(
      <CornerAngleViewport
        parameters={{ ...CORNER_ANGLE_DEFAULT_PARAMETERS, legA_mm: 1 }}
        thicknessMm={T}
      />,
    );
    expect(html).toContain(FALLBACK);
    expect(html).not.toContain(LOADING);
  });

  it("валідні параметри → сцена (loading), без fallback", () => {
    const html = renderToString(
      <CornerAngleViewport parameters={CORNER_ANGLE_DEFAULT_PARAMETERS} thicknessMm={T} />,
    );
    expect(html).toContain(LOADING);
    expect(html).not.toContain(FALLBACK);
  });
});

describe("render-gate: l_bracket", () => {
  it("невалідний legB → fallback", () => {
    const html = renderToString(
      <LBracketViewport
        parameters={{ ...L_BRACKET_DEFAULT_PARAMETERS, legB_mm: 1 }}
        thicknessMm={T}
      />,
    );
    expect(html).toContain(FALLBACK);
  });

  it("валідні → сцена", () => {
    const html = renderToString(
      <LBracketViewport parameters={L_BRACKET_DEFAULT_PARAMETERS} thicknessMm={T} />,
    );
    expect(html).toContain(LOADING);
  });
});

describe("render-gate: z_bracket", () => {
  it("замала top_flange → fallback", () => {
    const html = renderToString(
      <ZBracketViewport
        parameters={{ ...Z_BRACKET_DEFAULT_PARAMETERS, top_flange_mm: 2 }}
        thicknessMm={T}
      />,
    );
    expect(html).toContain(FALLBACK);
  });

  it("валідні → сцена", () => {
    const html = renderToString(
      <ZBracketViewport parameters={Z_BRACKET_DEFAULT_PARAMETERS} thicknessMm={T} />,
    );
    expect(html).toContain(LOADING);
  });
});

describe("render-gate: wall_shelf", () => {
  it("замала back_height → fallback", () => {
    const html = renderToString(
      <WallShelfViewport
        parameters={{ ...WALL_SHELF_DEFAULT_PARAMETERS, back_height_mm: 3 }}
        thicknessMm={T}
      />,
    );
    expect(html).toContain(FALLBACK);
  });

  it("валідні → сцена", () => {
    const html = renderToString(
      <WallShelfViewport parameters={WALL_SHELF_DEFAULT_PARAMETERS} thicknessMm={T} />,
    );
    expect(html).toContain(LOADING);
  });
});
