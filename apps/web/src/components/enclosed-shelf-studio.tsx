"use client";

import {
  EnclosedShelfParametersSchema,
  type EnclosedShelfParameters,
  type MaterialChoice,
} from "@flatcraft/types";

import { EnclosedShelfEditor } from "./enclosed-shelf-editor";
import { EnclosedShelfViewport } from "./enclosed-shelf-viewport";
import { TemplateStudio, type TemplateStudioProductMeta } from "./template-studio";

interface EnclosedShelfStudioProps {
  readonly initialParameters: EnclosedShelfParameters;
  readonly materials: ReadonlyArray<MaterialChoice>;
  /**
   * Phase 3.0 PR 7d (ADR-027): коли задано — студія рендериться у product-mode
   * (header з product.name + AutoForm фільтрується по visibleFields). Інакше
   * — звичайний part-mode для прямого `/templates/enclosed_shelf`.
   */
  readonly product?: TemplateStudioProductMeta;
}

/**
 * Студія enclosed_shelf — thin wrapper над TemplateStudio (Phase 3.0 PR 4
 * pattern, ADR-027 Рішення 3). Slug `enclosed_shelf` додано у
 * `TemplateStudioSlug` enum + у SLUGS_WITH_BENDS (3-4 гиби, матрична валідація).
 */
export function EnclosedShelfStudio({
  initialParameters,
  materials,
  product,
}: EnclosedShelfStudioProps) {
  return (
    <TemplateStudio<EnclosedShelfParameters>
      mode={product ? "product" : "part"}
      templateSlug="enclosed_shelf"
      initialParameters={initialParameters}
      materials={materials}
      schema={EnclosedShelfParametersSchema}
      testId="enclosed-shelf-studio"
      {...(product ? { product } : {})}
      renderEditor={(props) => (
        <EnclosedShelfEditor
          value={props.value}
          onChange={props.onChange}
          materialCode={props.materialCode}
          thicknessMm={props.thicknessMm}
          {...(props.visibleFields ? { visibleFields: props.visibleFields } : {})}
        />
      )}
      renderViewport={(props) => (
        <EnclosedShelfViewport parameters={props.parameters} thicknessMm={props.thicknessMm} />
      )}
    />
  );
}
