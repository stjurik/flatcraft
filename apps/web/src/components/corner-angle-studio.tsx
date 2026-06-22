"use client";

import {
  CornerAngleParametersSchema,
  type CornerAngleParameters,
  type MaterialChoice,
} from "@flatcraft/types";

import { CornerAngleEditor } from "./corner-angle-editor";
import { CornerAngleViewport } from "./corner-angle-viewport";
import { TemplateStudio } from "./template-studio";

interface CornerAngleStudioProps {
  readonly initialParameters: CornerAngleParameters;
  readonly materials: ReadonlyArray<MaterialChoice>;
}

export function CornerAngleStudio({ initialParameters, materials }: CornerAngleStudioProps) {
  return (
    <TemplateStudio<CornerAngleParameters>
      mode="part"
      templateSlug="corner_angle"
      initialParameters={initialParameters}
      materials={materials}
      schema={CornerAngleParametersSchema}
      testId="corner-angle-studio"
      renderEditor={(props) => (
        <CornerAngleEditor
          value={props.value}
          onChange={props.onChange}
          materialCode={props.materialCode}
          thicknessMm={props.thicknessMm}
        />
      )}
      renderViewport={(props) => (
        <CornerAngleViewport parameters={props.parameters} thicknessMm={props.thicknessMm} />
      )}
    />
  );
}
