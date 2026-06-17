"use client";

import { validateProfile } from "@flatcraft/cad-engine";
import type { LBracketParameters } from "@flatcraft/types";
import { R3FErrorBoundary } from "@flatcraft/ui";
import dynamic from "next/dynamic";

import { InvalidParametersFallback } from "./invalid-parameters-fallback";

// LBracketScene з @flatcraft/ui — "use client", але three.js потребує
// браузерний WebGL. dynamic(ssr:false) робить server skip, scene вантажиться
// тільки після hydration.
const Scene = dynamic(() => import("@flatcraft/ui").then((m) => m.LBracketScene), {
  ssr: false,
  loading: () => (
    <div
      data-testid="l-bracket-viewport-loading"
      className="text-fg-muted flex h-full w-full items-center justify-center text-sm"
    >
      Завантаження 3D…
    </div>
  ),
});

interface LBracketViewportProps {
  readonly parameters: LBracketParameters;
  readonly thicknessMm: number;
}

export function LBracketViewport({ parameters, thicknessMm }: LBracketViewportProps) {
  // Render-gate (ADR-026): не монтуємо <Canvas> при невалідній геометрії.
  const issues = validateProfile({ templateSlug: "l_bracket", parameters, thicknessMm });
  return (
    <div
      id="studio-viewport"
      data-testid="l-bracket-viewport"
      className="border-border bg-surface-sunken aspect-video w-full scroll-mt-20 overflow-hidden rounded-md border"
    >
      {issues.length > 0 ? (
        <InvalidParametersFallback issues={issues} />
      ) : (
        <R3FErrorBoundary>
          <Scene parameters={parameters} thicknessMm={thicknessMm} />
        </R3FErrorBoundary>
      )}
    </div>
  );
}
