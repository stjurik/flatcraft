/**
 * Канонічний origin платформи — використовується `metadataBase` (layout.tsx),
 * `app/sitemap.ts` (абсолютні URL, обов'язкові для sitemap-запису) і будь-де,
 * де Next.js не резолвить відносний шлях сам (ADR-037 §7 follow-up, hreflang).
 */
export const SITE_URL = "https://hart.crimea.ua";
