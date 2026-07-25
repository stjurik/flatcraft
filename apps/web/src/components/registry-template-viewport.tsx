"use client";

import type { TemplateDefinition } from "@flatcraft/templates";
import { R3FErrorBoundary } from "@flatcraft/ui";
import dynamic from "next/dynamic";
import { useMemo } from "react";

import { InvalidParametersFallback } from "./invalid-parameters-fallback";

interface RegistryTemplateViewportProps<Params extends Record<string, unknown>> {
  readonly def: TemplateDefinition<Params>;
  readonly parameters: Params;
  readonly thicknessMm: number;
}

// Один dynamic-wrapper (ssr:false, code-split) для ВСІХ kind:'composed'
// шаблонів — lookup за slug'ом усередині, а не per-slug dynamic() (не можна
// викликати dynamic() з реактивним slug на кожен render). Populated
// автоматично для будь-якого майбутнього composed-slug'а без правок цього
// файлу (STOP-знахідка docs/12 §1, Run 7 Етап 2 PR perforated_panel).
const DynamicComposedScene = dynamic(
  () =>
    import("@flatcraft/ui").then((m) => {
      function ComposedSceneRouter({
        slug,
        parameters,
        thicknessMm,
      }: {
        readonly slug: string;
        readonly parameters: unknown;
        readonly thicknessMm: number;
      }) {
        const Component = m.COMPOSED_SCENES[slug];
        if (!Component) return null;
        return <Component parameters={parameters} thicknessMm={thicknessMm} />;
      }
      return ComposedSceneRouter;
    }),
  {
    ssr: false,
    loading: () => (
      <div
        data-testid="registry-viewport-loading"
        className="text-fg-muted flex h-full w-full items-center justify-center text-sm"
      >
        Завантаження 3D…
      </div>
    ),
  },
);

// Один dynamic-wrapper для ВСІХ kind:'extrude' шаблонів (аналог
// DynamicComposedScene вище) — `ExtrudeScene` не знає slug'ів, лише
// `ShapeCommand[]` + depth, тому lookup тут не потрібен взагалі.
const DynamicExtrudeScene = dynamic(() => import("@flatcraft/ui").then((m) => m.ExtrudeScene), {
  ssr: false,
  loading: () => (
    <div
      data-testid="registry-viewport-loading"
      className="text-fg-muted flex h-full w-full items-center justify-center text-sm"
    >
      Завантаження 3D…
    </div>
  ),
});

/**
 * Generic viewport (Run 7 Master Registry Track, Етап 2) — керується
 * `TemplateDefinition` замість per-slug `*-viewport.tsx`.
 *
 * Render-gate (ADR-026) уніфіковано для ОБОХ kind'ів через `def.validators`
 * — раніше `perforated-panel-viewport.tsx` НЕ мав власного render-gate'у
 * (C1 A7: «гейт не потрібен, geometry OK», бо composed box-геометрія не
 * throw'ить на невалідних розмірах, на відміну від `build*ShapeCommands`).
 * Тепер render-gate стає структурною гарантією для БУДЬ-ЯКОГО зареєстрованого
 * шаблону (docs/12 §5: «generic-viewport ЗАВЖДИ виклик validateProfile()
 * через def.validators») — задокументоване покращення (закриває F2-клас
 * гепу), не regressed поведінка.
 *
 * `kind: 'extrude'` (Run 7 Етап 2, міграція l_bracket) — `ExtrudeScene`
 * (`@flatcraft/ui`) не знає імен полів конкретного шаблону, тому depth
 * (довжина лінії гиба) читається тут за задокументованою конвенцією
 * `width_mm` (ADR-033 §CONSEQUENCES: «X×Y = силует профілю, Z = довжина
 * лінії гиба (`width`)» — та сама конвенція, що вже давала `l_bracket`,
 * `z_bracket`, `wall_shelf`, `corner_angle`).
 */
export function RegistryTemplateViewport<Params extends Record<string, unknown>>({
  def,
  parameters,
  thicknessMm,
}: RegistryTemplateViewportProps<Params>) {
  const testId = `${def.slug.replaceAll("_", "-")}-viewport`;
  const issues = def.validators.flatMap((validator) => validator(parameters, thicknessMm));
  const depthMm = typeof parameters["width_mm"] === "number" ? parameters["width_mm"] : 0;
  // Мемоізовано — інакше нова ShapeCommand[]-референція на КОЖЕН render
  // (не лише при зміні параметрів) звела б нанівець useMemo усередині
  // ExtrudeScene (перебудова THREE.ExtrudeGeometry без потреби). Render-gate
  // (ADR-026): `build*ShapeCommands` throw'ить на невалідній геометрії
  // (напр. legB замалий для t+r) — `issues.length > 0` вже ловить це через
  // `def.validators`, тому build ВЗАГАЛІ не викликаємо у цьому випадку
  // (інакше throw усередині useMemo зваливши б увесь render, поза fallback-гілкою).
  const extrudeCommands = useMemo(() => {
    if (issues.length > 0) return [];
    return def.ui.scene.kind === "extrude" ? def.ui.scene.build(parameters, thicknessMm) : [];
  }, [def.ui.scene, parameters, thicknessMm, issues.length]);

  return (
    <div
      id="studio-viewport"
      data-testid={testId}
      className="border-border bg-surface-sunken aspect-video w-full scroll-mt-20 overflow-hidden rounded-md border"
    >
      {issues.length > 0 ? (
        <InvalidParametersFallback
          issues={issues.map((issue) => ({
            which: issue.field,
            message: issue.message ?? issue.code,
          }))}
        />
      ) : def.ui.scene.kind === "composed" ? (
        <R3FErrorBoundary>
          <DynamicComposedScene slug={def.slug} parameters={parameters} thicknessMm={thicknessMm} />
        </R3FErrorBoundary>
      ) : (
        <R3FErrorBoundary>
          <DynamicExtrudeScene
            commands={extrudeCommands}
            depthMm={depthMm}
            testId={`${testId}-canvas`}
          />
        </R3FErrorBoundary>
      )}
    </div>
  );
}
