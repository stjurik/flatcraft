"use client";

import { useReportWebVitals } from "next/web-vitals";

import { track, webVitalProps } from "../lib/analytics";

/**
 * Репортер web-vitals (docs/11 §8) → custom-подія `web_vital` через `track`.
 * Core Web Vitals (LCP/CLS/INP/FCP/TTFB) звіряються з бюджетами CLAUDE.md §9
 * через `rating`. No-op без аналітики (track сам гейтить). Рендерить `null`.
 */
export function WebVitals() {
  useReportWebVitals((metric) => {
    track("web_vital", webVitalProps(metric));
  });
  return null;
}
