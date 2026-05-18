"use client";

import { PerforatedPanelParametersSchema, type PerforatedPanelParameters } from "@flatcraft/types";
import { useDebouncedValue } from "@flatcraft/ui";
import { useMemo, useState } from "react";

import { ExportButton } from "./export-button";
import { PerforatedPanelEditor } from "./perforated-panel-editor";
import { PerforatedPanelViewport } from "./perforated-panel-viewport";

interface PerforatedPanelStudioProps {
  readonly initialParameters: PerforatedPanelParameters;
}

const VIEWPORT_DEBOUNCE_MS = 100;

export function PerforatedPanelStudio({ initialParameters }: PerforatedPanelStudioProps) {
  const [parameters, setParameters] = useState<PerforatedPanelParameters>(initialParameters);
  const debouncedParameters = useDebouncedValue(parameters, VIEWPORT_DEBOUNCE_MS);
  const thicknessMm = 2.0;

  const isValid = useMemo(
    () => PerforatedPanelParametersSchema.safeParse(parameters).success,
    [parameters],
  );

  return (
    <div data-testid="perforated-panel-studio" className="flex flex-col gap-4">
      <div className="grid gap-6 lg:grid-cols-[1fr_2fr]">
        <div className="flex flex-col gap-4 rounded-2xl border border-zinc-800 bg-zinc-900/40 p-5">
          <h2 className="text-lg font-semibold text-zinc-100">Параметри</h2>
          <PerforatedPanelEditor value={parameters} onChange={setParameters} />
          <ExportButton
            request={{
              template_slug: "perforated_panel",
              parameters,
              thickness_mm: thicknessMm,
            }}
            disabled={!isValid}
          />
        </div>

        <PerforatedPanelViewport parameters={debouncedParameters} thicknessMm={thicknessMm} />
      </div>
    </div>
  );
}
