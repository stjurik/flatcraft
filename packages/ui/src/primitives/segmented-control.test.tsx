/**
 * Юніт-тести SegmentedControl (Phase 3.0 PR 3, ADR-027).
 *
 * ui-suite — node без jsdom (як r3f-error-boundary.test.tsx). Інспектуємо
 * React-дерево через `createElement` → props children без mount'у в DOM.
 */
import { isValidElement, type ReactElement } from "react";
import { describe, expect, it, vi } from "vitest";

import { SegmentedControl, type SegmentedControlOption } from "./segmented-control.js";

type TabValue = "products" | "parts";

const OPTIONS: ReadonlyArray<SegmentedControlOption<TabValue>> = [
  { value: "products", label: "Вироби" },
  { value: "parts", label: "Деталі" },
];

/** Шукає всі елементи з певним типом (button, div, тощо) у дереві. */
function findAll(
  node: unknown,
  pred: (el: ReactElement) => boolean,
  out: ReactElement[] = [],
): ReactElement[] {
  if (Array.isArray(node)) {
    for (const c of node) findAll(c, pred, out);
    return out;
  }
  if (isValidElement(node)) {
    if (pred(node)) out.push(node);
    const children = (node.props as { children?: unknown }).children;
    findAll(children, pred, out);
  }
  return out;
}

function renderToTree(props: Parameters<typeof SegmentedControl<TabValue>>[0]): ReactElement {
  // Function component повертає ReactElement при прямому виклику.
  const result = SegmentedControl(props);
  return result as ReactElement;
}

describe("SegmentedControl", () => {
  it("рендерить контейнер з role=group + aria-label", () => {
    const tree = renderToTree({
      value: "products",
      onValueChange: () => {},
      options: OPTIONS,
      ariaLabel: "Каталог-toggle",
    });
    const props = tree.props as Record<string, unknown>;
    expect(props["role"]).toBe("group");
    expect(props["aria-label"]).toBe("Каталог-toggle");
  });

  it("рендерить по одному button для кожної option", () => {
    const tree = renderToTree({
      value: "products",
      onValueChange: () => {},
      options: OPTIONS,
      ariaLabel: "test",
    });
    const buttons = findAll(tree, (el) => el.type === "button");
    expect(buttons.length).toBe(2);
  });

  it("активний button має aria-pressed=true і data-active='true'", () => {
    const tree = renderToTree({
      value: "products",
      onValueChange: () => {},
      options: OPTIONS,
      ariaLabel: "test",
    });
    const buttons = findAll(tree, (el) => el.type === "button");
    const activeBtn = buttons.find(
      (b) => (b.props as Record<string, unknown>)["data-value"] === "products",
    );
    const inactiveBtn = buttons.find(
      (b) => (b.props as Record<string, unknown>)["data-value"] === "parts",
    );
    expect((activeBtn?.props as Record<string, unknown>)["aria-pressed"]).toBe(true);
    expect((activeBtn?.props as Record<string, unknown>)["data-active"]).toBe("true");
    expect((inactiveBtn?.props as Record<string, unknown>)["aria-pressed"]).toBe(false);
    expect((inactiveBtn?.props as Record<string, unknown>)["data-active"]).toBe("false");
  });

  it("onClick активного button НЕ викликає onValueChange (no-op idempotency)", () => {
    const onValueChange = vi.fn();
    const tree = renderToTree({
      value: "products",
      onValueChange,
      options: OPTIONS,
      ariaLabel: "test",
    });
    const buttons = findAll(tree, (el) => el.type === "button");
    const activeBtn = buttons.find(
      (b) => (b.props as Record<string, unknown>)["data-value"] === "products",
    );
    const onClick = (activeBtn?.props as { onClick?: () => void }).onClick;
    onClick?.();
    expect(onValueChange).not.toHaveBeenCalled();
  });

  it("onClick неактивного button викликає onValueChange з новим value", () => {
    const onValueChange = vi.fn();
    const tree = renderToTree({
      value: "products",
      onValueChange,
      options: OPTIONS,
      ariaLabel: "test",
    });
    const buttons = findAll(tree, (el) => el.type === "button");
    const inactiveBtn = buttons.find(
      (b) => (b.props as Record<string, unknown>)["data-value"] === "parts",
    );
    const onClick = (inactiveBtn?.props as { onClick?: () => void }).onClick;
    onClick?.();
    expect(onValueChange).toHaveBeenCalledTimes(1);
    expect(onValueChange).toHaveBeenCalledWith("parts");
  });

  it("підтримує опційний testId — генерує data-testid на контейнері + items", () => {
    const tree = renderToTree({
      value: "products",
      onValueChange: () => {},
      options: OPTIONS,
      ariaLabel: "test",
      testId: "catalog-toggle",
    });
    const containerProps = tree.props as Record<string, unknown>;
    expect(containerProps["data-testid"]).toBe("catalog-toggle");

    const buttons = findAll(tree, (el) => el.type === "button");
    const productsBtn = buttons.find(
      (b) => (b.props as Record<string, unknown>)["data-value"] === "products",
    );
    expect((productsBtn?.props as Record<string, unknown>)["data-testid"]).toBe(
      "catalog-toggle-item-products",
    );
  });

  it("використовує ariaLabel опції при наявності, інакше label", () => {
    const tree = renderToTree({
      value: "products",
      onValueChange: () => {},
      options: [
        { value: "products", label: "Вироби", ariaLabel: "Готові вироби (preset)" },
        { value: "parts", label: "Деталі" },
      ],
      ariaLabel: "test",
    });
    const buttons = findAll(tree, (el) => el.type === "button");
    const productsBtn = buttons.find(
      (b) => (b.props as Record<string, unknown>)["data-value"] === "products",
    );
    const partsBtn = buttons.find(
      (b) => (b.props as Record<string, unknown>)["data-value"] === "parts",
    );
    expect((productsBtn?.props as Record<string, unknown>)["aria-label"]).toBe(
      "Готові вироби (preset)",
    );
    expect((partsBtn?.props as Record<string, unknown>)["aria-label"]).toBe("Деталі");
  });
});
