import { describe, expect, it } from "vitest";

import { dailySalt, sessionHash } from "./session-hash.js";

describe("sessionHash", () => {
  it("детермінований за (ip, salt)", () => {
    expect(sessionHash("1.2.3.4", "s")).toBe(sessionHash("1.2.3.4", "s"));
  });

  it("різний salt → різний хеш (непереслідуваність між добами)", () => {
    expect(sessionHash("1.2.3.4", "day1")).not.toBe(sessionHash("1.2.3.4", "day2"));
  });

  it("різний IP → різний хеш", () => {
    expect(sessionHash("1.2.3.4", "s")).not.toBe(sessionHash("5.6.7.8", "s"));
  });

  it("НЕ містить сирого IP і має форму 32-hex", () => {
    const h = sessionHash("203.0.113.7", "s");
    expect(h).not.toContain("203.0.113.7");
    expect(h).toMatch(/^[0-9a-f]{32}$/);
  });

  it("undefined / порожній IP → null", () => {
    expect(sessionHash(undefined, "s")).toBeNull();
    expect(sessionHash("", "s")).toBeNull();
  });

  it("dailySalt стабільний у межах однієї UTC-доби", () => {
    const a = dailySalt(new Date("2026-07-05T01:00:00Z"));
    const b = dailySalt(new Date("2026-07-05T23:59:00Z"));
    expect(a).toBe(b);
    expect(a).toMatch(/^[0-9a-f]{32}$/);
  });
});
