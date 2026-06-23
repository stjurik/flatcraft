"use client";

import type { PerforatedPanelSquareParameters } from "@flatcraft/types";
import dynamic from "next/dynamic";

const Scene = dynamic(() => import("@flatcraft/ui").then((m) => m.PerforatedPanelSquareScene), {
  ssr: false,
  loading: () => (
    <div
      data-testid="perforated-panel-square-viewport-loading"
      className="text-fg-muted flex h-full w-full items-center justify-center text-sm"
    >
      Завантаження 3D…
    </div>
  ),
});

interface PerforatedPanelSquareViewportProps {
  readonly parameters: PerforatedPanelSquareParameters;
  readonly thicknessMm: number;
}

export function PerforatedPanelSquareViewport(props: PerforatedPanelSquareViewportProps) {
  return (
    <div
      id="studio-viewport"
      data-testid="perforated-panel-square-viewport"
      className="border-border bg-surface-sunken aspect-video w-full scroll-mt-20 overflow-hidden rounded-md border"
    >
      <Scene {...props} />
    </div>
  );
}
