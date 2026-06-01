"use client";

import type { WallShelfParameters } from "@flatcraft/types";
import dynamic from "next/dynamic";

const Scene = dynamic(() => import("@flatcraft/ui").then((m) => m.WallShelfScene), {
  ssr: false,
  loading: () => (
    <div
      data-testid="wall-shelf-viewport-loading"
      className="text-fg-muted flex h-full w-full items-center justify-center text-sm"
    >
      Завантаження 3D…
    </div>
  ),
});

interface WallShelfViewportProps {
  readonly parameters: WallShelfParameters;
  readonly thicknessMm: number;
}

export function WallShelfViewport(props: WallShelfViewportProps) {
  return (
    <div
      id="studio-viewport"
      data-testid="wall-shelf-viewport"
      className="border-border bg-surface-sunken aspect-video w-full scroll-mt-20 overflow-hidden rounded-md border"
    >
      <Scene {...props} />
    </div>
  );
}
