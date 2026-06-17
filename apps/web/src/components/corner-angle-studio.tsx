"use client";

import { validateProfile } from "@flatcraft/cad-engine";
import {
  CornerAngleParametersSchema,
  type CornerAngleParameters,
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

import { CornerAngleEditor } from "./corner-angle-editor";
import { CornerAngleViewport } from "./corner-angle-viewport";
import { ExportButton } from "./export-button";
import { StudioPreviewAnchor } from "./studio-preview-anchor";

interface CornerAngleStudioProps {
  readonly initialParameters: CornerAngleParameters;
  readonly materials: ReadonlyArray<MaterialChoice>;
}

const DEFAULT_MATERIAL_CODE = "cold_rolled_steel";
const DEFAULT_THICKNESS_MM = 2.0;

export function CornerAngleStudio({ initialParameters, materials }: CornerAngleStudioProps) {
  const [parameters, setParameters] = useState<CornerAngleParameters>(initialParameters);
  const [material, setMaterial] = useState<MaterialSelection>({
    materialCode: DEFAULT_MATERIAL_CODE,
    thicknessMm: DEFAULT_THICKNESS_MM,
  });
  const isMobile = useIsMobile();
  const reduced = useReducedMotion();
  const quality = useMemo(() => viewportQuality({ isMobile, reduced }), [isMobile, reduced]);
  const debouncedParameters = useDebouncedValue(parameters, quality.debounceMs);

  const isValid = useMemo(
    () => CornerAngleParametersSchema.safeParse(parameters).success,
    [parameters],
  );

  // Hotfix 2.9.c: матричні помилки блокують експорт ще до запиту (UX-gate).
  const matrixIssues = useMemo(
    () =>
      bendMatrixIssues({
        template_slug: "corner_angle",
        parameters,
        material_code: material.materialCode,
        thickness_mm: material.thicknessMm,
      }),
    [parameters, material.materialCode, material.thicknessMm],
  );

  // Hotfix 2.9.f (ADR-026): геометрична валідність профілю блокує експорт.
  const profileIssues = useMemo(
    () =>
      validateProfile({
        templateSlug: "corner_angle",
        parameters,
        thicknessMm: material.thicknessMm,
      }),
    [parameters, material.thicknessMm],
  );

  return (
    <div data-testid="corner-angle-studio" className="flex flex-col gap-4">
      <div className="grid gap-6 lg:grid-cols-[1fr_2fr]">
        <div className="flex flex-col gap-4">
          <MaterialSection materials={materials} value={material} onChange={setMaterial} />
          <StudioPreviewAnchor />
          <CornerAngleEditor
            value={parameters}
            onChange={setParameters}
            materialCode={material.materialCode}
            thicknessMm={material.thicknessMm}
          />
          <ExportButton
            request={{
              template_slug: "corner_angle",
              parameters,
              material_code: material.materialCode,
              thickness_mm: material.thicknessMm,
            }}
            disabled={!isValid || matrixIssues.length > 0 || profileIssues.length > 0}
          />
        </div>

        <CornerAngleViewport parameters={debouncedParameters} thicknessMm={material.thicknessMm} />
      </div>
    </div>
  );
}
