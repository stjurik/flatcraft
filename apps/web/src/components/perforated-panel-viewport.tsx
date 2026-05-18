"use client";

import type { PerforatedPanelParameters } from "@flatcraft/types";
import dynamic from "next/dynamic";

const Scene = dynamic(() => import("@flatcraft/ui").then((m) => m.PerforatedPanelScene), {
  ssr: false,
  loading: () => (
    <div
      data-testid="perforated-panel-viewport-loading"
      className="flex h-full w-full items-center justify-center text-sm text-zinc-500"
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
      data-testid="perforated-panel-viewport"
      className="aspect-video w-full overflow-hidden rounded-2xl border border-zinc-800 bg-zinc-950/60"
    >
      <Scene {...props} />
    </div>
  );
}
