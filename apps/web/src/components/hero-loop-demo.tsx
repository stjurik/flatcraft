"use client";

import { Activity, LBracketScene, useReducedMotion } from "@flatcraft/ui";
import { useEffect, useRef, useState } from "react";

import { HERO_LOOP_PERIOD_MS, nextDemoParams } from "../lib/hero-loop";

const DESKTOP_TICK_MS = 100;
const MOBILE_TICK_MS = 200;
const MOBILE_MQ = "(max-width: 767px)";

/**
 * Hero loop-демо: live 3D-перегляд, що автоматично прокручує L-кронштейн
 * через 4 параметричні фази (legA → legB → bend_radius → width).
 *
 * Performance — узгоджено з R-02 (mobile = спрощено):
 *   - desktop: tick 100мс (10fps на state updates), геометрія перебудовується.
 *   - mobile (≤767px): tick 200мс, удвічі менше rebuild'ів.
 * RAF просто chooses next-eligible tick; setState відбувається ТІЛЬКИ якщо
 * минув tick-інтервал, інакше re-schedule без re-render.
 *
 * Hover паузує (cancelAnimationFrame). Touch — без паузи (mobile не має
 * hover). prefers-reduced-motion — не запускає RAF взагалі, рендерить
 * статичний бракет за початковими параметрами.
 */
export function HeroLoopDemo() {
  const reduced = useReducedMotion();
  const [params, setParams] = useState(() => nextDemoParams(0));
  const pausedRef = useRef(false);

  useEffect(() => {
    if (reduced) return;
    if (typeof window === "undefined" || typeof window.requestAnimationFrame !== "function") return;

    const isMobile =
      typeof window.matchMedia === "function" && window.matchMedia(MOBILE_MQ).matches;
    const tickMs = isMobile ? MOBILE_TICK_MS : DESKTOP_TICK_MS;

    const start = performance.now();
    let lastTick = start;
    let raf = 0;

    const loop = (now: number) => {
      if (!pausedRef.current && now - lastTick >= tickMs) {
        lastTick = now;
        setParams(nextDemoParams((now - start) % HERO_LOOP_PERIOD_MS));
      }
      raf = window.requestAnimationFrame(loop);
    };
    raf = window.requestAnimationFrame(loop);
    return () => window.cancelAnimationFrame(raf);
  }, [reduced]);

  return (
    <div
      className="relative h-full w-full"
      onMouseEnter={() => {
        pausedRef.current = true;
      }}
      onMouseLeave={() => {
        pausedRef.current = false;
      }}
      data-testid="hero-loop-demo"
      data-reduced-motion={reduced ? "true" : "false"}
    >
      <span
        data-testid="hero-loop-badge"
        className="bg-bg-elevated border-border text-fg-muted rounded-xs absolute left-3 top-3 z-10 inline-flex items-center gap-1.5 border px-2 py-1 text-xs font-medium uppercase tracking-wide"
      >
        <Activity className="h-3 w-3" aria-hidden="true" />
        Live demo
      </span>

      <div
        className="h-full w-full"
        role="img"
        aria-label="Демо: автоматична зміна параметрів L-кронштейна"
      >
        <LBracketScene parameters={params} thicknessMm={2.0} />
      </div>

      {reduced ? (
        <p
          data-testid="hero-loop-reduced-caption"
          className="bg-bg-elevated/90 text-fg-muted absolute bottom-3 left-3 right-3 rounded-sm px-3 py-2 text-xs"
        >
          Параметри інтерактивні у редакторі — а тут показуємо статичний бракет (ваш браузер просить
          менше анімації).
        </p>
      ) : null}
    </div>
  );
}
