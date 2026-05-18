import { expect, test } from "@playwright/test";

test.describe("Каталог /templates", () => {
  test("показує всі 5 шаблонів — Phase 2.10 закрита", async ({ page }) => {
    const consoleErrors: string[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") consoleErrors.push(msg.text());
    });

    await page.goto("/templates");

    await expect(page.getByTestId("templates-page-title")).toHaveText("Шаблони");

    const expectedSlugs: ReadonlyArray<{ slug: string; name: string }> = [
      { slug: "l_bracket", name: "L-кронштейн" },
      { slug: "z_bracket", name: "Z-кронштейн" },
      { slug: "corner_angle", name: "Кутник" },
      { slug: "wall_shelf", name: "Полиця настінна" },
      { slug: "perforated_panel", name: "Перфо-панель" },
    ];

    for (const { slug, name } of expectedSlugs) {
      const card = page.locator(`[data-testid="template-card"][data-slug="${slug}"]`);
      await expect(card).toBeVisible();
      await expect(card).toContainText(name);
    }

    expect(consoleErrors, consoleErrors.join("\n")).toEqual([]);
  });
});
