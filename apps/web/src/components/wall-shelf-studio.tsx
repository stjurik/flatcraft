"use client";

import { validateProfile } from "@flatcraft/cad-engine";
import {
  WallShelfParametersSchema,
  type WallShelfParameters,
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
import { WallShelfEditor } from "./wall-shelf-editor";
import { WallShelfViewport } from "./wall-shelf-viewport";

interface WallShelfStudioProps {
  readonly initialParameters: WallShelfParameters;
  readonly materials: ReadonlyArray<MaterialChoice>;
}

const DEFAULT_MATERIAL_CODE = "cold_rolled_steel";
const DEFAULT_THICKNESS_MM = 2.0;

export function WallShelfStudio({ initialParameters, materials }: WallShelfStudioProps) {
  const [parameters, setParameters] = useState<WallShelfParameters>(initialParameters);
  const [material, setMaterial] = useState<MaterialSelection>({
    materialCode: DEFAULT_MATERIAL_CODE,
    thicknessMm: DEFAULT_THICKNESS_MM,
  });
  const isMobile = useIsMobile();
  const reduced = useReducedMotion();
  const quality = useMemo(() => viewportQuality({ isMobile, reduced }), [isMobile, reduced]);
  const debouncedParameters = useDebouncedValue(parameters, quality.debounceMs);

  const isValid = useMemo(
    () => WallShelfParametersSchema.safeParse(parameters).success,
    [parameters],
  );

  // Hotfix 2.9.c: матричні помилки блокують експорт ще до запиту (UX-gate).
  const matrixIssues = useMemo(
    () =>
      bendMatrixIssues({
        template_slug: "wall_shelf",
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
        templateSlug: "wall_shelf",
        parameters,
        thicknessMm: material.thicknessMm,
      }),
    [parameters, material.thicknessMm],
  );

  return (
    <div data-testid="wall-shelf-studio" className="flex flex-col gap-4">
      <div className="grid gap-6 lg:grid-cols-[1fr_2fr]">
        <div className="flex flex-col gap-4">
          <MaterialSection materials={materials} value={material} onChange={setMaterial} />
          <StudioPreviewAnchor />
          <WallShelfEditor
            value={parameters}
            onChange={setParameters}
            materialCode={material.materialCode}
            thicknessMm={material.thicknessMm}
          />
          <ExportButton
            request={{
              template_slug: "wall_shelf",
              parameters,
              material_code: material.materialCode,
              thickness_mm: material.thicknessMm,
            }}
            disabled={!isValid || matrixIssues.length > 0 || profileIssues.length > 0}
          />
        </div>

        <WallShelfViewport parameters={debouncedParameters} thicknessMm={material.thicknessMm} />
      </div>
    </div>
  );
}
