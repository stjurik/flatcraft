/**
 * Pure driver для `HeroLoopDemo`. Детермінований 16-секундний цикл, що
 * прокручує L-кронштейн через 4 параметричні фази:
 *
 *   0–4с    legA  50 → 200мм (linear)
 *   4–8с    legB  50 → 200мм (legA замикнуто на 200)
 *   8–12с   bend_radius переходить по RADII = [1, 2.5, 4, 5] (1с на крок)
 *  12–16с   width 100 → 300мм (radius замикнутий на 5)
 *
 * Розрахунок чистий — без RAF, без React. Викликається driver-ом у
 * `hero-loop-demo.tsx` на кожен tick з `t = (now - start) % PERIOD`.
 */
import { L_BRACKET_DEFAULT_PARAMETERS, type LBracketParameters } from "@flatcraft/types";

export const HERO_LOOP_PERIOD_MS = 16_000;

const PHASE_LEGA_END_MS = 4_000;
const PHASE_LEGB_END_MS = 8_000;
const PHASE_RADIUS_END_MS = 12_000;

/** Допустимі радіуси з L-bracket Zod-схеми (CLAUDE.md §7). */
const RADII = [1, 2.5, 4, 5] as const;
type Radius = (typeof RADII)[number];

function lerp(from: number, to: number, t01: number): number {
  return from + (to - from) * t01;
}

export function nextDemoParams(tMs: number): LBracketParameters {
  const phase = ((tMs % HERO_LOOP_PERIOD_MS) + HERO_LOOP_PERIOD_MS) % HERO_LOOP_PERIOD_MS;

  if (phase < PHASE_LEGA_END_MS) {
    return {
      ...L_BRACKET_DEFAULT_PARAMETERS,
      legA_mm: lerp(50, 200, phase / PHASE_LEGA_END_MS),
      legB_mm: 50,
      bend_radius_mm: 2.5,
      width_mm: 100,
    };
  }

  if (phase < PHASE_LEGB_END_MS) {
    return {
      ...L_BRACKET_DEFAULT_PARAMETERS,
      legA_mm: 200,
      legB_mm: lerp(50, 200, (phase - PHASE_LEGA_END_MS) / 4_000),
      bend_radius_mm: 2.5,
      width_mm: 100,
    };
  }

  if (phase < PHASE_RADIUS_END_MS) {
    // 4 рівних step'и по 1с: idx 0..3 → RADII[0..3].
    const stepIdx = Math.min(3, Math.floor((phase - PHASE_LEGB_END_MS) / 1_000));
    const radius: Radius = RADII[stepIdx] ?? RADII[0];
    return {
      ...L_BRACKET_DEFAULT_PARAMETERS,
      legA_mm: 200,
      legB_mm: 200,
      bend_radius_mm: radius,
      width_mm: 100,
    };
  }

  // Фаза 4: width 100→300, інше "застигло" в кінці фази 3.
  return {
    ...L_BRACKET_DEFAULT_PARAMETERS,
    legA_mm: 200,
    legB_mm: 200,
    bend_radius_mm: 5,
    width_mm: lerp(100, 300, (phase - PHASE_RADIUS_END_MS) / 4_000),
  };
}
