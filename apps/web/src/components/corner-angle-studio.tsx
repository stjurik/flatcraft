"use client";

import { CornerAngleParametersSchema, type CornerAngleParameters } from "@flatcraft/types";
import { useDebouncedValue } from "@flatcraft/ui";
import { useMemo, useState } from "react";

import { CornerAngleEditor } from "./corner-angle-editor";
import { CornerAngleViewport } from "./corner-angle-viewport";
import { ExportButton } from "./export-button";

interface CornerAngleStudioProps {
  readonly initialParameters: CornerAngleParameters;
}

const VIEWPORT_DEBOUNCE_MS = 100;

export function CornerAngleStudio({ initialParameters }: CornerAngleStudioProps) {
  const [parameters, setParameters] = useState<CornerAngleParameters>(initialParameters);
  const debouncedParameters = useDebouncedValue(parameters, VIEWPORT_DEBOUNCE_MS);
  const thicknessMm = 2.0;

  const isValid = useMemo(
    () => CornerAngleParametersSchema.safeParse(parameters).success,
    [parameters],
  );

  return (
    <div data-testid="corner-angle-studio" className="flex flex-col gap-4">
      <div className="grid gap-6 lg:grid-cols-[1fr_2fr]">
        <div className="flex flex-col gap-4 rounded-2xl border border-zinc-800 bg-zinc-900/40 p-5">
          <h2 className="text-lg font-semibold text-zinc-100">Параметри</h2>
          <CornerAngleEditor value={parameters} onChange={setParameters} />
          <ExportButton
            request={{
              template_slug: "corner_angle",
              parameters,
              thickness_mm: thicknessMm,
            }}
            disabled={!isValid}
          />
        </div>

        <CornerAngleViewport parameters={debouncedParameters} thicknessMm={thicknessMm} />
      </div>
    </div>
  );
}
