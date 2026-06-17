"use client";

import { validateProfile } from "@flatcraft/cad-engine";
import {
  LBracketParametersSchema,
  type LBracketParameters,
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
import { LBracketEditor } from "./l-bracket-editor";
import { LBracketViewport } from "./l-bracket-viewport";
import { StudioPreviewAnchor } from "./studio-preview-anchor";

interface LBracketStudioProps {
  readonly initialParameters: LBracketParameters;
  readonly materials: ReadonlyArray<MaterialChoice>;
}

const DEFAULT_MATERIAL_CODE = "cold_rolled_steel";
const DEFAULT_THICKNESS_MM = 2.0;

/**
 * Lift-state контейнер для L-bracket: editor + viewport + material/thickness.
 *
 * Phase 2.14.a: debounce читається з `viewportQuality` — на mobile 250мс
 * (зменшує rebuild-rate у 2.5×), на desktop 100мс, при reduced-motion 400мс.
 */
export function LBracketStudio({ initialParameters, materials }: LBracketStudioProps) {
  const [parameters, setParameters] = useState<LBracketParameters>(initialParameters);
  const [material, setMaterial] = useState<MaterialSelection>({
    materialCode: DEFAULT_MATERIAL_CODE,
    thicknessMm: DEFAULT_THICKNESS_MM,
  });
  const isMobile = useIsMobile();
  const reduced = useReducedMotion();
  const quality = useMemo(() => viewportQuality({ isMobile, reduced }), [isMobile, reduced]);
  const debouncedParameters = useDebouncedValue(parameters, quality.debounceMs);

  const isValid = useMemo(
    () => LBracketParametersSchema.safeParse(parameters).success,
    [parameters],
  );

  // Hotfix 2.9.c: матричні помилки блокують експорт ще до запиту (UX-gate).
  const matrixIssues = useMemo(
    () =>
      bendMatrixIssues({
        template_slug: "l_bracket",
        parameters,
        material_code: material.materialCode,
        thickness_mm: material.thicknessMm,
      }),
    [parameters, material.materialCode, material.thicknessMm],
  );

  // Hotfix 2.9.f (ADR-026): геометрична валідність профілю блокує експорт.
  const profileIssues = useMemo(
    () =>
      validateProfile({ templateSlug: "l_bracket", parameters, thicknessMm: material.thicknessMm }),
    [parameters, material.thicknessMm],
  );

  return (
    <div data-testid="l-bracket-studio" className="flex flex-col gap-4">
      <div className="grid gap-6 lg:grid-cols-[1fr_2fr]">
        <div className="flex flex-col gap-4">
          <MaterialSection materials={materials} value={material} onChange={setMaterial} />
          <StudioPreviewAnchor />
          <LBracketEditor
            value={parameters}
            onChange={setParameters}
            materialCode={material.materialCode}
            thicknessMm={material.thicknessMm}
          />
          <ExportButton
            request={{
              template_slug: "l_bracket",
              parameters,
              material_code: material.materialCode,
              thickness_mm: material.thicknessMm,
            }}
            disabled={!isValid || matrixIssues.length > 0 || profileIssues.length > 0}
          />
        </div>

        <LBracketViewport parameters={debouncedParameters} thicknessMm={material.thicknessMm} />
      </div>
    </div>
  );
}
