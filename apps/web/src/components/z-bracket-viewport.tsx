"use client";

import type { ZBracketParameters } from "@flatcraft/types";
import dynamic from "next/dynamic";

const Scene = dynamic(() => import("@flatcraft/ui").then((m) => m.ZBracketScene), {
  ssr: false,
  loading: () => (
    <div
      data-testid="z-bracket-viewport-loading"
      className="flex h-full w-full items-center justify-center text-sm text-zinc-500"
    >
      Завантаження 3D…
    </div>
  ),
});

interface ZBracketViewportProps {
  readonly parameters: ZBracketParameters;
  readonly thicknessMm: number;
}

export function ZBracketViewport(props: ZBracketViewportProps) {
  return (
    <div
      data-testid="z-bracket-viewport"
      className="aspect-video w-full overflow-hidden rounded-2xl border border-zinc-800 bg-zinc-950/60"
    >
      <Scene {...props} />
    </div>
  );
}
