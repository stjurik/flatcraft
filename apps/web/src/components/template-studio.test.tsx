/**
 * Доробка #275 (issue #237 п.2, Argon-контрприклад 1, PR
 * #275#issuecomment-6410942324): `exportDisabled` у `TemplateStudio` раніше
 * рахував лише `SLUGS_WITH_PROFILE`/`SLUGS_WITH_PERFORATION` (легасі-шлях
 * per-slug шаблонів до Registry) — `enclosed_shelf` поза обома сетами, тож
 * `def.validators` (render-gate ADR-026) ігнорувалися: 3D-сцена ховалась
 * (`RegistryTemplateViewport` читає `def.validators` напряму), а кнопка
 * «Експортувати» лишалась активною — клік падав 500 у воркері
 * (`unfold.py:799-805` ValueError на виродженому ребрі).
 *
 * `@flatcraft/ui` тут підмінено ЛОКАЛЬНИМ `vi.mock` (не спільним стабом
 * `src/test/flatcraft-ui-stub.tsx` — той не несе `MaterialSection`/
 * `useDebouncedValue`/`useIsMobile`/`useReducedMotion`/`viewportQuality`/
 * `Button`, потрібні `TemplateStudio`/`ExportButton`), той самий паттерн, що
 * й `hero-loop-demo.test.tsx`.
 */
import type { ReactNode } from "react";
import { describe, expect, it, vi } from "vitest";

vi.mock("@flatcraft/ui", () => ({
  MaterialSection: () => null,
  useDebouncedValue: <T,>(value: T): T => value,
  useIsMobile: () => false,
  useReducedMotion: () => false,
  viewportQuality: () => ({
    dpr: [1, 1] as const,
    enableZoom: true,
    enableRotate: true,
    debounceMs: 0,
    curveSegments: 12,
  }),
  Button: ({ children, ...rest }: { readonly children?: ReactNode } & Record<string, unknown>) => (
    <button {...rest}>{children}</button>
  ),
  Heart: () => null,
}));

import { TEMPLATE_REGISTRY } from "@flatcraft/templates";
import type { EnclosedShelfParameters } from "@flatcraft/types";
import { renderToString } from "react-dom/server";

import { TemplateStudio } from "./template-studio";

const def = TEMPLATE_REGISTRY.enclosed_shelf;

function renderStudio(parameters: EnclosedShelfParameters): string {
  return renderToString(
    <TemplateStudio
      mode="part"
      templateSlug="enclosed_shelf"
      initialParameters={parameters}
      materials={[]}
      schema={def.schema}
      validators={def.validators}
      testId="enclosed-shelf-studio-test"
      renderEditor={() => null}
      renderViewport={() => null}
    />,
  );
}

function exportButtonDisabled(html: string): boolean {
  const match = html.match(/<button[^>]*data-testid="export-button"[^>]*>/);
  if (!match) throw new Error("export-button не знайдено у рендері");
  return match[0].includes("disabled");
}

describe("TemplateStudio — exportDisabled читає def.validators (доробка #275)", () => {
  it("дефолтні параметри enclosed_shelf → кнопка активна", () => {
    const html = renderStudio(def.defaults);
    expect(exportButtonDisabled(html)).toBe(false);
  });

  it("Argon #1: вироджене ребро (height_mm 5 <= t+r=6 при thicknessMm=2, r=4) → кнопка неактивна", () => {
    // DEFAULT_THICKNESS_MM у TemplateStudio = 2.0 (внутрішній useState,
    // некерований зовні без взаємодії з MaterialSection). r=4 — дозволене
    // bend_radius_mm (схема); height_mm=5 — у Zod-діапазоні [5,50], тож
    // isValid(schema) залишається true, а падає лише новий def.validators.
    const html = renderStudio({
      ...def.defaults,
      bend_radius_mm: 4,
      stiffening_rib: { height_mm: 5 },
    } as EnclosedShelfParameters);
    expect(exportButtonDisabled(html)).toBe(true);
  });

  it("Argon #3: side_perforation без місця (margin 48, depth 100, r=2.5, t=2) → кнопка неактивна", () => {
    const html = renderStudio({
      ...def.defaults,
      depth_mm: 100,
      bend_radius_mm: 2.5,
      side_perforation: { hole_size_mm: 10, pitch_x_mm: 20, pitch_y_mm: 20, margin_mm: 48 },
    } as EnclosedShelfParameters);
    expect(exportButtonDisabled(html)).toBe(true);
  });
});
