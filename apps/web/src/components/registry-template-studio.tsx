"use client";

import {
  TEMPLATE_REGISTRY,
  type TemplateDefinition,
  type TemplateSlug,
} from "@flatcraft/templates";
import type { MaterialChoice } from "@flatcraft/types";

import { RegistryTemplateEditor } from "./registry-template-editor";
import { RegistryTemplateViewport } from "./registry-template-viewport";
import {
  TemplateStudio,
  type TemplateStudioProductMeta,
  type TemplateStudioSlug,
} from "./template-studio";

interface RegistryTemplateStudioProps<Params extends Record<string, unknown>> {
  /**
   * ЛИШЕ slug, НЕ TemplateDefinition — `TemplateDefinition` несе функції
   * (`validators`, `ui.extraControls[].render`), а сервер-компоненти
   * (`template-detail-content.tsx`, `product-detail-content.tsx`) НЕ можуть
   * передавати функції клієнтським компонентам через RSC-серіалізацію (Next.js
   * kидає "Functions cannot be passed directly to Client Components" —
   * знайдено реальним e2e-прогоном, Run 7 Етап 2 PR perforated_panel).
   * Тому lookup у `TEMPLATE_REGISTRY` робиться ТУТ, у client-компоненті.
   */
  readonly slug: TemplateSlug;
  readonly initialParameters: Params;
  readonly materials: ReadonlyArray<MaterialChoice>;
  readonly product?: TemplateStudioProductMeta;
}

/**
 * Generic студія (Run 7 Master Registry Track, Етап 2) — thin wrapper над
 * наявним `TemplateStudio` (той самий паттерн, що й `perforated-panel-studio.tsx`
 * та ін., але керований `TemplateDefinition` замість хардкоду). Один цей
 * компонент замінює `<slug>-studio.tsx` для КОЖНОГО майбутнього
 * зареєстрованого шаблону — нових файлів на PR більше не додається.
 */
export function RegistryTemplateStudio<Params extends Record<string, unknown>>({
  slug,
  initialParameters,
  materials,
  product,
}: RegistryTemplateStudioProps<Params>) {
  const def = TEMPLATE_REGISTRY[slug] as unknown as TemplateDefinition<Params>;
  return (
    <TemplateStudio<Params>
      mode={product ? "product" : "part"}
      templateSlug={def.slug as TemplateStudioSlug}
      initialParameters={initialParameters}
      materials={materials}
      schema={def.schema}
      testId={`${def.slug.replaceAll("_", "-")}-studio`}
      {...(product ? { product } : {})}
      renderEditor={(props) => (
        <RegistryTemplateEditor
          def={def}
          value={props.value}
          onChange={props.onChange}
          thicknessMm={props.thicknessMm}
          materialCode={props.materialCode}
          {...(props.visibleFields ? { visibleFields: props.visibleFields } : {})}
        />
      )}
      renderViewport={(props) => (
        <RegistryTemplateViewport
          def={def}
          parameters={props.parameters}
          thicknessMm={props.thicknessMm}
        />
      )}
    />
  );
}
