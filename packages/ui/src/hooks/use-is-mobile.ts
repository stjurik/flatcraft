"use client";

import { useEffect, useState } from "react";

const QUERY = "(max-width: 767px)";

/**
 * Слідкує за CSS media query `(max-width: 767px)` — наш mobile-baseline
 * (Phase 2.11 Tailwind breakpoint `md: 768px`).
 *
 * SSR safety: на сервері повертає `false` (desktop-first рендер); client
 * після hydration одразу перерахує. Це безпечніше за SSR-mobile, бо
 * desktop-build має повну якість і не обрізає функціонал.
 *
 * Парний близнюк до `useReducedMotion` — використовується разом у
 * `viewportQuality` (Phase 2.14, R-02 mitigation).
 */
export function useIsMobile(): boolean {
  const [isMobile, setIsMobile] = useState(false);

  useEffect(() => {
    if (typeof window === "undefined" || typeof window.matchMedia !== "function") return;
    const mq = window.matchMedia(QUERY);
    const update = () => setIsMobile(mq.matches);
    update();
    if (typeof mq.addEventListener === "function") {
      mq.addEventListener("change", update);
      return () => mq.removeEventListener("change", update);
    }
    mq.addListener(update);
    return () => mq.removeListener(update);
  }, []);

  return isMobile;
}
