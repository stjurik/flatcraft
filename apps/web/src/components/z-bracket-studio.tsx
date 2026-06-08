"use client";

import {
  ZBracketParametersSchema,
  type ZBracketParameters,
  type MaterialChoice,
} from "@flatcraft/types";
import {
  MaterialSection,
  useDebouncedValue,
  useIsMobile,
  useReducedMotion,
  viewportQuality,
  type MaterialSelection,
} from "@flatcraft/ui";
import { useMemo, useState } from "react";

import { bendMatrixIssues } from "../lib/bend-matrix";

import { ExportButton } from "./export-button";
import { StudioPreviewAnchor } from "./studio-preview-anchor";
import { ZBracketEditor } from "./z-bracket-editor";
import { ZBracketViewport } from "./z-bracket-viewport";

interface ZBracketStudioProps {
  readonly initialParameters: ZBracketParameters;
  readonly materials: ReadonlyArray<MaterialChoice>;
}

const DEFAULT_MATERIAL_CODE = "cold_rolled_steel";
const DEFAULT_THICKNESS_MM = 2.0;

export function ZBracketStudio({ initialParameters, materials }: ZBracketStudioProps) {
  const [parameters, setParameters] = useState<ZBracketParameters>(initialParameters);
  const [material, setMaterial] = useState<MaterialSelection>({
    materialCode: DEFAULT_MATERIAL_CODE,
    thicknessMm: DEFAULT_THICKNESS_MM,
  });
  const isMobile = useIsMobile();
  const reduced = useReducedMotion();
  const quality = useMemo(() => viewportQuality({ isMobile, reduced }), [isMobile, reduced]);
  const debouncedParameters = useDebouncedValue(parameters, quality.debounceMs);

  const isValid = useMemo(
    () => ZBracketParametersSchema.safeParse(parameters).success,
    [parameters],
  );

  // Hotfix 2.9.c: матричні помилки блокують експорт ще до запиту (UX-gate).
  const matrixIssues = useMemo(
    () =>
      bendMatrixIssues({
        template_slug: "z_bracket",
        parameters,
        material_code: material.materialCode,
        thickness_mm: material.thicknessMm,
      }),
    [parameters, material.materialCode, material.thicknessMm],
  );

  return (
    <div data-testid="z-bracket-studio" className="flex flex-col gap-4">
      <div className="grid gap-6 lg:grid-cols-[1fr_2fr]">
        <div className="flex flex-col gap-4">
          <MaterialSection materials={materials} value={material} onChange={setMaterial} />
          <StudioPreviewAnchor />
          <ZBracketEditor
            value={parameters}
            onChange={setParameters}
            materialCode={material.materialCode}
            thicknessMm={material.thicknessMm}
          />
          <ExportButton
            request={{
              template_slug: "z_bracket",
              parameters,
              material_code: material.materialCode,
              thickness_mm: material.thicknessMm,
            }}
            disabled={!isValid || matrixIssues.length > 0}
          />
        </div>

        <ZBracketViewport parameters={debouncedParameters} thicknessMm={material.thicknessMm} />
      </div>
    </div>
  );
}
