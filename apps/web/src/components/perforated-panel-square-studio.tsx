"use client";

import {
  PerforatedPanelSquareParametersSchema,
  type PerforatedPanelSquareParameters,
  type MaterialChoice,
} from "@flatcraft/types";

import { PerforatedPanelSquareEditor } from "./perforated-panel-square-editor";
import { PerforatedPanelSquareViewport } from "./perforated-panel-square-viewport";
import { TemplateStudio } from "./template-studio";

interface PerforatedPanelSquareStudioProps {
  readonly initialParameters: PerforatedPanelSquareParameters;
  readonly materials: ReadonlyArray<MaterialChoice>;
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
}: PerforatedPanelSquareStudioProps) {
  return (
    <TemplateStudio<PerforatedPanelSquareParameters>
      mode="part"
      templateSlug="perforated_panel_square"
      initialParameters={initialParameters}
      materials={materials}
      schema={PerforatedPanelSquareParametersSchema}
      testId="perforated-panel-square-studio"
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
