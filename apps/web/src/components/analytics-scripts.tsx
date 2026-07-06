import Script from "next/script";

/**
 * Plausible tracking-скрипт (ADR-032 §4, docs/11 §8). Self-hosted або cloud —
 * керується env. Cookie-less (ADR-006) → без cookie-banner.
 *
 * Рендериться ЛИШЕ коли задано `NEXT_PUBLIC_PLAUSIBLE_DOMAIN` — інакше `null`
 * (dev/preview без аналітики; `window.plausible` відсутній → `track` no-op).
 * `NEXT_PUBLIC_*` інлайняться Next під час build.
 */
const DOMAIN = process.env["NEXT_PUBLIC_PLAUSIBLE_DOMAIN"];
const API_HOST = process.env["NEXT_PUBLIC_PLAUSIBLE_API_HOST"] ?? "https://plausible.io";

/**
 * Queue-stub: дозволяє викликати `window.plausible(...)` (custom-події воронки)
 * ще до того, як зовнішній скрипт довантажився — виклики буферизуються.
 */
const PLAUSIBLE_STUB =
  "window.plausible=window.plausible||function(){(window.plausible.q=window.plausible.q||[]).push(arguments)}";

export function AnalyticsScripts() {
  if (!DOMAIN) return null;
  const src = `${API_HOST.replace(/\/+$/, "")}/js/script.js`;
  return (
    <>
      <Script defer data-domain={DOMAIN} src={src} strategy="afterInteractive" />
      <Script id="plausible-init" strategy="afterInteractive">
        {PLAUSIBLE_STUB}
      </Script>
    </>
  );
}
