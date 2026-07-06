/**
 * Продуктова аналітика — Umami воронка + web-vitals (ADR-032 §4, docs/11 §8).
 *
 * Vendor-нейтральна обгортка: публічний API (`track`) не залежить від бекенда;
 * під капотом — `window.umami.track` (Umami self-hosted, ADR-032 §4). Клієнт-side,
 * cookie-less (ADR-006 → без cookie-banner). Це агрегатний UX-сигнал (де
 * користувач страждає), НЕ джерело істини — точний серверний факт живе у `events`
 * (PR 2). Umami-скрипт вантажиться лише коли задано `NEXT_PUBLIC_UMAMI_WEBSITE_ID`
 * + `NEXT_PUBLIC_UMAMI_SRC` (див. `components/analytics-scripts.tsx`); без нього
 * `window.umami` відсутній і всі виклики тут — no-op.
 *
 * GDPR (CLAUDE.md §8): у props НІКОЛИ не потрапляє PII. `track` fail-closed —
 * якщо props містять заборонений ключ (email/ip/…), увесь виклик тихо
 * відкидається, а не «очищується». Call-site'и й так шлють лише
 * template/constraint/mode/metric — whitelisted низькокардинальні виміри.
 */

/** Кроки воронки docs/11 §8: catalog → … → export_done. */
export const FUNNEL_EVENTS = [
  "catalog",
  "studio_opened",
  "param_changed",
  "validation_error_shown",
  "export_clicked",
  "export_done",
] as const;

export type FunnelEvent = (typeof FUNNEL_EVENTS)[number];

/** Усі custom-події, які шлемо у Umami (воронка + web-vitals). */
export type AnalyticsEvent = FunnelEvent | "web_vital";

/** Значення custom-props (event-data Umami) — рядок або число. */
export type AnalyticsProps = Record<string, string | number>;

/**
 * Ключі, які НЕ можуть з'явитися у props (PII-backstop). Не покладаємось лише на
 * дисципліну call-site'ів — тут остання лінія оборони перед мережею.
 */
const FORBIDDEN_PROP_KEYS: ReadonlySet<string> = new Set([
  "email",
  "ip",
  "ip_address",
  "user",
  "user_id",
  "username",
  "name",
  "phone",
  "password",
  "session_hash",
]);

declare global {
  interface Window {
    umami?: { track: (event: string, data?: AnalyticsProps) => void };
  }
}

function hasForbiddenKey(props: AnalyticsProps): boolean {
  return Object.keys(props).some((key) => FORBIDDEN_PROP_KEYS.has(key.toLowerCase()));
}

/**
 * Шле custom-подію у Umami (`window.umami.track`). No-op на сервері (SSR) і поки
 * скрипт не завантажив `window.umami`. Fail-closed на PII у props.
 */
export function track(event: AnalyticsEvent, props?: AnalyticsProps): void {
  if (typeof window === "undefined") return;
  const umami = window.umami;
  if (typeof umami?.track !== "function") return;
  if (props && hasForbiddenKey(props)) return;
  if (props) umami.track(event, props);
  else umami.track(event);
}

/** Мінімальна форма метрики з `next/web-vitals` (лише поля, які шлемо). */
export interface WebVitalMetric {
  readonly name: string;
  readonly value: number;
  readonly rating?: string;
}

/**
 * Мапить web-vitals-метрику у props (event-data Umami). `value` округлюємо (мс), щоб
 * не плодити кардинальність; `rating` (good/needs-improvement/poor) — головний
 * вимір для звірки з бюджетами CLAUDE.md §9.
 */
export function webVitalProps(metric: WebVitalMetric): AnalyticsProps {
  return {
    metric: metric.name,
    value: Math.round(metric.value),
    ...(metric.rating ? { rating: metric.rating } : {}),
  };
}

/**
 * `code` першого issue (валідація/профіль/перфорація мають спільне поле `code`)
 * — вимір `constraint` для `validation_error_shown`. Ключова метрика R-10:
 * який ліміт блокує найчастіше. Порожньо → `undefined`.
 */
export function firstIssueCode(issues: readonly { readonly code: string }[]): string | undefined {
  return issues[0]?.code;
}
