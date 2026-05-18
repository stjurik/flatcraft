"use client";

import { WallShelfParametersSchema, type WallShelfParameters } from "@flatcraft/types";
import { useDebouncedValue } from "@flatcraft/ui";
import { useMemo, useState } from "react";

import { ExportButton } from "./export-button";
import { WallShelfEditor } from "./wall-shelf-editor";
import { WallShelfViewport } from "./wall-shelf-viewport";

interface WallShelfStudioProps {
  readonly initialParameters: WallShelfParameters;
}

const VIEWPORT_DEBOUNCE_MS = 100;

export function WallShelfStudio({ initialParameters }: WallShelfStudioProps) {
  const [parameters, setParameters] = useState<WallShelfParameters>(initialParameters);
  const debouncedParameters = useDebouncedValue(parameters, VIEWPORT_DEBOUNCE_MS);
  const thicknessMm = 2.0;

  const isValid = useMemo(
    () => WallShelfParametersSchema.safeParse(parameters).success,
    [parameters],
  );

  return (
    <div data-testid="wall-shelf-studio" className="flex flex-col gap-4">
      <div className="grid gap-6 lg:grid-cols-[1fr_2fr]">
        <div className="flex flex-col gap-4 rounded-2xl border border-zinc-800 bg-zinc-900/40 p-5">
          <h2 className="text-lg font-semibold text-zinc-100">Параметри</h2>
          <WallShelfEditor value={parameters} onChange={setParameters} />
          <ExportButton
            request={{
              template_slug: "wall_shelf",
              parameters,
              thickness_mm: thicknessMm,
            }}
            disabled={!isValid}
          />
        </div>

        <WallShelfViewport parameters={debouncedParameters} thicknessMm={thicknessMm} />
      </div>
    </div>
  );
}
