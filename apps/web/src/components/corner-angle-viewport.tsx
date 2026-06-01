"use client";

import type { CornerAngleParameters } from "@flatcraft/types";
import dynamic from "next/dynamic";

const Scene = dynamic(() => import("@flatcraft/ui").then((m) => m.CornerAngleScene), {
  ssr: false,
  loading: () => (
    <div
      data-testid="corner-angle-viewport-loading"
      className="text-fg-muted flex h-full w-full items-center justify-center text-sm"
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
      id="studio-viewport"
      data-testid="corner-angle-viewport"
      className="border-border bg-surface-sunken aspect-video w-full scroll-mt-20 overflow-hidden rounded-md border"
    >
      <Scene {...props} />
    </div>
  );
}
