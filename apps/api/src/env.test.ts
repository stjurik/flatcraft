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
});
