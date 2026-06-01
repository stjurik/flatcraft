"use client";

import type { ZBracketParameters } from "@flatcraft/types";
import dynamic from "next/dynamic";

const Scene = dynamic(() => import("@flatcraft/ui").then((m) => m.ZBracketScene), {
  ssr: false,
  loading: () => (
    <div
      data-testid="z-bracket-viewport-loading"
      className="text-fg-muted flex h-full w-full items-center justify-center text-sm"
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
      id="studio-viewport"
      data-testid="z-bracket-viewport"
      className="border-border bg-surface-sunken aspect-video w-full scroll-mt-20 overflow-hidden rounded-md border"
    >
      <Scene {...props} />
    </div>
  );
}
