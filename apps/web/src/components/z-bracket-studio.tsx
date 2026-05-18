"use client";

import { ZBracketParametersSchema, type ZBracketParameters } from "@flatcraft/types";
import { useDebouncedValue } from "@flatcraft/ui";
import { useMemo, useState } from "react";

import { ExportButton } from "./export-button";
import { ZBracketEditor } from "./z-bracket-editor";
import { ZBracketViewport } from "./z-bracket-viewport";

interface ZBracketStudioProps {
  readonly initialParameters: ZBracketParameters;
}

const VIEWPORT_DEBOUNCE_MS = 100;

/**
 * Lift-state контейнер для Z-bracket. Editor live, viewport debounced.
 * thickness — 2.0 поки немає MaterialPicker (Phase 3.5).
 */
export function ZBracketStudio({ initialParameters }: ZBracketStudioProps) {
  const [parameters, setParameters] = useState<ZBracketParameters>(initialParameters);
  const debouncedParameters = useDebouncedValue(parameters, VIEWPORT_DEBOUNCE_MS);
  const thicknessMm = 2.0;

  const isValid = useMemo(
    () => ZBracketParametersSchema.safeParse(parameters).success,
    [parameters],
  );

  return (
    <div data-testid="z-bracket-studio" className="flex flex-col gap-4">
      <div className="grid gap-6 lg:grid-cols-[1fr_2fr]">
        <div className="flex flex-col gap-4 rounded-2xl border border-zinc-800 bg-zinc-900/40 p-5">
          <h2 className="text-lg font-semibold text-zinc-100">Параметри</h2>
          <ZBracketEditor value={parameters} onChange={setParameters} />
          <ExportButton
            request={{
              template_slug: "z_bracket",
              parameters,
              thickness_mm: thicknessMm,
            }}
            disabled={!isValid}
          />
        </div>

        <ZBracketViewport parameters={debouncedParameters} thicknessMm={thicknessMm} />
      </div>
    </div>
  );
}
