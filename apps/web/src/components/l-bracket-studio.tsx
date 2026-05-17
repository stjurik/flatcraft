"use client";

import type { LBracketParameters } from "@flatcraft/types";
import { useDebouncedValue } from "@flatcraft/ui";
import { useState } from "react";

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

  return (
    <div data-testid="l-bracket-studio" className="grid gap-6 lg:grid-cols-[1fr_2fr]">
      <div className="rounded-2xl border border-zinc-800 bg-zinc-900/40 p-5">
        <h2 className="mb-4 text-lg font-semibold text-zinc-100">Параметри</h2>
        <LBracketEditor value={parameters} onChange={setParameters} />
      </div>

      <LBracketViewport parameters={debouncedParameters} thicknessMm={thicknessMm} />
    </div>
  );
}
