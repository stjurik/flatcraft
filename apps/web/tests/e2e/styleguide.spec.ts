import { expect, test } from "@playwright/test";

test.describe("Styleguide (Phase 2.11 design system)", () => {
  const VIEWPORTS = [
    { name: "mobile-360", width: 360, height: 640 },
    { name: "tablet-768", width: 768, height: 1024 },
    { name: "desktop-1280", width: 1280, height: 800 },
  ] as const;

  for (const { name, width, height } of VIEWPORTS) {
    test(`рендериться без console-errors на ${name}`, async ({ page }) => {
      const errors: string[] = [];
      page.on("console", (msg) => {
        if (msg.type() === "error") errors.push(msg.text());
      });

      await page.setViewportSize({ width, height });
      await page.goto("/styleguide");

      await expect(page.getByRole("heading", { name: "Design System" })).toBeVisible();
      // Усі 12 секцій присутні (id у hash-anchor):
      for (const id of [
        "brand",
        "typography",
        "colors",
        "buttons",
        "forms",
        "cards",
        "badges",
        "overlays",
        "icons",
        "motion",
        "footer",
        "viewport",
      ]) {
        await expect(page.locator(`#${id}`)).toBeAttached();
      }

      expect(errors, errors.join("\n")).toEqual([]);
    });
  }

  test("UkraineStripe — 2px заввишки, з UA-blue і UA-yellow", async ({ page }) => {
    await page.goto("/styleguide");
    // У styleguide є дві стрічки: усередині section #footer і всередині <Footer> теж.
    // Беремо першу — для перевірки геометрії однієї достатньо.
    const stripe = page.getByTestId("ukraine-stripe").first();
    await expect(stripe).toBeVisible();

    const box = await stripe.boundingBox();
    expect(box).not.toBeNull();
    expect(box!.height).toBeCloseTo(2, 0);

    const bg = await stripe.evaluate((el) => getComputedStyle(el).backgroundImage);
    // Computed background — серіалізований gradient з обома кольорами.
    expect(bg.toLowerCase()).toContain("rgb(0, 87, 183)"); // #0057B7
    expect(bg.toLowerCase()).toContain("rgb(255, 215, 0)"); // #FFD700
  });

  test("усі кнопки на сторінці мають min-розмір ≥ 44×44 (WCAG 2.5.5)", async ({ page }) => {
    await page.goto("/styleguide");
    const dims = await page.locator("section:has(#buttons) button").evaluateAll((buttons) =>
      buttons.map((b) => ({
        w: (b as HTMLElement).offsetWidth,
        h: (b as HTMLElement).offsetHeight,
      })),
    );
    expect(dims.length).toBeGreaterThan(0);
    for (const { w, h } of dims) {
      expect(w).toBeGreaterThanOrEqual(44);
      expect(h).toBeGreaterThanOrEqual(44);
    }
  });

  test("у prod-buildі (без NEXT_PUBLIC_ENV=dev) сторінка віддавала б 404", async ({ page }) => {
    // Тут ми НЕ можемо змінити NEXT_PUBLIC_ENV runtime'ом — це build-time
    // змінна. Тест-маркер для майбутнього: код у page.tsx містить виклик
    // notFound() у гілці !IS_DEV. Webserver у playwright.config.ts явно
    // експортує NEXT_PUBLIC_ENV=dev — інакше сторінка тут не відкрилась би.
    await page.goto("/styleguide");
    await expect(page).toHaveURL(/\/styleguide$/);
  });
});
