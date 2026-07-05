/**
 * Sentry client init (браузер, ADR-032). No-op без `NEXT_PUBLIC_SENTRY_DSN`.
 * Sample: errors 100% / traces 0. beforeSend прибирає PII (CLAUDE.md §8).
 * Це єдиний спосіб побачити краш R3F на реальних телефонах (R-02).
 */
import * as Sentry from "@sentry/nextjs";

import { redactSentryPii } from "./lib/sentry-pii.js";

const dsn = process.env["NEXT_PUBLIC_SENTRY_DSN"];
if (dsn) {
  const environment = process.env["NEXT_PUBLIC_SENTRY_ENVIRONMENT"];
  Sentry.init({
    dsn,
    ...(environment ? { environment } : {}),
    tracesSampleRate: 0,
    sampleRate: 1,
    sendDefaultPii: false,
    beforeSend: redactSentryPii,
  });
}
