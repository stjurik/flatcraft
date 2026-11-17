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
import { TEMPLATE_REGISTRY } from "@flatcraft/templates";
import { PERFORATED_PANEL_DEFAULT_PARAMETERS } from "@flatcraft/types";
import { renderToString } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { RegistryTemplateViewport } from "./registry-template-viewport";

const T = 2; // t+r = 2 + 2.5 = 4.5 для default bend_radius_mm.
const FALLBACK = "Виправте параметри у формі";
const LOADING = "Завантаження 3D";

describe("render-gate: l_bracket (RegistryTemplateViewport, Run 7 Етап 2)", () => {
  const def = TEMPLATE_REGISTRY.l_bracket;

  it("невалідний legB → fallback, без сцени", () => {
    const html = renderToString(
      <RegistryTemplateViewport
        def={def}
        parameters={{ ...def.defaults, legB_mm: 1 }}
        thicknessMm={T}
      />,
    );
    expect(html).toContain(FALLBACK);
    expect(html).not.toContain(LOADING);
  });

  it("валідні параметри → сцена (extrude, dynamic loading), без fallback", () => {
    const html = renderToString(
      <RegistryTemplateViewport def={def} parameters={def.defaults} thicknessMm={T} />,
    );
    expect(html).toContain(LOADING);
    expect(html).not.toContain(FALLBACK);
  });
});

describe("render-gate: z_bracket (RegistryTemplateViewport, Run 7 Етап 2)", () => {
  const def = TEMPLATE_REGISTRY.z_bracket;

  it("замала top_flange → fallback, без сцени", () => {
    const html = renderToString(
      <RegistryTemplateViewport
        def={def}
        parameters={{ ...def.defaults, top_flange_mm: 2 }}
        thicknessMm={T}
      />,
    );
    expect(html).toContain(FALLBACK);
    expect(html).not.toContain(LOADING);
  });

  it("валідні параметри → сцена (extrude, dynamic loading), без fallback", () => {
    const html = renderToString(
      <RegistryTemplateViewport def={def} parameters={def.defaults} thicknessMm={T} />,
    );
    expect(html).toContain(LOADING);
    expect(html).not.toContain(FALLBACK);
  });
});

describe("render-gate: wall_shelf (RegistryTemplateViewport, Run 7 Етап 2)", () => {
  const def = TEMPLATE_REGISTRY.wall_shelf;

  it("замала back_height → fallback, без сцени", () => {
    const html = renderToString(
      <RegistryTemplateViewport
        def={def}
        parameters={{ ...def.defaults, back_height_mm: 3 }}
        thicknessMm={T}
      />,
    );
    expect(html).toContain(FALLBACK);
    expect(html).not.toContain(LOADING);
  });

  it("валідні параметри → сцена (composed, dynamic loading), без fallback", () => {
    const html = renderToString(
      <RegistryTemplateViewport def={def} parameters={def.defaults} thicknessMm={T} />,
    );
    expect(html).toContain(LOADING);
    expect(html).not.toContain(FALLBACK);
  });
});

describe("render-gate: perforated_panel (RegistryTemplateViewport, Run 7 Етап 2)", () => {
  const def = TEMPLATE_REGISTRY.perforated_panel;

  it("замале ребро (rib_height ≤ t+r) → fallback — НОВИЙ render-gate (раніше не мав)", () => {
    // default bend_radius_mm=2.5; t=10 → min=t+r=12.5; rib_height=10 <= 12.5 → invalid.
    const html = renderToString(
      <RegistryTemplateViewport
        def={def}
        parameters={{ ...PERFORATED_PANEL_DEFAULT_PARAMETERS, rib_height_mm: 10 }}
        thicknessMm={10}
      />,
    );
    expect(html).toContain(FALLBACK);
    expect(html).not.toContain(LOADING);
  });

  it("валідні → сцена (composed, dynamic loading)", () => {
    const html = renderToString(
      <RegistryTemplateViewport
        def={def}
        parameters={PERFORATED_PANEL_DEFAULT_PARAMETERS}
        thicknessMm={T}
      />,
    );
    expect(html).toContain(LOADING);
    expect(html).not.toContain(FALLBACK);
  });
});

// enclosed_shelf — `def.validators` НЕ порожній (issue #237 п.2, ADR-026):
// `validateProfile` і далі НЕ підтримує `templateSlug: "enclosed_shelf"` (той
// самий задокументований розрив, що лежить у `export-gate.ts`
// (`case "enclosed_shelf": return []`) і `template-studio.tsx`
// (`SLUGS_WITH_PROFILE` без `enclosed_shelf`) — cross-розгортка profile-кейс
// не моделюється), але `enclosedShelfDefinition.validators` тепер має
// Zod-schema-валідатор + bend-matrix thickness-валідатор +
// `stiffeningRibValidator` + `sidePerforationValidator`
// (`packages/templates/src/enclosed-shelf/index.ts`, доробка #275 —
// Argon-контрприклади 1 і 3), тож "невалідні параметри → fallback" кейс тут
// є, як і для інших шаблонів.
describe("render-gate: enclosed_shelf (RegistryTemplateViewport, Run 7 Етап 2)", () => {
  const def = TEMPLATE_REGISTRY.enclosed_shelf;

  it("невалідний width_mm (< min 300) → fallback, без сцени", () => {
    const html = renderToString(
      <RegistryTemplateViewport
        def={def}
        parameters={{ ...def.defaults, width_mm: 50 }}
        thicknessMm={T}
      />,
    );
    expect(html).toContain(FALLBACK);
    expect(html).not.toContain(LOADING);
  });

  it("Argon #1: ребро height_mm <= t+r (5 <= 2.5+2.5) → fallback, без сцени", () => {
    const html = renderToString(
      <RegistryTemplateViewport
        def={def}
        parameters={{
          ...def.defaults,
          bend_radius_mm: 2.5,
          stiffening_rib: { height_mm: 5 },
        }}
        thicknessMm={2.5}
      />,
    );
    expect(html).toContain(FALLBACK);
    expect(html).not.toContain(LOADING);
  });

  it("Argon #3: margin занадто великий для depth-(t+r) (0 отворів у розгортці) → fallback", () => {
    const html = renderToString(
      <RegistryTemplateViewport
        def={def}
        parameters={{
          ...def.defaults,
          depth_mm: 100,
          bend_radius_mm: 2.5,
          side_perforation: { hole_size_mm: 10, pitch_x_mm: 20, pitch_y_mm: 20, margin_mm: 48 },
        }}
        thicknessMm={2}
      />,
    );
    expect(html).toContain(FALLBACK);
    expect(html).not.toContain(LOADING);
  });

  it("валідні параметри → сцена (composed, dynamic loading), без fallback", () => {
    const html = renderToString(
      <RegistryTemplateViewport def={def} parameters={def.defaults} thicknessMm={T} />,
    );
    expect(html).toContain(LOADING);
    expect(html).not.toContain(FALLBACK);
  });
});

describe("render-gate: corner_angle (RegistryTemplateViewport, Run 7 Етап 2)", () => {
  const def = TEMPLATE_REGISTRY.corner_angle;

  it("невалідний legA → fallback, без сцени", () => {
    const html = renderToString(
      <RegistryTemplateViewport
        def={def}
        parameters={{ ...def.defaults, legA_mm: 1 }}
        thicknessMm={T}
      />,
    );
    expect(html).toContain(FALLBACK);
    expect(html).not.toContain(LOADING);
  });

  it("валідні параметри → сцена (composed, dynamic loading), без fallback", () => {
    const html = renderToString(
      <RegistryTemplateViewport def={def} parameters={def.defaults} thicknessMm={T} />,
    );
    expect(html).toContain(LOADING);
    expect(html).not.toContain(FALLBACK);
  });
});
