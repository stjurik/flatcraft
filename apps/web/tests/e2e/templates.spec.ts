import { expect, test } from "@playwright/test";

test.describe("Каталог /templates", () => {
  test("показує L-bracket, Z-bracket і corner_angle картки (Phase 2.10.b)", async ({ page }) => {
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

    const cornerCard = page.locator('[data-testid="template-card"][data-slug="corner_angle"]');
    await expect(cornerCard).toBeVisible();
    await expect(cornerCard).toContainText("Кутник");

    // Решта 2 — поки приховані до Phase 2.10.c/d (wall_shelf, perforated_panel).
    for (const slug of ["wall_shelf", "perforated_panel"]) {
      await expect(page.locator(`[data-testid="template-card"][data-slug="${slug}"]`)).toHaveCount(
        0,
      );
    }

    expect(consoleErrors, consoleErrors.join("\n")).toEqual([]);
  });
});
