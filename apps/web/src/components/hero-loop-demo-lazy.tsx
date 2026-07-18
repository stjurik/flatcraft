"use client";

import dynamic from "next/dynamic";

import { DEFAULT_LOCALE, type Locale } from "../i18n/locale";

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

interface HeroLoopDemoLazyProps {
  readonly locale?: Locale;
}

export function HeroLoopDemoLazy({ locale = DEFAULT_LOCALE }: HeroLoopDemoLazyProps = {}) {
  return <HeroLoopDemoInner locale={locale} />;
}
