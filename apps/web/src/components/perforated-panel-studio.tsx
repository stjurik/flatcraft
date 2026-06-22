"use client";

import {
  PerforatedPanelParametersSchema,
  type PerforatedPanelParameters,
  type MaterialChoice,
} from "@flatcraft/types";

import { PerforatedPanelEditor } from "./perforated-panel-editor";
import { PerforatedPanelViewport } from "./perforated-panel-viewport";
import { TemplateStudio } from "./template-studio";

interface PerforatedPanelStudioProps {
  readonly initialParameters: PerforatedPanelParameters;
  readonly materials: ReadonlyArray<MaterialChoice>;
}

/**
 * Perforated panel — без гибів, тож TemplateStudio пропускає bend matrix
 * і profile validation (SLUGS_WITH_BENDS / SLUGS_WITH_PROFILE).
 *
 * Editor не приймає materialCode/thicknessMm — perforated не має cross-field
 * matrix-validation; передаємо через renderEditor але ігноруємо у нашому editor.
 */
export function PerforatedPanelStudio({
  initialParameters,
  materials,
}: PerforatedPanelStudioProps) {
  return (
    <TemplateStudio<PerforatedPanelParameters>
      mode="part"
      templateSlug="perforated_panel"
      initialParameters={initialParameters}
      materials={materials}
      schema={PerforatedPanelParametersSchema}
      testId="perforated-panel-studio"
      renderEditor={(props) => (
        <PerforatedPanelEditor value={props.value} onChange={props.onChange} />
      )}
      renderViewport={(props) => (
        <PerforatedPanelViewport parameters={props.parameters} thicknessMm={props.thicknessMm} />
      )}
    />
  );
}
