"use client";

import {
  ZBracketParametersSchema,
  type ZBracketParameters,
  type MaterialChoice,
} from "@flatcraft/types";

import { TemplateStudio } from "./template-studio";
import { ZBracketEditor } from "./z-bracket-editor";
import { ZBracketViewport } from "./z-bracket-viewport";

interface ZBracketStudioProps {
  readonly initialParameters: ZBracketParameters;
  readonly materials: ReadonlyArray<MaterialChoice>;
}

export function ZBracketStudio({ initialParameters, materials }: ZBracketStudioProps) {
  return (
    <TemplateStudio<ZBracketParameters>
      mode="part"
      templateSlug="z_bracket"
      initialParameters={initialParameters}
      materials={materials}
      schema={ZBracketParametersSchema}
      testId="z-bracket-studio"
      renderEditor={(props) => (
        <ZBracketEditor
          value={props.value}
          onChange={props.onChange}
          materialCode={props.materialCode}
          thicknessMm={props.thicknessMm}
        />
      )}
      renderViewport={(props) => (
        <ZBracketViewport parameters={props.parameters} thicknessMm={props.thicknessMm} />
      )}
    />
  );
}
