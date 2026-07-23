/**
 * SSR-тести RegistryTemplateEditor (Run 7 Master Registry Track, Етап 2) —
 * заміняє видалений `perforated-panel-editor.test.tsx`: та сама поведінка
 * (SegmentedControl активна форма, гліф Ø/□ у grid-summary, банер
 * HOLES_OVERLAP при pitch ≤ розмір отвору), тепер керована `TemplateDefinition`.
 *
 * @flatcraft/ui аліасовано на стаб (AutoForm→null, SegmentedControl→кнопки).
 */
import { TEMPLATE_REGISTRY } from "@flatcraft/templates";
import {
  PERFORATED_PANEL_DEFAULT_PARAMETERS,
  type PerforatedPanelParameters,
} from "@flatcraft/types";
import { renderToString } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { RegistryTemplateEditor } from "./registry-template-editor";

const def = TEMPLATE_REGISTRY.perforated_panel;
const noop = () => {};

function params(overrides: Partial<PerforatedPanelParameters>): PerforatedPanelParameters {
  return { ...PERFORATED_PANEL_DEFAULT_PARAMETERS, ...overrides };
}

function render(p: PerforatedPanelParameters): string {
  const html = renderToString(
    <RegistryTemplateEditor def={def} value={p} onChange={noop} thicknessMm={2} />,
  );
  return html.replace(/<!-- -->/g, "");
}

describe("RegistryTemplateEditor — perforated_panel форма отвору", () => {
  it("circle: гліф Ø, активна опція 'circle'", () => {
    const html = render(params({ hole_shape: "circle" }));
    expect(html).toContain("Ø");
    expect(html).not.toContain("□");
    expect(html).toMatch(/data-value="circle"[^>]*data-active="true"/);
  });

  it("square: гліф □, активна опція 'square'", () => {
    const html = render(params({ hole_shape: "square" }));
    expect(html).toContain("□");
    expect(html).not.toContain("Ø");
    expect(html).toMatch(/data-value="square"[^>]*data-active="true"/);
  });

  it("валідні дефолти → зелений банер (validation-ok)", () => {
    const html = render(params({ hole_shape: "circle" }));
    expect(html).toContain('data-testid="validation-ok"');
    expect(html).not.toContain('data-testid="validation-errors"');
  });

  it("pitch ≤ розмір отвору → банер HOLES_OVERLAP (перетин)", () => {
    const html = render(
      params({
        hole_shape: "square",
        hole_size_mm: 20,
        pitch_x_mm: 27,
        pitch_y_mm: 10,
        length_mm: 300,
        width_mm: 100,
        margin_mm: 15,
      }),
    );
    expect(html).toContain('data-testid="validation-errors"');
    expect(html).toContain("перетин");
  });

  it("grid-summary рахує отвори (pitch 20 → 9×7=63)", () => {
    const html = render(params({ hole_shape: "circle", pitch_x_mm: 20, pitch_y_mm: 20 }));
    expect(html).toMatch(/Grid:\s*9×7\s*=\s*63 отворів/);
  });
});
