"use client";

import { validateProfile } from "@flatcraft/cad-engine";
import type { ZBracketParameters } from "@flatcraft/types";
import { R3FErrorBoundary } from "@flatcraft/ui";
import dynamic from "next/dynamic";

import { InvalidParametersFallback } from "./invalid-parameters-fallback";

const Scene = dynamic(() => import("@flatcraft/ui").then((m) => m.ZBracketScene), {
  ssr: false,
  loading: () => (
    <div
      data-testid="z-bracket-viewport-loading"
      className="text-fg-muted flex h-full w-full items-center justify-center text-sm"
    >
      Завантаження 3D…
    </div>
  ),
});

interface ZBracketViewportProps {
  readonly parameters: ZBracketParameters;
  readonly thicknessMm: number;
}

export function ZBracketViewport({ parameters, thicknessMm }: ZBracketViewportProps) {
  // Render-gate (ADR-026): не монтуємо <Canvas> при невалідній геометрії.
  const issues = validateProfile({ templateSlug: "z_bracket", parameters, thicknessMm });
  return (
    <div
      id="studio-viewport"
      data-testid="z-bracket-viewport"
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
