/**
 * Юніт-тести R3FErrorBoundary (Hotfix 2.9.f, ADR-026).
 *
 * ui-suite — node без jsdom, тож тестуємо boundary через статичні/інстанс-методи
 * та pure-fallback (без mount'у). Це покриває весь error-flow: throw у дитині →
 * React викликає getDerivedStateFromError → render віддає fallback → retry скидає
 * стан.
 */
import { createElement, isValidElement, type ReactElement } from "react";
import { describe, expect, it, vi } from "vitest";

import { R3FErrorBoundary, R3FErrorFallback } from "./r3f-error-boundary.js";

/** Рекурсивно збирає текстові вузли з React-елемента (для assert без DOM). */
function collectText(node: unknown): string {
  if (node == null || typeof node === "boolean") return "";
  if (typeof node === "string" || typeof node === "number") return String(node);
  if (Array.isArray(node)) return node.map(collectText).join("");
  if (isValidElement(node)) {
    const props = node.props as { children?: unknown };
    return collectText(props.children);
  }
  return "";
}

/** Шукає перший елемент за предикатом у дереві. */
function findElement(node: unknown, pred: (el: ReactElement) => boolean): ReactElement | undefined {
  if (Array.isArray(node)) {
    for (const c of node) {
      const found = findElement(c, pred);
      if (found) return found;
    }
    return undefined;
  }
  if (isValidElement(node)) {
    if (pred(node)) return node;
    return findElement((node.props as { children?: unknown }).children, pred);
  }
  return undefined;
}

describe("R3FErrorBoundary", () => {
  it("getDerivedStateFromError → {hasError:true, error}", () => {
    const err = new Error("legA_mm too small");
    expect(R3FErrorBoundary.getDerivedStateFromError(err)).toEqual({ hasError: true, error: err });
  });

  it("без помилки render() повертає children", () => {
    const child = createElement("div", { "data-testid": "scene" });
    const boundary = new R3FErrorBoundary({ children: child });
    expect(boundary.render()).toBe(child);
  });

  it("після помилки render() повертає fallback", () => {
    const boundary = new R3FErrorBoundary({ children: createElement("div") });
    // Симулюємо React-flow: throw у дитині → setState через derived state.
    boundary.state = R3FErrorBoundary.getDerivedStateFromError(new Error("boom"));
    const out = boundary.render();
    // render() повертає <R3FErrorFallback/> (нерозгорнутий елемент-компонент).
    expect(isValidElement(out) && out.type === R3FErrorFallback).toBe(true);
  });

  it("componentDidCatch кличе onError-колбек (телеметрія)", () => {
    const onError = vi.fn();
    const boundary = new R3FErrorBoundary({ children: createElement("div"), onError });
    const err = new Error("boom");
    boundary.componentDidCatch(err, { componentStack: "" });
    expect(onError).toHaveBeenCalledWith(err, { componentStack: "" });
  });

  it("handleRetry скидає hasError у false", () => {
    const boundary = new R3FErrorBoundary({ children: createElement("div") });
    boundary.state = { hasError: true, error: new Error("x") };
    const setState = vi.fn();
    // Підміняємо setState для перевірки без mount'у.
    (boundary as unknown as { setState: typeof setState }).setState = setState;
    boundary.handleRetry();
    expect(setState).toHaveBeenCalledWith({ hasError: false, error: undefined });
  });
});

describe("R3FErrorFallback", () => {
  it("рендерить повідомлення + кнопку retry з onClick", () => {
    const onRetry = vi.fn();
    const out = R3FErrorFallback({ onRetry });
    expect(collectText(out)).toContain("3D-прев'ю тимчасово недоступне");
    const button = findElement(out, (el) => el.type === "button");
    expect(button).toBeDefined();
    (button?.props as { onClick: () => void }).onClick();
    expect(onRetry).toHaveBeenCalledOnce();
  });
});
