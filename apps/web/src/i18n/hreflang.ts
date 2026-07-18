import type { Metadata } from "next";

import type { Locale } from "./locale";
import { toEnPath } from "./routes";

/**
 * Reciprocal hreflang alternates для пари локалізованих сторінок (ADR-037
 * §7 follow-up — Master Run 8 Стадія 3 зауваження). `x-default` = uk-шлях:
 * узгоджено з `DEFAULT_LOCALE` (ADR-037 §2 — uk дефолтна локаль сайту).
 * `canonical` — сама поточна локаль (кожна мовна версія канонічна сама на
 * себе, hreflang лише зв'язує їх як еквіваленти, не дублікати).
 */
export function localeAlternates(
  locale: Locale,
  ukPath: string,
  enPath: string,
): Metadata["alternates"] {
  return {
    canonical: locale === "en" ? enPath : ukPath,
    languages: {
      uk: ukPath,
      en: enPath,
      "x-default": ukPath,
    },
  };
}

/**
 * Зручний варіант для дзеркалених `/en/*`-сторінок Etap A (ADR-037 §2) —
 * EN-шлях виводиться з uk-шляху через {@link toEnPath}, той самий механізм,
 * що й LocaleSwitcher/middleware. Для `/privacy`+`/en`, `/terms`+`/en`
 * (суфіксна легасі-схема) використовуйте {@link localeAlternates} напряму.
 */
export function mirroredAlternates(locale: Locale, ukPath: string): Metadata["alternates"] {
  return localeAlternates(locale, ukPath, toEnPath(ukPath));
}
