import { describe, expect, it } from "vitest";

import { parseEnv } from "./env.js";

describe("parseEnv", () => {
  it("приймає мінімальний набір і ставить дефолти", () => {
    const env = parseEnv({});
    expect(env.NODE_ENV).toBe("development");
    expect(env.HOST).toBe("0.0.0.0");
    expect(env.PORT).toBe(4000);
    expect(["fatal", "error", "warn", "info", "debug", "trace"]).toContain(env.LOG_LEVEL);
  });

  it("парсить PORT як число", () => {
    const env = parseEnv({ PORT: "5000" });
    expect(env.PORT).toBe(5000);
  });

  it("кидає на невалідному PORT", () => {
    expect(() => parseEnv({ PORT: "not-a-number" })).toThrow();
  });

  it("приймає production з валідними значеннями", () => {
    const env = parseEnv({ NODE_ENV: "production", LOG_LEVEL: "warn" });
    expect(env.NODE_ENV).toBe("production");
    expect(env.LOG_LEVEL).toBe("warn");
  });

  it("кидає на невалідному NODE_ENV", () => {
    expect(() => parseEnv({ NODE_ENV: "staging" })).toThrow();
  });

  // Ansible-шаблон env.prod.j2 рендерить `SENTRY_DSN=` пустим рядком, коли
  // vault_sentry_dsn не задано. Без preprocess'у Zod .url() кидає на "" → api
  // у crash-loop → deploy падає з "container is unhealthy" (інцидент 07.07.2026).
  it("трактує порожній SENTRY_DSN як не задано", () => {
    const env = parseEnv({ SENTRY_DSN: "" });
    expect(env.SENTRY_DSN).toBeUndefined();
  });

  it("приймає валідний SENTRY_DSN", () => {
    const env = parseEnv({ SENTRY_DSN: "https://key@sentry.io/1" });
    expect(env.SENTRY_DSN).toBe("https://key@sentry.io/1");
  });

  it("кидає на невалідному SENTRY_DSN (не-URL)", () => {
    expect(() => parseEnv({ SENTRY_DSN: "not-a-url" })).toThrow();
  });

  it("трактує порожній SENTRY_ENVIRONMENT як не задано", () => {
    const env = parseEnv({ SENTRY_ENVIRONMENT: "" });
    expect(env.SENTRY_ENVIRONMENT).toBeUndefined();
  });
});
