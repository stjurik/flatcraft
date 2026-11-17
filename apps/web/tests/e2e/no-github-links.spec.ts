import { expect, test } from "@playwright/test";

/**
 * #266 (зауваження yurii, hart-inbox #3, відповіді 19.10): на сайті немає посилань на
 * GitHub-репозиторій і згадок GitHub у тексті — скрізь, включно з правилами /terms;
 * картку «Open Source · MIT» на головній прибрано; у футері «Спільнота» лишається Discord.
 */
const PAGES = ["/", "/en", "/about", "/en/about", "/soon", "/en/soon", "/terms", "/terms/en"];

test.describe("#266 — без посилань і згадок GitHub", () => {
  for (const path of PAGES) {
    test(`${path}: немає a[href*=github.com] і слова GitHub`, async ({ page }) => {
      await page.goto(path);
      await expect(page.getByTestId("footer")).toBeVisible();
      await expect(page.locator('a[href*="github.com"]')).toHaveCount(0);
      const text = (await page.locator("body").innerText()).toLowerCase();
      expect(text, `на ${path} лишилась згадка GitHub`).not.toContain("github");
    });
  }

  test("футер: Discord лишився", async ({ page }) => {
    await page.goto("/");
    await expect(page.getByTestId("footer").locator('a[href*="discord"]').first()).toBeVisible();
  });
});
