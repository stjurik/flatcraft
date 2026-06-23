"use client";

import {
  PerforatedPanelSquareParametersSchema,
  type PerforatedPanelSquareParameters,
  type MaterialChoice,
} from "@flatcraft/types";

import { PerforatedPanelSquareEditor } from "./perforated-panel-square-editor";
import { PerforatedPanelSquareViewport } from "./perforated-panel-square-viewport";
import { TemplateStudio, type TemplateStudioProductMeta } from "./template-studio";

interface PerforatedPanelSquareStudioProps {
  readonly initialParameters: PerforatedPanelSquareParameters;
  readonly materials: ReadonlyArray<MaterialChoice>;
  /**
   * Phase 3.0 PR 6 (ADR-027): коли задано — студія рендериться у product-mode
   * (header з product.name + AutoForm фільтрується по visibleFields). Інакше
   * — звичайний part-mode (підстраховка на майбутнє; perforated_panel_square
   * unpublished — у каталог не потрапляє, але URL прямий працює).
   */
  readonly product?: TemplateStudioProductMeta;
}

/**
 * Студія perforated_panel_square — thin wrapper над TemplateStudio
 * (Phase 3.0 PR 4 pattern, ADR-027 Рішення 3).
 *
 * Має той самий slug у TemplateStudioSlug (perforated_panel_square додано
 * у template-studio.tsx ENUM).
 */
export function PerforatedPanelSquareStudio({
  initialParameters,
  materials,
  product,
}: PerforatedPanelSquareStudioProps) {
  return (
    <TemplateStudio<PerforatedPanelSquareParameters>
      mode={product ? "product" : "part"}
      templateSlug="perforated_panel_square"
      initialParameters={initialParameters}
      materials={materials}
      schema={PerforatedPanelSquareParametersSchema}
      testId="perforated-panel-square-studio"
      {...(product ? { product } : {})}
      renderEditor={(props) => (
        <PerforatedPanelSquareEditor
          value={props.value}
          onChange={props.onChange}
          {...(props.visibleFields ? { visibleFields: props.visibleFields } : {})}
        />
      )}
      renderViewport={(props) => (
        <PerforatedPanelSquareViewport
          parameters={props.parameters}
          thicknessMm={props.thicknessMm}
        />
      )}
    />
  );
}
