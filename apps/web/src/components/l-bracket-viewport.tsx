"use client";

import type { LBracketParameters } from "@flatcraft/types";
import dynamic from "next/dynamic";

const Scene = dynamic(() => import("./l-bracket-scene").then((m) => m.LBracketSceneInner), {
  ssr: false,
  loading: () => (
    <div
      data-testid="l-bracket-viewport-loading"
      className="flex h-full w-full items-center justify-center text-sm text-zinc-500"
    >
      Завантаження 3D…
    </div>
  ),
});

interface LBracketViewportProps {
  readonly parameters: LBracketParameters;
  readonly thicknessMm: number;
}

export function LBracketViewport(props: LBracketViewportProps) {
  return (
    <div
      data-testid="l-bracket-viewport"
      className="aspect-video w-full overflow-hidden rounded-2xl border border-zinc-800 bg-zinc-950/60"
    >
      <Scene {...props} />
    </div>
  );
}
