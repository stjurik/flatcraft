"use client";

import { validateProfile } from "@flatcraft/cad-engine";
import type { CornerAngleParameters } from "@flatcraft/types";
import { R3FErrorBoundary } from "@flatcraft/ui";
import dynamic from "next/dynamic";

import { InvalidParametersFallback } from "./invalid-parameters-fallback";

const Scene = dynamic(() => import("@flatcraft/ui").then((m) => m.CornerAngleScene), {
  ssr: false,
  loading: () => (
    <div
      data-testid="corner-angle-viewport-loading"
      className="text-fg-muted flex h-full w-full items-center justify-center text-sm"
    >
      Завантаження 3D…
    </div>
  ),
});

interface CornerAngleViewportProps {
  readonly parameters: CornerAngleParameters;
  readonly thicknessMm: number;
}

export function CornerAngleViewport({ parameters, thicknessMm }: CornerAngleViewportProps) {
  // Render-gate (ADR-026): не монтуємо <Canvas> при невалідній геометрії —
  // інакше build*ShapeCommands кидає throw → R3F-крах. ErrorBoundary — backstop.
  const issues = validateProfile({ templateSlug: "corner_angle", parameters, thicknessMm });
  return (
    <div
      id="studio-viewport"
      data-testid="corner-angle-viewport"
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
