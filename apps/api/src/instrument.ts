/**
 * Sentry-ініціалізація (ADR-032, Roadmap 5.1). **Імпортується ПЕРШИМ** у
 * server-entry, щоб init стався до інших модулів. No-op без `SENTRY_DSN`
 * (dev / CI / тести не чіпаються). Sample: errors 100% / traces 0 (ресурси MS21).
 * `beforeSend` прибирає PII (інваріант CLAUDE.md §8).
 */
import * as Sentry from "@sentry/node";

import { env } from "./env.js";
import { redactSentryPii } from "./lib/sentry-pii.js";

if (env.SENTRY_DSN) {
  Sentry.init({
    dsn: env.SENTRY_DSN,
    environment: env.SENTRY_ENVIRONMENT ?? env.NODE_ENV,
    tracesSampleRate: 0,
    sampleRate: 1,
    sendDefaultPii: false,
    beforeSend: redactSentryPii,
  });
}
