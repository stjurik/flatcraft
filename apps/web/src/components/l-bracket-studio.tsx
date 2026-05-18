"use client";

import { LBracketParametersSchema, type LBracketParameters } from "@flatcraft/types";
import { useDebouncedValue } from "@flatcraft/ui";
import { useMemo, useState } from "react";

import { ExportButton } from "./export-button";
import { LBracketEditor } from "./l-bracket-editor";
import { LBracketViewport } from "./l-bracket-viewport";

interface LBracketStudioProps {
  readonly initialParameters: LBracketParameters;
}

const VIEWPORT_DEBOUNCE_MS = 100;

/**
 * Lift-state контейнер для L-bracket: редактор параметрів + 3D viewport
 * діляться одним state-ом.
 *
 * Editor читає live-параметри (instant input feedback + live-валідація).
 * Viewport отримує debounced-копію — ExtrudeGeometry-rebuild не блокує
 * клавіш-події при швидкому скролі чисел. 100мс = CLAUDE.md §9 поріг.
 *
 * thickness — Phase 3 додасть UI-вибір через MaterialPicker; поки 2.0
 * (CLAUDE.md §7 — мінімум типового діапазону для L-bracket).
 */
export function LBracketStudio({ initialParameters }: LBracketStudioProps) {
  const [parameters, setParameters] = useState<LBracketParameters>(initialParameters);
  const debouncedParameters = useDebouncedValue(parameters, VIEWPORT_DEBOUNCE_MS);
  const thicknessMm = 2.0;

  const isValid = useMemo(
    () => LBracketParametersSchema.safeParse(parameters).success,
    [parameters],
  );

  return (
    <div data-testid="l-bracket-studio" className="flex flex-col gap-4">
      <div className="grid gap-6 lg:grid-cols-[1fr_2fr]">
        <div className="flex flex-col gap-4 rounded-2xl border border-zinc-800 bg-zinc-900/40 p-5">
          <h2 className="text-lg font-semibold text-zinc-100">Параметри</h2>
          <LBracketEditor value={parameters} onChange={setParameters} />
          <ExportButton
            request={{
              template_slug: "l_bracket",
              parameters,
              thickness_mm: thicknessMm,
            }}
            disabled={!isValid}
          />
        </div>

        <LBracketViewport parameters={debouncedParameters} thicknessMm={thicknessMm} />
      </div>
    </div>
  );
}
