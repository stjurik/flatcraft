import { DEFAULT_LOCALE, type Locale } from "./locale";

/**
 * Дзеркалені uk-шляхи Etap A (ADR-037 §2) — єдине джерело для
 * `middleware.ts` matcher і для LocaleSwitcher (щоб не вести на 404 поза
 * цим набором).
 */
export const MIRRORED_UK_PATH_PREFIXES: readonly string[] = [
  "/",
  "/about",
  "/soon",
  "/templates",
  "/products",
];

const EN_PREFIX_RE = /^\/en(\/|$)/;

function isMirrored(ukPathname: string): boolean {
  if (ukPathname === "/") return true;
  return MIRRORED_UK_PATH_PREFIXES.some(
    (prefix) => prefix !== "/" && (ukPathname === prefix || ukPathname.startsWith(`${prefix}/`)),
  );
}

/** Локаль поточної сторінки з pathname — `/en/*` це `en`, усе інше `uk`. */
export function localeFromPathname(pathname: string): Locale {
  return EN_PREFIX_RE.test(pathname) ? "en" : DEFAULT_LOCALE;
}

/**
 * uk-шлях → EN-дзеркало (`/en/*`). Symmetric з {@link toUkPath} — без
 * hardcoded route-table, працює для будь-якого майбутнього шляху всередині
 * {@link MIRRORED_UK_PATH_PREFIXES}.
 */
export function toEnPath(ukPathname: string): string {
  if (ukPathname === "/") return "/en";
  return `/en${ukPathname}`;
}

/** EN-шлях (`/en/*`) → uk-оригінал. */
export function toUkPath(enPathname: string): string {
  return enPathname.replace(EN_PREFIX_RE, "/");
}

/**
 * Обчислює URL для LocaleSwitcher з поточного pathname (локаль виводиться
 * з самого pathname). Повертає `null`, якщо поточна сторінка поза
 * дзеркаленим Etap A-набором (перемикач тоді не рендериться — ADR-037 §2,
 * свідомий ліміт).
 */
export function switchLocaleHref(pathname: string): string | null {
  if (localeFromPathname(pathname) === "uk") {
    return isMirrored(pathname) ? toEnPath(pathname) : null;
  }
  const ukPathname = toUkPath(pathname);
  return isMirrored(ukPathname) ? ukPathname : null;
}
