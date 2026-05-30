"use client";

import { useState } from "react";

/**
 * Демо motion-токенів: квадрат, який pulse-ується. Кнопка нижче
 * прокидає inline-style з `animation-duration: 0`, імітуючи ефект
 * @media (prefers-reduced-motion: reduce) — щоб локально подивитися,
 * що декоративна анімація справді знімається.
 */
export function MotionDemo() {
  const [reduced, setReduced] = useState(false);

  return (
    <div className="flex flex-col gap-3">
      <div
        data-testid="motion-square"
        className="bg-primary h-16 w-16 rounded-md"
        style={{
          animation: "pulse-soft 1.6s ease-in-out infinite",
          animationDuration: reduced ? "0ms" : undefined,
        }}
      />
      <style>{`
        @keyframes pulse-soft {
          0%, 100% { transform: scale(1); opacity: 1; }
          50%      { transform: scale(1.12); opacity: 0.7; }
        }
      `}</style>
      <button
        type="button"
        onClick={() => setReduced((r) => !r)}
        className="border-border-strong text-fg hover:bg-surface-sunken self-start rounded-sm border px-3 py-1 text-xs font-semibold"
      >
        {reduced ? "↻ Увімкнути анімацію" : "⏸ Імітувати reduced-motion"}
      </button>
    </div>
  );
}
