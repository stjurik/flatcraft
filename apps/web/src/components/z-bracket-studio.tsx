"use client";

import {
  ZBracketParametersSchema,
  type ZBracketParameters,
  type MaterialChoice,
} from "@flatcraft/types";
import { MaterialSection, useDebouncedValue, type MaterialSelection } from "@flatcraft/ui";
import { useMemo, useState } from "react";

import { ExportButton } from "./export-button";
import { ZBracketEditor } from "./z-bracket-editor";
import { ZBracketViewport } from "./z-bracket-viewport";

interface ZBracketStudioProps {
  readonly initialParameters: ZBracketParameters;
  readonly materials: ReadonlyArray<MaterialChoice>;
}

const VIEWPORT_DEBOUNCE_MS = 100;
const DEFAULT_MATERIAL_CODE = "cold_rolled_steel";
const DEFAULT_THICKNESS_MM = 2.0;

export function ZBracketStudio({ initialParameters, materials }: ZBracketStudioProps) {
  const [parameters, setParameters] = useState<ZBracketParameters>(initialParameters);
  const [material, setMaterial] = useState<MaterialSelection>({
    materialCode: DEFAULT_MATERIAL_CODE,
    thicknessMm: DEFAULT_THICKNESS_MM,
  });
  const debouncedParameters = useDebouncedValue(parameters, VIEWPORT_DEBOUNCE_MS);

  const isValid = useMemo(
    () => ZBracketParametersSchema.safeParse(parameters).success,
    [parameters],
  );

  return (
    <div data-testid="z-bracket-studio" className="flex flex-col gap-4">
      <div className="grid gap-6 lg:grid-cols-[1fr_2fr]">
        <div className="flex flex-col gap-4">
          <MaterialSection materials={materials} value={material} onChange={setMaterial} />
          <ZBracketEditor value={parameters} onChange={setParameters} />
          <ExportButton
            request={{
              template_slug: "z_bracket",
              parameters,
              material_code: material.materialCode,
              thickness_mm: material.thicknessMm,
            }}
            disabled={!isValid}
          />
        </div>

        <ZBracketViewport parameters={debouncedParameters} thicknessMm={material.thicknessMm} />
      </div>
    </div>
  );
}
