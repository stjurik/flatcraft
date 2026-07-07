import type { ErrorEvent } from "@sentry/nextjs";
import { describe, expect, it } from "vitest";

import { redactSentryPii } from "./sentry-pii.js";

const asEvent = (partial: Partial<ErrorEvent>): ErrorEvent => partial as ErrorEvent;

describe("redactSentryPii (web)", () => {
  it("прибирає user.email / ip_address / username, лишає id", () => {
    const ev = redactSentryPii(
      asEvent({ user: { id: "u1", email: "a@b.c", ip_address: "1.2.3.4", username: "a@b.c" } }),
    );
    expect(ev.user).toEqual({ id: "u1" });
  });

  it("прибирає cookies / query_string і чутливі заголовки, лишає інші", () => {
    const ev = redactSentryPii(
      asEvent({
        request: {
          cookies: { s: "x" },
          query_string: "email=a@b.c",
          headers: { Authorization: "Bearer x", Cookie: "a=b", "user-agent": "UA" },
        },
      }),
    );
    expect(ev.request?.cookies).toBeUndefined();
    expect(ev.request?.query_string).toBeUndefined();
    expect(ev.request?.headers).toEqual({ "user-agent": "UA" });
  });

  it("no-op на події без user/request", () => {
    const ev = redactSentryPii(asEvent({ level: "error" }));
    expect(ev.level).toBe("error");
  });
});
