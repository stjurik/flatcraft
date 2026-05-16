"use client";

import type { LBracketParameters } from "@flatcraft/types";
import dynamic from "next/dynamic";

// LBracketScene з @flatcraft/ui — "use client", але three.js потребує
// браузерний WebGL. dynamic(ssr:false) робить server skip, scene вантажиться
// тільки після hydration.
const Scene = dynamic(() => import("@flatcraft/ui").then((m) => m.LBracketScene), {
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
