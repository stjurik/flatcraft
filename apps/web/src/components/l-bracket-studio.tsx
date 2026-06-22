"use client";

import {
  LBracketParametersSchema,
  type LBracketParameters,
  type MaterialChoice,
} from "@flatcraft/types";

import { LBracketEditor } from "./l-bracket-editor";
import { LBracketViewport } from "./l-bracket-viewport";
import { TemplateStudio } from "./template-studio";

interface LBracketStudioProps {
  readonly initialParameters: LBracketParameters;
  readonly materials: ReadonlyArray<MaterialChoice>;
}

/**
 * L-bracket studio — тонка обгортка над generic TemplateStudio (Phase 3.0 PR 4,
 * ADR-027 Рішення 3). Передає template-specific Editor/Viewport renderers і
 * шаблонову Zod-схему. mode='part' жорстко — `/products/l-bracket-*` (якщо колись
 * з'являться) використовуватимуть TemplateStudio mode='product' напряму.
 */
export function LBracketStudio({ initialParameters, materials }: LBracketStudioProps) {
  return (
    <TemplateStudio<LBracketParameters>
      mode="part"
      templateSlug="l_bracket"
      initialParameters={initialParameters}
      materials={materials}
      schema={LBracketParametersSchema}
      testId="l-bracket-studio"
      renderEditor={(props) => (
        <LBracketEditor
          value={props.value}
          onChange={props.onChange}
          materialCode={props.materialCode}
          thicknessMm={props.thicknessMm}
        />
      )}
      renderViewport={(props) => (
        <LBracketViewport parameters={props.parameters} thicknessMm={props.thicknessMm} />
      )}
    />
  );
}
