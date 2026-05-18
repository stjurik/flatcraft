"use client";

import type { WallShelfParameters } from "@flatcraft/types";
import dynamic from "next/dynamic";

const Scene = dynamic(() => import("@flatcraft/ui").then((m) => m.WallShelfScene), {
  ssr: false,
  loading: () => (
    <div
      data-testid="wall-shelf-viewport-loading"
      className="flex h-full w-full items-center justify-center text-sm text-zinc-500"
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
      data-testid="wall-shelf-viewport"
      className="aspect-video w-full overflow-hidden rounded-2xl border border-zinc-800 bg-zinc-950/60"
    >
      <Scene {...props} />
    </div>
  );
}
