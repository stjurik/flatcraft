/**
 * SSR-тести PerforatedPanelEditor (Варіант B — спільний редактор обох форм).
 *
 * @flatcraft/ui аліасовано на стаб (AutoForm→null, SegmentedControl→кнопки).
 * Перевіряємо ВЛАСНУ логіку редактора: SegmentedControl активна форма, гліф
 * Ø/□ у grid-summary, банер HOLES_OVERLAP при pitch ≤ розмір отвору.
 */
import { PERFORATED_PANEL_DEFAULT_PARAMETERS } from "@flatcraft/types";
import { renderToString } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { initialPerforationParams, type PerforationParameters } from "../lib/perforation-shape";

import { PerforatedPanelEditor } from "./perforated-panel-editor";

const noop = () => {};

function render(shape: "circle" | "square", params: PerforationParameters): string {
  const html = renderToString(
    <PerforatedPanelEditor
      value={params}
      onChange={noop}
      holeShape={shape}
      onHoleShapeChange={noop}
    />,
  );
  // SSR вставляє маркери <!-- --> між сусідніми JSX-виразами (у браузері їх
  // нема — textContent зливає текст). Прибираємо для матчингу тексту.
  return html.replace(/<!-- -->/g, "");
}

describe("PerforatedPanelEditor — форма отвору", () => {
  it("circle: гліф Ø, активна опція 'circle'", () => {
    const html = render("circle", initialPerforationParams("circle", { hole_diameter_mm: 8 }));
    expect(html).toContain("Ø");
    expect(html).not.toContain("□");
    expect(html).toMatch(/data-value="circle"[^>]*data-active="true"/);
  });

  it("square: гліф □, активна опція 'square'", () => {
    const html = render("square", initialPerforationParams("square", { hole_size_mm: 8 }));
    expect(html).toContain("□");
    expect(html).not.toContain("Ø");
    expect(html).toMatch(/data-value="square"[^>]*data-active="true"/);
  });

  it("валідні дефолти → зелений банер (validation-ok)", () => {
    const html = render("circle", initialPerforationParams("circle", {}));
    expect(html).toContain('data-testid="validation-ok"');
    expect(html).not.toContain('data-testid="validation-errors"');
  });

  it("pitch ≤ розмір отвору → банер HOLES_OVERLAP (перетин)", () => {
    // □20 при pitch_y=10 — отвори зливаються по Y (як каталожний дефект).
    const params = initialPerforationParams("square", {
      hole_size_mm: 20,
      pitch_x_mm: 27,
      pitch_y_mm: 10,
      length_mm: 300,
      width_mm: 100,
      margin_mm: 15,
    });
    const html = render("square", params);
    expect(html).toContain('data-testid="validation-errors"');
    expect(html).toContain("перетин");
  });

  it("grid-summary рахує отвори (round defaults: pitch 20 → 9×7=63)", () => {
    const html = render(
      "circle",
      initialPerforationParams("circle", PERFORATED_PANEL_DEFAULT_PARAMETERS),
    );
    // 200−30=170 → 9 cols; 150−30=120 → 7 rows.
    expect(html).toMatch(/Grid:\s*9×7\s*=\s*63 отворів/);
  });
});
