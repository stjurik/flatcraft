"use client";

import {
  WallShelfParametersSchema,
  type WallShelfParameters,
  type MaterialChoice,
} from "@flatcraft/types";
import { MaterialSection, useDebouncedValue, type MaterialSelection } from "@flatcraft/ui";
import { useMemo, useState } from "react";

import { ExportButton } from "./export-button";
import { WallShelfEditor } from "./wall-shelf-editor";
import { WallShelfViewport } from "./wall-shelf-viewport";

interface WallShelfStudioProps {
  readonly initialParameters: WallShelfParameters;
  readonly materials: ReadonlyArray<MaterialChoice>;
}

const VIEWPORT_DEBOUNCE_MS = 100;
const DEFAULT_MATERIAL_CODE = "cold_rolled_steel";
const DEFAULT_THICKNESS_MM = 2.0;

export function WallShelfStudio({ initialParameters, materials }: WallShelfStudioProps) {
  const [parameters, setParameters] = useState<WallShelfParameters>(initialParameters);
  const [material, setMaterial] = useState<MaterialSelection>({
    materialCode: DEFAULT_MATERIAL_CODE,
    thicknessMm: DEFAULT_THICKNESS_MM,
  });
  const debouncedParameters = useDebouncedValue(parameters, VIEWPORT_DEBOUNCE_MS);

  const isValid = useMemo(
    () => WallShelfParametersSchema.safeParse(parameters).success,
    [parameters],
  );

  return (
    <div data-testid="wall-shelf-studio" className="flex flex-col gap-4">
      <div className="grid gap-6 lg:grid-cols-[1fr_2fr]">
        <div className="flex flex-col gap-4">
          <MaterialSection materials={materials} value={material} onChange={setMaterial} />
          <WallShelfEditor value={parameters} onChange={setParameters} />
          <ExportButton
            request={{
              template_slug: "wall_shelf",
              parameters,
              material_code: material.materialCode,
              thickness_mm: material.thicknessMm,
            }}
            disabled={!isValid}
          />
        </div>

        <WallShelfViewport parameters={debouncedParameters} thicknessMm={material.thicknessMm} />
      </div>
    </div>
  );
}
