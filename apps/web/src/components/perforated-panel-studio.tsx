"use client";

import {
  PerforatedPanelParametersSchema,
  type PerforatedPanelParameters,
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

import { ExportButton } from "./export-button";
import { PerforatedPanelEditor } from "./perforated-panel-editor";
import { PerforatedPanelViewport } from "./perforated-panel-viewport";
import { StudioPreviewAnchor } from "./studio-preview-anchor";

interface PerforatedPanelStudioProps {
  readonly initialParameters: PerforatedPanelParameters;
  readonly materials: ReadonlyArray<MaterialChoice>;
}

const DEFAULT_MATERIAL_CODE = "cold_rolled_steel";
const DEFAULT_THICKNESS_MM = 2.0;

export function PerforatedPanelStudio({
  initialParameters,
  materials,
}: PerforatedPanelStudioProps) {
  const [parameters, setParameters] = useState<PerforatedPanelParameters>(initialParameters);
  const [material, setMaterial] = useState<MaterialSelection>({
    materialCode: DEFAULT_MATERIAL_CODE,
    thicknessMm: DEFAULT_THICKNESS_MM,
  });
  const isMobile = useIsMobile();
  const reduced = useReducedMotion();
  const quality = useMemo(() => viewportQuality({ isMobile, reduced }), [isMobile, reduced]);
  const debouncedParameters = useDebouncedValue(parameters, quality.debounceMs);

  const isValid = useMemo(
    () => PerforatedPanelParametersSchema.safeParse(parameters).success,
    [parameters],
  );

  return (
    <div data-testid="perforated-panel-studio" className="flex flex-col gap-4">
      <div className="grid gap-6 lg:grid-cols-[1fr_2fr]">
        <div className="flex flex-col gap-4">
          <MaterialSection materials={materials} value={material} onChange={setMaterial} />
          <StudioPreviewAnchor />
          <PerforatedPanelEditor value={parameters} onChange={setParameters} />
          <ExportButton
            request={{
              template_slug: "perforated_panel",
              parameters,
              material_code: material.materialCode,
              thickness_mm: material.thicknessMm,
            }}
            disabled={!isValid}
          />
        </div>

        <PerforatedPanelViewport
          parameters={debouncedParameters}
          thicknessMm={material.thicknessMm}
        />
      </div>
    </div>
  );
}
