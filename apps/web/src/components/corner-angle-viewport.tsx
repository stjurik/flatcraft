"use client";

import type { CornerAngleParameters } from "@flatcraft/types";
import dynamic from "next/dynamic";

const Scene = dynamic(() => import("@flatcraft/ui").then((m) => m.CornerAngleScene), {
  ssr: false,
  loading: () => (
    <div
      data-testid="corner-angle-viewport-loading"
      className="flex h-full w-full items-center justify-center text-sm text-zinc-500"
    >
      Завантаження 3D…
    </div>
  ),
});

interface CornerAngleViewportProps {
  readonly parameters: CornerAngleParameters;
  readonly thicknessMm: number;
}

export function CornerAngleViewport(props: CornerAngleViewportProps) {
  return (
    <div
      data-testid="corner-angle-viewport"
      className="aspect-video w-full overflow-hidden rounded-2xl border border-zinc-800 bg-zinc-950/60"
    >
      <Scene {...props} />
    </div>
  );
}
