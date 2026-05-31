import type { ReactElement } from "react";

/**
 * Schematic SVG-thumbnails для каталога. Кожен — спрощений контур
 * виробу (НЕ точна геометрія — для впізнаваності у grid'і карток).
 * `stroke="currentColor"` дозволяє керувати тоном через `text-*` класи
 * на батькові (group-hover, theme tokens).
 *
 * Phase 2.13 — стартовий набір; реальні preview-PNG зʼявляться у
 * Phase 2.16 (R3F→canvas snapshot pipeline).
 */

const SVG_PROPS = {
  viewBox: "0 0 100 75",
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 3,
  strokeLinecap: "round",
  strokeLinejoin: "round",
  className: "h-24 w-32 sm:h-28 sm:w-36",
  role: "img",
  "aria-hidden": true,
} as const;

function LBracketThumb(): ReactElement {
  // Дві перпендикулярні полиці з малим радіусом гиба.
  return (
    <svg {...SVG_PROPS} data-testid="template-thumb-l_bracket">
      <path d="M 30 15 L 30 50 Q 30 55 35 55 L 75 55" />
    </svg>
  );
}

function ZBracketThumb(): ReactElement {
  // 3 секції з 2 гибами, Z-форма.
  return (
    <svg {...SVG_PROPS} data-testid="template-thumb-z_bracket">
      <path d="M 20 20 L 50 20 Q 55 20 55 25 L 55 50 Q 55 55 60 55 L 80 55" />
    </svg>
  );
}

function CornerAngleThumb(): ReactElement {
  // L + grid отворів на полицях (3 на горизонтальну, 3 на вертикальну).
  return (
    <svg {...SVG_PROPS} data-testid="template-thumb-corner_angle">
      <path d="M 25 15 L 25 55 L 75 55" />
      <circle cx="40" cy="55" r="2.5" fill="currentColor" stroke="none" />
      <circle cx="55" cy="55" r="2.5" fill="currentColor" stroke="none" />
      <circle cx="70" cy="55" r="2.5" fill="currentColor" stroke="none" />
      <circle cx="25" cy="25" r="2.5" fill="currentColor" stroke="none" />
      <circle cx="25" cy="35" r="2.5" fill="currentColor" stroke="none" />
      <circle cx="25" cy="45" r="2.5" fill="currentColor" stroke="none" />
    </svg>
  );
}

function WallShelfThumb(): ReactElement {
  // U-channel: back + shelf + front lip; mounting holes на back.
  return (
    <svg {...SVG_PROPS} data-testid="template-thumb-wall_shelf">
      <path d="M 25 15 L 25 50 Q 25 55 30 55 L 70 55 Q 75 55 75 50 L 75 40" />
      <circle cx="25" cy="25" r="2.5" fill="currentColor" stroke="none" />
      <circle cx="25" cy="35" r="2.5" fill="currentColor" stroke="none" />
    </svg>
  );
}

function PerforatedPanelThumb(): ReactElement {
  // Прямокутник + сітка 3×3 отворів.
  return (
    <svg {...SVG_PROPS} data-testid="template-thumb-perforated_panel">
      <rect x="15" y="15" width="70" height="45" rx="2" />
      {[27, 37.5, 48].map((cy) =>
        [30, 50, 70].map((cx) => (
          <circle key={`${cx}-${cy}`} cx={cx} cy={cy} r="2.5" fill="currentColor" stroke="none" />
        )),
      )}
    </svg>
  );
}

function FallbackThumb(): ReactElement {
  // Generic квадрат — для будь-якого slug поза 5 MVP-шаблонами.
  return (
    <svg {...SVG_PROPS} data-testid="template-thumb-fallback">
      <rect x="20" y="15" width="60" height="45" rx="2" />
    </svg>
  );
}

const REGISTRY: Record<string, () => ReactElement> = {
  l_bracket: LBracketThumb,
  z_bracket: ZBracketThumb,
  corner_angle: CornerAngleThumb,
  wall_shelf: WallShelfThumb,
  perforated_panel: PerforatedPanelThumb,
};

interface TemplateThumbProps {
  readonly slug: string;
}

export function TemplateThumb({ slug }: TemplateThumbProps) {
  const Thumb = REGISTRY[slug] ?? FallbackThumb;
  return <Thumb />;
}
