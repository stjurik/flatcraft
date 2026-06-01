"use client";

import type { PerforatedPanelParameters } from "@flatcraft/types";
import dynamic from "next/dynamic";

const Scene = dynamic(() => import("@flatcraft/ui").then((m) => m.PerforatedPanelScene), {
  ssr: false,
  loading: () => (
    <div
      data-testid="perforated-panel-viewport-loading"
      className="text-fg-muted flex h-full w-full items-center justify-center text-sm"
    >
      Завантаження 3D…
    </div>
  ),
});

interface PerforatedPanelViewportProps {
  readonly parameters: PerforatedPanelParameters;
  readonly thicknessMm: number;
}

export function PerforatedPanelViewport(props: PerforatedPanelViewportProps) {
  return (
    <div
      id="studio-viewport"
      data-testid="perforated-panel-viewport"
      className="border-border bg-surface-sunken aspect-video w-full scroll-mt-20 overflow-hidden rounded-md border"
    >
      <Scene {...props} />
    </div>
  );
}
