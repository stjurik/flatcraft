import Script from "next/script";

/**
 * Umami tracking-скрипт (ADR-032 §4, docs/11 §8) — self-hosted, окрема БД у
 * наявному Postgres. Cookie-less (ADR-006) → без cookie-banner.
 *
 * Рендериться ЛИШЕ коли задано `NEXT_PUBLIC_UMAMI_WEBSITE_ID` **і**
 * `NEXT_PUBLIC_UMAMI_SRC` — інакше `null` (dev/preview без аналітики;
 * `window.umami` відсутній → `track` no-op). `NEXT_PUBLIC_*` інлайняться Next
 * під час build.
 *
 * Черги-стабу немає: події до завантаження скрипта дропаються (`track` гейтить
 * на `typeof window.umami.track`) — accepted при поточному трафіку (docs/11 §8).
 */
const WEBSITE_ID = process.env["NEXT_PUBLIC_UMAMI_WEBSITE_ID"];
const SRC = process.env["NEXT_PUBLIC_UMAMI_SRC"];

export function AnalyticsScripts() {
  if (!WEBSITE_ID || !SRC) return null;
  return <Script defer src={SRC} data-website-id={WEBSITE_ID} strategy="afterInteractive" />;
}
