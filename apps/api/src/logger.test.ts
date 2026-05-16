import { describe, expect, it } from "vitest";

import { createLoggerOptions } from "./logger.js";

describe("createLoggerOptions", () => {
  it("у dev використовує pino-pretty transport", () => {
    const opts = createLoggerOptions({ NODE_ENV: "development", LOG_LEVEL: "debug" });
    const transport = opts.transport;
    if (!transport || !("target" in transport)) {
      throw new Error("dev transport has to be single TransportSingleOptions");
    }
    expect(transport.target).toBe("pino-pretty");
    expect(opts.level).toBe("debug");
  });

  it("у production не використовує pretty", () => {
    const opts = createLoggerOptions({ NODE_ENV: "production", LOG_LEVEL: "info" });
    expect(opts.transport).toBeUndefined();
    expect(opts.level).toBe("info");
  });

  it("redact-paths включають PII-чутливі ключі і remove=true (CLAUDE.md §8)", () => {
    const opts = createLoggerOptions({ NODE_ENV: "production", LOG_LEVEL: "info" });
    // redact завжди об'єкт (не string[]) — наш контракт; звужуємо тип явно.
    const redact = opts.redact;
    if (!redact || Array.isArray(redact)) {
      throw new Error("redact has to be a redactOptions object");
    }
    expect(redact.paths).toContain("req.headers.authorization");
    expect(redact.paths).toContain("req.headers.cookie");
    expect(redact.paths.some((p) => p.includes("password"))).toBe(true);
    expect(redact.paths.some((p) => p.includes("email"))).toBe(true);
    expect(redact.remove).toBe(true);
  });
});
