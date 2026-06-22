"use client";

import {
  WallShelfParametersSchema,
  type WallShelfParameters,
  type MaterialChoice,
} from "@flatcraft/types";

import { TemplateStudio } from "./template-studio";
import { WallShelfEditor } from "./wall-shelf-editor";
import { WallShelfViewport } from "./wall-shelf-viewport";

interface WallShelfStudioProps {
  readonly initialParameters: WallShelfParameters;
  readonly materials: ReadonlyArray<MaterialChoice>;
}

export function WallShelfStudio({ initialParameters, materials }: WallShelfStudioProps) {
  return (
    <TemplateStudio<WallShelfParameters>
      mode="part"
      templateSlug="wall_shelf"
      initialParameters={initialParameters}
      materials={materials}
      schema={WallShelfParametersSchema}
      testId="wall-shelf-studio"
      renderEditor={(props) => (
        <WallShelfEditor
          value={props.value}
          onChange={props.onChange}
          materialCode={props.materialCode}
          thicknessMm={props.thicknessMm}
        />
      )}
      renderViewport={(props) => (
        <WallShelfViewport parameters={props.parameters} thicknessMm={props.thicknessMm} />
      )}
    />
  );
}
