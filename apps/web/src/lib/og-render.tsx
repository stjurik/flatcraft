/**
 * Спільний рендерер Open Graph image (ADR-037 §2 — EN-дзеркало без
 * дублювання Satori/font-boilerplate). Візуальний дизайн — Phase 2.16.a;
 * див. `apps/web/src/app/opengraph-image.tsx` для повного опису підходу.
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";

import { ImageResponse } from "next/og";

export const OG_SIZE = { width: 1200, height: 630 } as const;

// process.cwd() у Next.js server = корінь apps/web; шлях відповідає файловій структурі.
const FONTS_DIR = join(process.cwd(), "src/app/_og-fonts");

function loadFont(filename: string): Buffer {
  return readFileSync(join(FONTS_DIR, filename));
}

// Warm-industrial токени (Phase 2.11) як hex — Satori не парсить oklch().
const COLORS = {
  bg: "#faf6ec", // ≈ oklch(0.985 0.005 80)
  bgElevated: "#ffffff", // ≈ oklch(1 0 0)
  fg: "#2e2820", // ≈ oklch(0.22 0.015 50)
  fgMuted: "#766b5d", // ≈ oklch(0.42 0.012 50)
  fgSubtle: "#9b9285", // ≈ oklch(0.55 0.01 50)
  primary: "#d27a3a", // ≈ oklch(0.66 0.17 50) — ember
  border: "#dad3c4", // ≈ oklch(0.88 0.008 70)
  uaBlue: "#0057B7",
  uaYellow: "#FFD700",
} as const;

export interface OgImageText {
  readonly headline: string;
  readonly sub: string;
}

export function renderOgImage({ headline, sub }: OgImageText): ImageResponse {
  const [interRegular, interSemibold, interBold] = [
    loadFont("Inter-Regular.ttf"),
    loadFont("Inter-SemiBold.ttf"),
    loadFont("Inter-Bold.ttf"),
  ];

  return new ImageResponse(
    <div
      style={{
        width: "100%",
        height: "100%",
        display: "flex",
        flexDirection: "column",
        background: COLORS.bg,
        fontFamily: "Inter",
      }}
    >
      {/* Основний layout (2 колонки) */}
      <div
        style={{
          flex: 1,
          display: "flex",
          flexDirection: "row",
          padding: "72px 80px",
          gap: "48px",
        }}
      >
        {/* Ліворуч: hero текст */}
        <div
          style={{
            flex: 1,
            display: "flex",
            flexDirection: "column",
            justifyContent: "center",
          }}
        >
          {/* Wordmark hart.crimea.ua */}
          <div
            style={{
              display: "flex",
              alignItems: "baseline",
              fontSize: 36,
              color: COLORS.fg,
              marginBottom: 32,
            }}
          >
            <span style={{ fontWeight: 600 }}>hart</span>
            <span style={{ fontWeight: 400, color: COLORS.fgMuted }}>.crimea.ua</span>
          </div>

          <div
            style={{
              fontSize: 68,
              fontWeight: 700,
              lineHeight: 1.05,
              letterSpacing: -1.5,
              color: COLORS.fg,
              marginBottom: 28,
              display: "flex",
            }}
          >
            {headline}
          </div>

          <div
            style={{
              fontSize: 28,
              color: COLORS.fgMuted,
              lineHeight: 1.4,
              display: "flex",
            }}
          >
            {sub}
          </div>

          {/* Ember accent рисочка */}
          <div
            style={{
              width: 96,
              height: 4,
              background: COLORS.primary,
              marginTop: 32,
              borderRadius: 2,
            }}
          />
        </div>

        {/* Праворуч: схематичний L-bracket SVG */}
        <div
          style={{
            width: 380,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          <svg width="320" height="320" viewBox="0 0 100 100" fill="none">
            {/* Background-square (subtle) */}
            <rect
              x="6"
              y="6"
              width="88"
              height="88"
              rx="4"
              fill={COLORS.bgElevated}
              stroke={COLORS.border}
              strokeWidth="0.8"
            />
            {/* L-shape outline */}
            <path
              d="M 28 18 L 28 62 Q 28 70 36 70 L 78 70"
              stroke={COLORS.primary}
              strokeWidth="5"
              strokeLinecap="round"
              strokeLinejoin="round"
              fill="none"
            />
            {/* Невеликі індикатори отворів */}
            <circle cx="28" cy="30" r="2.5" fill={COLORS.fgSubtle} />
            <circle cx="28" cy="42" r="2.5" fill={COLORS.fgSubtle} />
            <circle cx="48" cy="70" r="2.5" fill={COLORS.fgSubtle} />
            <circle cx="60" cy="70" r="2.5" fill={COLORS.fgSubtle} />
          </svg>
        </div>
      </div>

      {/* UkraineStripe внизу — 4px height (×2 від продакшну для OG-видимості) */}
      <div
        style={{
          height: 4,
          display: "flex",
          flexDirection: "row",
        }}
      >
        <div style={{ flex: 1, background: COLORS.uaBlue }} />
        <div style={{ flex: 1, background: COLORS.uaYellow }} />
      </div>
    </div>,
    {
      ...OG_SIZE,
      fonts: [
        { name: "Inter", data: interRegular, weight: 400, style: "normal" },
        { name: "Inter", data: interSemibold, weight: 600, style: "normal" },
        { name: "Inter", data: interBold, weight: 700, style: "normal" },
      ],
    },
  );
}
