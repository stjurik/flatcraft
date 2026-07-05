/**
 * Sentry `beforeSend` PII-фільтр (інваріант CLAUDE.md §8, ADR-032).
 *
 * Прибирає email / IP / чутливі заголовки ПЕРЕД відправкою у Sentry — паритет із
 * серверним фільтром api/worker. Спільний для client + server + edge конфігів.
 */
import type { ErrorEvent, EventHint } from "@sentry/nextjs";

const SENSITIVE_HEADERS = ["authorization", "cookie", "set-cookie", "x-csrf-token"];

export function redactSentryPii(event: ErrorEvent, _hint?: EventHint): ErrorEvent {
  if (event.user) {
    delete event.user.email;
    delete event.user.ip_address;
    delete event.user.username;
  }
  if (event.request) {
    delete event.request.cookies;
    delete event.request.query_string;
    const headers = event.request.headers;
    if (headers) {
      for (const key of Object.keys(headers)) {
        if (SENSITIVE_HEADERS.includes(key.toLowerCase())) delete headers[key];
      }
    }
  }
  return event;
}
