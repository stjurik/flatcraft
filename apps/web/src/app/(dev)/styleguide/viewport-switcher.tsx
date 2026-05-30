"use client";

import { useState } from "react";

const PRESETS = [360, 768, 1280] as const;
type Preset = (typeof PRESETS)[number];

/**
 * Floating bottom-right switcher: натиснувши кнопку, додає inline-border
 * на <body> через element.style.border. Дозволяє ВСЕРЕДИНІ десктопного
 * браузера побачити, як токени/breakpoints реагують на різні viewports
 * (рамка візуалізує бокс, а CSS-utility @media — ні).
 */
export function ViewportSwitcher() {
  const [active, setActive] = useState<Preset | null>(null);

  const apply = (preset: Preset | null) => {
    setActive(preset);
    const body = document.body;
    if (!preset) {
      body.style.maxWidth = "";
      body.style.borderLeft = "";
      body.style.borderRight = "";
      body.style.marginInline = "";
      return;
    }
    body.style.maxWidth = `${preset}px`;
    body.style.marginInline = "auto";
    body.style.borderLeft = "2px dashed oklch(var(--color-primary) / 0.8)";
    body.style.borderRight = "2px dashed oklch(var(--color-primary) / 0.8)";
  };

  return (
    <div
      data-testid="viewport-switcher"
      className="bg-bg-elevated ring-border-strong fixed bottom-4 right-4 z-50 flex items-center gap-1 rounded-md p-1 shadow-md ring-1"
    >
      <span className="text-fg-muted px-2 text-xs font-medium">Viewport</span>
      {PRESETS.map((preset) => (
        <button
          type="button"
          key={preset}
          onClick={() => apply(preset)}
          data-active={active === preset}
          className="text-fg duration-fast hover:bg-surface-muted data-[active=true]:bg-primary data-[active=true]:text-primary-foreground rounded-sm px-2 py-1 text-xs font-semibold transition-colors ease-out"
        >
          {preset}
        </button>
      ))}
      <button
        type="button"
        onClick={() => apply(null)}
        className="text-fg-muted duration-fast hover:bg-surface-muted rounded-sm px-2 py-1 text-xs font-semibold transition-colors ease-out"
      >
        full
      </button>
    </div>
  );
}
