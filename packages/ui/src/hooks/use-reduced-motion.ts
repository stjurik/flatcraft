"use client";

import { useEffect, useState } from "react";

const QUERY = "(prefers-reduced-motion: reduce)";

/**
 * Слідкує за CSS media query `prefers-reduced-motion: reduce`.
 *
 * SSR safety: на сервері повертає `false` (стартова анімація запуститься,
 * потім client одразу перерахує). Це краще, ніж приховати hero на сервері
 * і викликати layout shift.
 *
 * Споживачі (наприклад, `HeroLoopDemo`) використовують прапор, щоб НЕ
 * запускати RAF при reduced-motion і рендерити статичний стан.
 */
export function useReducedMotion(): boolean {
  const [reduced, setReduced] = useState(false);

  useEffect(() => {
    if (typeof window === "undefined" || typeof window.matchMedia !== "function") return;
    const mq = window.matchMedia(QUERY);
    const update = () => setReduced(mq.matches);
    update();
    // Safari < 14 не має addEventListener на MediaQueryList — fallback
    // до deprecated addListener.
    if (typeof mq.addEventListener === "function") {
      mq.addEventListener("change", update);
      return () => mq.removeEventListener("change", update);
    }
    mq.addListener(update);
    return () => mq.removeListener(update);
  }, []);

  return reduced;
}
