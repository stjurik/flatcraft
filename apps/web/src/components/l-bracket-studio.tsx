"use client";

import {
  LBracketParametersSchema,
  type LBracketParameters,
  type MaterialChoice,
} from "@flatcraft/types";
import { MaterialSection, useDebouncedValue, type MaterialSelection } from "@flatcraft/ui";
import { useMemo, useState } from "react";

import { ExportButton } from "./export-button";
import { LBracketEditor } from "./l-bracket-editor";
import { LBracketViewport } from "./l-bracket-viewport";

interface LBracketStudioProps {
  readonly initialParameters: LBracketParameters;
  readonly materials: ReadonlyArray<MaterialChoice>;
}

const VIEWPORT_DEBOUNCE_MS = 100;
const DEFAULT_MATERIAL_CODE = "cold_rolled_steel";
const DEFAULT_THICKNESS_MM = 2.0;

/**
 * Lift-state контейнер для L-bracket: editor + viewport + material/thickness.
 *
 * Phase 2.12: material+thickness — controlled state у студії, передається
 * у `<MaterialSection>` (зверху форми) і у ExportRequest (ADR-018).
 */
export function LBracketStudio({ initialParameters, materials }: LBracketStudioProps) {
  const [parameters, setParameters] = useState<LBracketParameters>(initialParameters);
  const [material, setMaterial] = useState<MaterialSelection>({
    materialCode: DEFAULT_MATERIAL_CODE,
    thicknessMm: DEFAULT_THICKNESS_MM,
  });
  const debouncedParameters = useDebouncedValue(parameters, VIEWPORT_DEBOUNCE_MS);

  const isValid = useMemo(
    () => LBracketParametersSchema.safeParse(parameters).success,
    [parameters],
  );

  return (
    <div data-testid="l-bracket-studio" className="flex flex-col gap-4">
      <div className="grid gap-6 lg:grid-cols-[1fr_2fr]">
        <div className="flex flex-col gap-4">
          <MaterialSection materials={materials} value={material} onChange={setMaterial} />
          <LBracketEditor value={parameters} onChange={setParameters} />
          <ExportButton
            request={{
              template_slug: "l_bracket",
              parameters,
              material_code: material.materialCode,
              thickness_mm: material.thicknessMm,
            }}
            disabled={!isValid}
          />
        </div>

        <LBracketViewport parameters={debouncedParameters} thicknessMm={material.thicknessMm} />
      </div>
    </div>
  );
}
