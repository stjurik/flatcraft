import { expect, test } from "@playwright/test";

const ROUTES = ["/", "/templates", "/styleguide"] as const;

test.describe("Global layout (Phase 2.11 — Logo header + Footer на всіх сторінках)", () => {
  for (const route of ROUTES) {
    test(`${route}: header з Logo + footer з UkraineStripe і ЗСУ-кнопкою`, async ({ page }) => {
      await page.goto(route);

      // Header: <Logo /> у sticky bar.
      const header = page.getByTestId("site-header");
      await expect(header).toBeVisible();
      const headerLogo = header.getByTestId("logo");
      await expect(headerLogo).toBeVisible();
      await expect(headerLogo).toHaveText("hart.crimea.ua");

      // Footer: глобальний footer у layout — завжди останній у DOM.
      // (На /styleguide є ще один демо-Footer всередині section #footer
      // — звідси .last().)
      const footer = page.getByTestId("footer").last();
      await expect(footer).toBeVisible();
      await expect(footer.getByTestId("ukraine-stripe")).toBeVisible();
      const zsu = footer.getByTestId("zsu-donate");
      await expect(zsu).toBeVisible();
      await expect(zsu).toHaveText("Підтримати ЗСУ");
    });
  }
});
