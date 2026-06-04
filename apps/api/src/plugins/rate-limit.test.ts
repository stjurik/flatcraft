/**
 * Unit-тести rate-limit конфігу (Phase X.1 A).
 *
 * Перевіряємо самі числа й форму RFC 9457 problem-detail, без підняття
 * Fastify (integration-частина — у exports.test.ts).
 */
import { describe, expect, it } from "vitest";

import { EXPORT_RATE_LIMIT, RATE_LIMIT_PLUGIN_OPTIONS } from "./rate-limit.js";

describe("rate-limit config", () => {
  it("плагін реєструється opt-in (global:false) — SSR-fetch не throttl'иться", () => {
    // global:false критично: web SSR робить server-side fetch з однієї IP;
    // глобальний per-IP ліміт миттєво throttl'ив би усіх (ловило CI на /materials).
    expect(RATE_LIMIT_PLUGIN_OPTIONS.global).toBe(false);
  });

  it("export-ліміт: 30 на годину з ban=50", () => {
    expect(EXPORT_RATE_LIMIT.max).toBe(30);
    expect(EXPORT_RATE_LIMIT.timeWindow).toBe("1 hour");
    expect(EXPORT_RATE_LIMIT.ban).toBe(50);
  });

  it("keyGenerator повертає IP запиту", () => {
    const key = EXPORT_RATE_LIMIT.keyGenerator?.({ ip: "203.0.113.7" } as never);
    expect(key).toBe("203.0.113.7");
  });

  it("errorResponseBuilder: 429 RFC 9457 з україномовним detail", () => {
    const problem = EXPORT_RATE_LIMIT.errorResponseBuilder?.(
      {} as never,
      {
        ttl: 5 * 60_000,
      } as never,
    ) as Record<string, unknown>;
    expect(problem.status).toBe(429);
    expect(problem.title).toBe("Rate limit exceeded");
    expect(problem.type).toMatch(/rate-limit/);
    expect(problem.instance).toBe("/exports");
    expect(String(problem.detail)).toMatch(/30 експортів на годину/);
    // ttl=5хв → підказка «через 5 хв».
    expect(String(problem.detail)).toMatch(/5 хв/);
  });

  it("errorResponseBuilder: ban → 403 з відповідним detail", () => {
    const problem = EXPORT_RATE_LIMIT.errorResponseBuilder?.(
      {} as never,
      {
        ttl: 60_000,
        ban: true,
      } as never,
    ) as Record<string, unknown>;
    expect(problem.status).toBe(403);
    expect(problem.title).toBe("Temporarily banned");
    expect(String(problem.detail)).toMatch(/обмежено/);
  });
});
