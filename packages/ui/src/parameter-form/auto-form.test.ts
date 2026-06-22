/**
 * Юніт-тести AutoForm — фокус на Phase 3.0 PR 4 visibleFields prop
 * (ADR-027 Рішення 4).
 *
 * Рендеримо через renderToString (SSR) як editor-matrix-validation.test —
 * ui-suite без jsdom, але SSR-rendering підтримує useMemo. Шукаємо у HTML
 * наявність `data-testid="param-<field>"` для перевірки фільтрації.
 */
import { createElement } from "react";
import { renderToString } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { z } from "zod";

import { AutoForm } from "./auto-form.js";

const TEST_SCHEMA = z.object({
  width_mm: z.number().min(20).max(3000),
  height_mm: z.number().min(20).max(3000),
  thickness_mm: z.number().min(0.5).max(8),
  bend_radius_mm: z.union([z.literal(1), z.literal(2.5), z.literal(4), z.literal(5)]),
});

type TestValues = z.infer<typeof TEST_SCHEMA>;

const VALUES: TestValues = {
  width_mm: 200,
  height_mm: 300,
  thickness_mm: 2,
  bend_radius_mm: 2.5,
};

function render(props: Parameters<typeof AutoForm<TestValues>>[0]): string {
  return renderToString(createElement(AutoForm<TestValues>, props));
}

function hasParam(html: string, name: string): boolean {
  return html.includes(`data-testid="param-${name}"`);
}

describe("AutoForm visibleFields (Phase 3.0 PR 4, ADR-027 Рішення 4)", () => {
  it("undefined visibleFields → рендерить ВСІ поля (regression: legacy AutoForm)", () => {
    const html = render({
      schema: TEST_SCHEMA,
      value: VALUES,
      onChange: () => {},
    });
    expect(hasParam(html, "width_mm")).toBe(true);
    expect(hasParam(html, "height_mm")).toBe(true);
    expect(hasParam(html, "thickness_mm")).toBe(true);
    expect(hasParam(html, "bend_radius_mm")).toBe(true);
  });

  it("visibleFields=['width_mm','height_mm'] → лише два поля у формі", () => {
    const html = render({
      schema: TEST_SCHEMA,
      value: VALUES,
      onChange: () => {},
      visibleFields: ["width_mm", "height_mm"],
    });
    expect(hasParam(html, "width_mm")).toBe(true);
    expect(hasParam(html, "height_mm")).toBe(true);
    expect(hasParam(html, "thickness_mm")).toBe(false);
    expect(hasParam(html, "bend_radius_mm")).toBe(false);
  });

  it("visibleFields=[] → не рендерить жодного param-поля", () => {
    const html = render({
      schema: TEST_SCHEMA,
      value: VALUES,
      onChange: () => {},
      visibleFields: [],
    });
    // Сама форма (auto-form) лишається, але param-* нема.
    expect(html.includes('data-testid="auto-form"')).toBe(true);
    expect(hasParam(html, "width_mm")).toBe(false);
    expect(hasParam(html, "height_mm")).toBe(false);
  });

  it("невідомі поля у visibleFields тихо ігноруються (seed-валідатор — окремо)", () => {
    const html = render({
      schema: TEST_SCHEMA,
      value: VALUES,
      onChange: () => {},
      visibleFields: ["width_mm", "made_up_field"],
    });
    expect(hasParam(html, "width_mm")).toBe(true);
    expect(hasParam(html, "made_up_field")).toBe(false);
  });

  it("порядок рендеру — за схемою, не за visibleFields", () => {
    const html = render({
      schema: TEST_SCHEMA,
      value: VALUES,
      onChange: () => {},
      // У "перевернутому" порядку:
      visibleFields: ["bend_radius_mm", "width_mm"],
    });
    // У HTML width_mm з'являється РАНІШЕ за bend_radius_mm (schema order).
    expect(html.indexOf('data-testid="param-width_mm"')).toBeLessThan(
      html.indexOf('data-testid="param-bend_radius_mm"'),
    );
  });

  it("groups стабільні: легенда рендериться лише якщо у групі є видимі поля", () => {
    const SchemaWithGroups = z.object({
      width_mm: z.number().min(20).max(3000).describe("group:Розміри"),
      bend_radius_mm: z.union([z.literal(1), z.literal(2.5)]).describe("group:Гиб"),
    });
    const html = renderToString(
      createElement(AutoForm<{ width_mm: number; bend_radius_mm: 1 | 2.5 }>, {
        schema: SchemaWithGroups,
        value: { width_mm: 100, bend_radius_mm: 1 },
        onChange: () => {},
        visibleFields: ["width_mm"], // лише Розміри
      }),
    );
    expect(html.includes('data-testid="auto-form-group-Розміри"')).toBe(true);
    expect(html.includes('data-testid="auto-form-group-Гиб"')).toBe(false);
    expect(html.includes('data-testid="param-width_mm"')).toBe(true);
    expect(html.includes('data-testid="param-bend_radius_mm"')).toBe(false);
  });
});
