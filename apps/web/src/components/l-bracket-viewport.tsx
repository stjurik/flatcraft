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
      className="text-fg-muted flex h-full w-full items-center justify-center text-sm"
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
      id="studio-viewport"
      data-testid="l-bracket-viewport"
      className="border-border bg-surface-sunken aspect-video w-full scroll-mt-20 overflow-hidden rounded-md border"
    >
      <Scene {...props} />
    </div>
  );
}
