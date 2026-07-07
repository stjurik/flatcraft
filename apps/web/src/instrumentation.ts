/**
 * Next.js instrumentation (server + edge Sentry init, ADR-032). No-op без DSN
 * (dev / CI / тести). Sample: errors 100% / traces 0 (ресурси MS21). beforeSend
 * прибирає PII (інваріант CLAUDE.md §8). Client init — `instrumentation-client.ts`.
 */
import * as Sentry from "@sentry/nextjs";

import { redactSentryPii } from "./lib/sentry-pii.js";

export async function register(): Promise<void> {
  const dsn = process.env["SENTRY_DSN"] ?? process.env["NEXT_PUBLIC_SENTRY_DSN"];
  if (!dsn) return;
  if (process.env["NEXT_RUNTIME"] === "nodejs" || process.env["NEXT_RUNTIME"] === "edge") {
    const environment = process.env["SENTRY_ENVIRONMENT"];
    Sentry.init({
      dsn,
      ...(environment ? { environment } : {}),
      tracesSampleRate: 0,
      sampleRate: 1,
      sendDefaultPii: false,
      beforeSend: redactSentryPii,
    });
  }
}

// Ловить помилки серверних компонентів / route-handler'ів (Next 15).
export const onRequestError = Sentry.captureRequestError;
