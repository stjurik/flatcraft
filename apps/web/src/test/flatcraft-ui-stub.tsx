/**
 * Vitest-стаб для `@flatcraft/ui` (Hotfix 2.9.c).
 *
 * Чому: барель `@flatcraft/ui` ре-експортує R3F 3d-viewport, а vitest (node, без
 * WebGL) резолвить пакет із `dist` — крихко щодо порядку turbo-build. Жоден web
 * unit-тест не вживає реальний `@flatcraft/ui`, окрім editor-wrapper тестів, яким
 * потрібні лише `AutoForm` (рендер-плейсхолдер) і `zodIssuesToFieldErrors`.
 *
 * Аліас на цей файл (apps/web/vitest.config.ts) робить резолюцію детермінованою
 * і незалежною від dist. Типи у typecheck беруться з РЕАЛЬНОГО пакета (tsc через
 * tsconfig paths → packages/ui/src), тож контракт лишається перевіреним.
 *
 * ⚠ Якщо майбутній web unit-тест потребуватиме справжній компонент із
 * `@flatcraft/ui` — приберіть/звузьте аліас і застабте конкретний підмодуль.
 */
import type { ReactNode } from "react";

export function AutoForm(): null {
  return null;
}

export function zodIssuesToFieldErrors(): Record<string, string> {
  return {};
}

// Hotfix 2.9.f (ADR-026): render-gate viewport-тести вживають R3FErrorBoundary.
// Стаб — passthrough (рендерить children); справжній boundary покритий у
// packages/ui (r3f-error-boundary.test.tsx).
export function R3FErrorBoundary({ children }: { children: ReactNode }): ReactNode {
  return children;
}

// Scene-компоненти вантажаться через dynamic(ssr:false) — у SSR-тесті
// рендериться loading-плейсхолдер, тож реальні Scene не потрібні. Стаб-плейсхолдери
// лише щоб `import("@flatcraft/ui").then(m => m.XScene)` мав визначене значення.
export function CornerAngleScene(): null {
  return null;
}
export function LBracketScene(): null {
  return null;
}
export function ZBracketScene(): null {
  return null;
}
export function WallShelfScene(): null {
  return null;
}
export function PerforatedPanelScene(): null {
  return null;
}
