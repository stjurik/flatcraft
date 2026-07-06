import { afterEach, describe, expect, it, vi } from "vitest";

import { firstIssueCode, track, webVitalProps } from "./analytics";

afterEach(() => {
  vi.unstubAllGlobals();
});

/** Стабимо `window` (web-suite без jsdom) з опційним `umami`-моком. */
function stubWindow(umamiTrack?: unknown): void {
  vi.stubGlobal("window", umamiTrack === undefined ? {} : { umami: { track: umamiTrack } });
}

describe("track", () => {
  it("no-op коли window.umami відсутній (скрипт не завантажено)", () => {
    stubWindow(); // window є, umami нема
    expect(() => track("catalog")).not.toThrow();
  });

  it("no-op на сервері (window undefined)", () => {
    vi.stubGlobal("window", undefined);
    expect(() => track("studio_opened")).not.toThrow();
  });

  it("викликає umami.track з ім'ям події та data", () => {
    const spy = vi.fn();
    stubWindow(spy);
    track("validation_error_shown", { constraint: "RADIUS_NOT_ALLOWED", template: "z_bracket" });
    expect(spy).toHaveBeenCalledWith("validation_error_shown", {
      constraint: "RADIUS_NOT_ALLOWED",
      template: "z_bracket",
    });
  });

  it("без props — викликає track лише з ім'ям події", () => {
    const spy = vi.fn();
    stubWindow(spy);
    track("export_clicked");
    expect(spy).toHaveBeenCalledWith("export_clicked");
  });

  it("fail-closed: props з PII-ключем → нічого не шлемо", () => {
    const spy = vi.fn();
    stubWindow(spy);
    track("export_done", { email: "a@b.com" } as never);
    expect(spy).not.toHaveBeenCalled();
  });

  it("fail-closed нечутливий до регістру ключа", () => {
    const spy = vi.fn();
    stubWindow(spy);
    track("export_done", { IP_Address: "1.2.3.4" } as never);
    expect(spy).not.toHaveBeenCalled();
  });
});

describe("webVitalProps", () => {
  it("округлює value і пробрасує metric+rating", () => {
    expect(webVitalProps({ name: "LCP", value: 2412.7, rating: "good" })).toEqual({
      metric: "LCP",
      value: 2413,
      rating: "good",
    });
  });

  it("без rating — ключ відсутній", () => {
    expect(webVitalProps({ name: "TTFB", value: 120 })).toEqual({ metric: "TTFB", value: 120 });
  });
});

describe("firstIssueCode", () => {
  it("порожній список → undefined", () => {
    expect(firstIssueCode([])).toBeUndefined();
  });

  it("повертає code першого issue", () => {
    expect(firstIssueCode([{ code: "FLANGE_TOO_SHORT" }, { code: "RADIUS_NOT_ALLOWED" }])).toBe(
      "FLANGE_TOO_SHORT",
    );
  });
});
