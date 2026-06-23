"use client";

import type { EnclosedShelfParameters } from "@flatcraft/types";
import dynamic from "next/dynamic";

const Scene = dynamic(() => import("@flatcraft/ui").then((m) => m.EnclosedShelfScene), {
  ssr: false,
  loading: () => (
    <div
      data-testid="enclosed-shelf-viewport-loading"
      className="text-fg-muted flex h-full w-full items-center justify-center text-sm"
    >
      Завантаження 3D…
    </div>
  ),
});

interface EnclosedShelfViewportProps {
  readonly parameters: EnclosedShelfParameters;
  readonly thicknessMm: number;
}

export function EnclosedShelfViewport(props: EnclosedShelfViewportProps) {
  return (
    <div
      id="studio-viewport"
      data-testid="enclosed-shelf-viewport"
      className="border-border bg-surface-sunken aspect-video w-full scroll-mt-20 overflow-hidden rounded-md border"
    >
      <Scene {...props} />
    </div>
  );
}
