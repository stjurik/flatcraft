import { expect, test, type Page } from "@playwright/test";

/**
 * #264 (зауваження yurii, hart-inbox #4): у формі параметрів поля одного рядка сітки
 * мають стояти на одній лінії, навіть коли назва поля переноситься на два рядки.
 * Поле — input/select/textarea у `field-*` або плашка значення в `literal-*`.
 */
type Row = { names: string[]; labelHeights: number[]; controlTops: number[] };

async function rows(page: Page): Promise<Row[]> {
  return page.evaluate(() => {
    const shells = Array.from(
      document.querySelectorAll<HTMLElement>(
        '[data-testid^="field-"]:not([data-testid^="field-error-"]), [data-testid^="literal-"]',
      ),
    );
    const groups = new Map<string, Row>();
    for (const el of shells) {
      const parent = el.parentElement;
      if (!parent) continue;
      const control =
        el.querySelector<HTMLElement>("input, select, textarea") ??
        el.querySelectorAll<HTMLElement>(":scope > span")[1] ??
        null;
      const label = el.querySelector<HTMLElement>(":scope > span");
      if (!control || !label) continue;
      const top = Math.round(el.getBoundingClientRect().top);
      const idx = Array.from(document.querySelectorAll("*")).indexOf(parent);
      const key = `${idx}:${top}`;
      const g = groups.get(key) ?? { names: [], labelHeights: [], controlTops: [] };
      g.names.push(el.dataset["testid"] ?? "");
      g.labelHeights.push(label.getBoundingClientRect().height);
      g.controlTops.push(control.getBoundingClientRect().top);
      groups.set(key, g);
    }
    return Array.from(groups.values()).filter((g) => g.names.length > 1);
  });
}

test.describe("#264 — поля в одному рядку форми на одній лінії", () => {
  test.use({ viewport: { width: 1280, height: 900 } });

  test("corner_angle: блок «Гиб» і решта рядків", async ({ page }) => {
    await page.goto("/templates/corner_angle");
    await expect(page.getByTestId("validation-ok")).toBeVisible();

    const all = await rows(page);
    expect(all.length, "у формі є рядки з ≥2 полями").toBeGreaterThan(0);
    // Передумова: є рядок, де назви різної висоти (інакше тест нічого не доводить).
    const uneven = all.filter((r) => Math.max(...r.labelHeights) - Math.min(...r.labelHeights) > 4);
    expect(uneven.length, "є рядок з назвою на 2 рядки поруч з однорядковою").toBeGreaterThan(0);

    for (const r of all) {
      const spread = Math.max(...r.controlTops) - Math.min(...r.controlTops);
      expect(spread, `поля ${r.names.join(", ")} не на одній лінії`).toBeLessThanOrEqual(1);
    }
  });
});
