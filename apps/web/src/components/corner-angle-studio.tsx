"use client";

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

  return (
    <div data-testid="corner-angle-studio" className="flex flex-col gap-4">
      <div className="grid gap-6 lg:grid-cols-[1fr_2fr]">
        <div className="flex flex-col gap-4">
          <MaterialSection materials={materials} value={material} onChange={setMaterial} />
          <StudioPreviewAnchor />
          <CornerAngleEditor value={parameters} onChange={setParameters} />
          <ExportButton
            request={{
              template_slug: "corner_angle",
              parameters,
              material_code: material.materialCode,
              thickness_mm: material.thicknessMm,
            }}
            disabled={!isValid}
          />
        </div>

        <CornerAngleViewport parameters={debouncedParameters} thicknessMm={material.thicknessMm} />
      </div>
    </div>
  );
}
