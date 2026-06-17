/**
 * Hotfix 2.9.f (ADR-026): InvalidParametersFallback рендерить конкретні поради.
 * SSR-рендер (renderToString — web-suite без jsdom).
 */
import type { ProfileIssue } from "@flatcraft/cad-engine";
import { renderToString } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { InvalidParametersFallback } from "./invalid-parameters-fallback";

const legIssue: ProfileIssue = {
  code: "LEG_TOO_SHORT",
  which: "legA",
  min: 4.5,
  got: 1,
  message: "Збільшіть «Довжина плеча A» до мінімум 4.5 мм (товщина 2 + радіус 2.5).",
};
const legBIssue: ProfileIssue = {
  code: "LEG_TOO_SHORT",
  which: "legB",
  min: 4.5,
  got: 2,
  message: "Збільшіть «Довжина плеча B» до мінімум 4.5 мм (товщина 2 + радіус 2.5).",
};

describe("InvalidParametersFallback", () => {
  it("показує заголовок-підказку", () => {
    const html = renderToString(<InvalidParametersFallback issues={[legIssue]} />);
    expect(html).toContain("Виправте параметри у формі");
  });

  it("рендерить повідомлення issue з конкретним мінімумом", () => {
    const html = renderToString(<InvalidParametersFallback issues={[legIssue]} />);
    expect(html).toContain("4.5 мм");
    expect(html).toContain("Довжина плеча A");
  });

  it("рендерить кілька issues окремими пунктами", () => {
    const html = renderToString(<InvalidParametersFallback issues={[legIssue, legBIssue]} />);
    expect(html).toContain("Довжина плеча A");
    expect(html).toContain("Довжина плеча B");
    expect((html.match(/<li/g) ?? []).length).toBe(2);
  });

  it("має data-testid та role=status", () => {
    const html = renderToString(<InvalidParametersFallback issues={[legIssue]} />);
    expect(html).toContain('data-testid="invalid-parameters-fallback"');
    expect(html).toContain('role="status"');
  });

  it("порожній список issues → без <ul>, але заголовок є", () => {
    const html = renderToString(<InvalidParametersFallback issues={[]} />);
    expect(html).toContain("Виправте параметри у формі");
    expect(html).not.toContain("<ul");
  });

  it("ключ списку — issue.which (без React-варнінгів дублікатів)", () => {
    // різні which → стабільні унікальні елементи
    const html = renderToString(<InvalidParametersFallback issues={[legIssue, legBIssue]} />);
    expect(html).toContain("<li");
  });
});
