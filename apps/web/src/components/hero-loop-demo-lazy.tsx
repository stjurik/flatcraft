"use client";

import dynamic from "next/dynamic";

/**
 * Dynamic ssr:false wrapper для `HeroLoopDemo` — R3F bundle важкий
 * (~300КБ gzip), вантажиться поза critical path. Skeleton — той самий
 * aspect-ratio, щоб уникнути CLS.
 */
const HeroLoopDemoInner = dynamic(() => import("./hero-loop-demo").then((m) => m.HeroLoopDemo), {
  ssr: false,
  loading: () => (
    <div
      aria-hidden="true"
      data-testid="hero-loop-skeleton"
      className="bg-surface-muted h-full w-full animate-pulse rounded-lg"
    />
  ),
});

export function HeroLoopDemoLazy() {
  return <HeroLoopDemoInner />;
}
