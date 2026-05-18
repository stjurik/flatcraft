import { expect, test } from "@playwright/test";

test.describe("Каталог /templates", () => {
  test("показує L-bracket і Z-bracket картки (Phase 2.10)", async ({ page }) => {
    const consoleErrors: string[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") consoleErrors.push(msg.text());
    });

    await page.goto("/templates");

    await expect(page.getByTestId("templates-page-title")).toHaveText("Шаблони");

    const lBracketCard = page.locator('[data-testid="template-card"][data-slug="l_bracket"]');
    await expect(lBracketCard).toBeVisible();
    await expect(lBracketCard).toContainText("L-кронштейн");

    const zBracketCard = page.locator('[data-testid="template-card"][data-slug="z_bracket"]');
    await expect(zBracketCard).toBeVisible();
    await expect(zBracketCard).toContainText("Z-кронштейн");

    // Решта 3 — поки приховані до наступних PR (corner_angle, wall_shelf, perforated_panel).
    for (const slug of ["corner_angle", "wall_shelf", "perforated_panel"]) {
      await expect(page.locator(`[data-testid="template-card"][data-slug="${slug}"]`)).toHaveCount(
        0,
      );
    }

    expect(consoleErrors, consoleErrors.join("\n")).toEqual([]);
  });
});
