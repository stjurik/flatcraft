import { expect, test } from "@playwright/test";

test.describe("Каталог /templates (Phase 2.1)", () => {
  test("показує заголовок і L-bracket картку після seed", async ({ page }) => {
    const consoleErrors: string[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") consoleErrors.push(msg.text());
    });

    await page.goto("/templates");

    await expect(page.getByTestId("templates-page-title")).toHaveText("Шаблони");

    // L-bracket — єдиний опублікований після Phase 2.1 seed.
    const lBracketCard = page.locator('[data-testid="template-card"][data-slug="l_bracket"]');
    await expect(lBracketCard).toBeVisible();
    await expect(lBracketCard.getByTestId("template-card-slug")).toHaveText("l_bracket");
    await expect(lBracketCard).toContainText("L-кронштейн");

    // Картка має placeholder для прев'ю (поки немає R2-зображень).
    await expect(lBracketCard.getByTestId("template-card-preview-placeholder")).toBeVisible();

    // Z-bracket / corner_angle / wall_shelf / perforated_panel — поки is_published=false.
    await expect(page.locator('[data-testid="template-card"][data-slug="z_bracket"]')).toHaveCount(
      0,
    );

    expect(consoleErrors, consoleErrors.join("\n")).toEqual([]);
  });

  // Error-path (templates-load-error) рендериться у server component при
  // недоступному API; playwright route не може перехопити server-side
  // fetch у Node-процесі Next. Залишаємо ручну перевірку: зупинити api
  // і відкрити /templates — error block має з'явитися.
});
