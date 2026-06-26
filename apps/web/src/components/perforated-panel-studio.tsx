"use client";

import {
  PerforatedPanelParametersSchema,
  type MaterialChoice,
  type PerforatedPanelParameters,
} from "@flatcraft/types";

import { PerforatedPanelEditor } from "./perforated-panel-editor";
import { PerforatedPanelViewport } from "./perforated-panel-viewport";
import { TemplateStudio, type TemplateStudioProductMeta } from "./template-studio";

interface PerforatedPanelStudioProps {
  /** Стартові параметри (вкл. hole_shape) з роута або базового шаблону продукту. */
  readonly initialParameters: PerforatedPanelParameters;
  readonly materials: ReadonlyArray<MaterialChoice>;
  readonly product?: TemplateStudioProductMeta;
}

/**
 * Студія перфо-монтажної панелі — ОДИН параметричний шаблон (ADR-031). Форма
 * отвору (круг/квадрат) — звичайний параметр `hole_shape`, яким керує toggle у
 * редакторі (не перемикає slug/схему). Єдина схема, єдиний viewport.
 */
export function PerforatedPanelStudio({
  initialParameters,
  materials,
  product,
}: PerforatedPanelStudioProps) {
  return (
    <TemplateStudio<PerforatedPanelParameters>
      mode={product ? "product" : "part"}
      templateSlug="perforated_panel"
      initialParameters={initialParameters}
      materials={materials}
      schema={PerforatedPanelParametersSchema}
      testId="perforated-panel-studio"
      {...(product ? { product } : {})}
      renderEditor={(props) => (
        <PerforatedPanelEditor
          value={props.value}
          onChange={props.onChange}
          {...(props.visibleFields ? { visibleFields: props.visibleFields } : {})}
        />
      )}
      renderViewport={(props) => (
        <PerforatedPanelViewport parameters={props.parameters} thicknessMm={props.thicknessMm} />
      )}
    />
  );
}
