"use client";

import { usePathname } from "next/navigation";

import { localeFromPathname, switchLocaleHref } from "../i18n/routes";
import { dictionaries } from "../i18n/dictionaries";

/**
 * Перемикач мови (ADR-037 §3) — Footer, 44px tap-target. Локаль читається з
 * pathname (`/en/*` → en), не з окремого стану. Поза дзеркаленим Etap
 * A-набором (`i18n/routes.ts`) не рендериться — уникає лінку на 404.
 */
export function LocaleSwitcher() {
  const pathname = usePathname();
  const currentLocale = localeFromPathname(pathname);
  const href = switchLocaleHref(pathname);
  if (!href) return null;

  const dict = dictionaries[currentLocale].common.localeSwitcher;
  const isUk = currentLocale === "uk";

  return (
    <a
      href={href}
      data-testid="locale-switcher"
      aria-label={isUk ? dict.toEnAria : dict.toUkAria}
      className="border-border text-fg-muted hover:text-fg hover:border-border-strong min-h-tap min-w-tap inline-flex items-center justify-center rounded-md border px-3 text-sm font-medium"
    >
      {isUk ? dict.toEnLabel : dict.toUkLabel}
    </a>
  );
}
