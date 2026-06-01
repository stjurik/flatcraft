/**
 * Адаптивна матриця для 3D-сцен (Phase 2.14, R-02 mitigation).
 *
 * Pure helper — не залежить від React. Споживачі викликають `useIsMobile`
 * + `useReducedMotion` хуки і передають їх result сюди.
 *
 * Чому 3 рівні (desktop / mobile / reduced):
 *  - desktop: full quality, користувач має GPU і не скаржиться на анімацію.
 *  - mobile: dpr cap [1, 1.5] (інакше retina × pixelRatio=3 = 9× pixel load),
 *    `enableZoom=false` запобігає конфлікту pinch-zoom 3D ↔ pinch-zoom сторінки
 *    на iOS Safari (інакше canvas-area недоступна для зум-сторінки).
 *  - reduced-motion: користувач явно просив менше руху (часто vestibular
 *    sensitivity або low-end девайс) → найжорсткіша економія: dpr [1, 1],
 *    rotate disabled, найдовший debounce.
 *
 * `curveSegments` — параметр three.js `ExtrudeGeometry` (default 12); знижує
 * детал bend-арки. Phase 2.14.a: вживається тільки у L-bracket scene
 * (інші 4 рендеряться як BoxGeometry без arcs — round-bend rewrite у 2.14.b).
 */

export interface ViewportQuality {
  /** [min, max] DPR — Canvas обмежує pixelRatio у цей діапазон. */
  readonly dpr: readonly [number, number];
  /** OrbitControls scroll/pinch-zoom. На mobile вимикаємо — конфлікт з браузером. */
  readonly enableZoom: boolean;
  /** OrbitControls drag-rotate. reduce-motion вимикає рух камери. */
  readonly enableRotate: boolean;
  /** Затримка `useDebouncedValue` між input → mesh rebuild. */
  readonly debounceMs: number;
  /** three.js `ExtrudeGeometry({ curveSegments })` — детал bend-арки. */
  readonly curveSegments: number;
}

export interface ViewportQualityInput {
  readonly isMobile: boolean;
  readonly reduced: boolean;
}

export function viewportQuality({ isMobile, reduced }: ViewportQualityInput): ViewportQuality {
  // reduced-motion має пріоритет — користувач явно вимагає менше руху,
  // незалежно від того, чи це mobile, чи desktop.
  if (reduced) {
    return {
      dpr: [1, 1],
      enableZoom: false,
      enableRotate: false,
      debounceMs: 400,
      curveSegments: 6,
    };
  }
  if (isMobile) {
    return {
      dpr: [1, 1.5],
      enableZoom: false,
      enableRotate: true,
      debounceMs: 250,
      curveSegments: 8,
    };
  }
  return {
    dpr: [1, 2],
    enableZoom: true,
    enableRotate: true,
    debounceMs: 100,
    curveSegments: 12,
  };
}
