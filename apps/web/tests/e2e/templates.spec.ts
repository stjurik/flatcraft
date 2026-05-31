import { expect, test } from "@playwright/test";

const EXPECTED: ReadonlyArray<{ slug: string; name: string }> = [
  { slug: "l_bracket", name: "L-кронштейн" },
  { slug: "z_bracket", name: "Z-кронштейн" },
  { slug: "corner_angle", name: "Кутник" },
  { slug: "wall_shelf", name: "Полиця настінна" },
  { slug: "perforated_panel", name: "Перфо-панель" },
];

const VIEWPORTS = [
  { name: "mobile-360", width: 360, height: 640 },
  { name: "tablet-768", width: 768, height: 1024 },
  { name: "desktop-1280", width: 1280, height: 800 },
] as const;

test.describe("Каталог /templates (Phase 2.13)", () => {
  test("hero + усі 5 опублікованих шаблонів — Phase 2.10 закрита", async ({ page }) => {
    const consoleErrors: string[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") consoleErrors.push(msg.text());
    });

    await page.goto("/templates");
    await expect(page.getByTestId("templates-page-title")).toHaveText("Каталог шаблонів");

    for (const { slug, name } of EXPECTED) {
      const card = page.locator(`[data-testid="template-card"][data-slug="${slug}"]`);
      await expect(card).toBeVisible();
      await expect(card).toContainText(name);
      // SVG thumb або img — у будь-якому випадку <svg> з відповідним testId
      // (за відсутності previewImageUrl, що поки правда для всіх 5 seed-row).
      await expect(card.locator(`[data-testid="template-thumb-${slug}"]`)).toBeVisible();
    }

    expect(consoleErrors, consoleErrors.join("\n")).toEqual([]);
  });

  test("CTA «Налаштувати →» на кожній картці веде на /templates/:slug", async ({ page }) => {
    await page.goto("/templates");
    for (const { slug } of EXPECTED) {
      const cta = page
        .locator(`[data-testid="template-card"][data-slug="${slug}"]`)
        .getByTestId("template-card-cta");
      await expect(cta).toBeVisible();
      await expect(cta).toContainText("Налаштувати");
      await expect(cta).toHaveAttribute("href", `/templates/${slug}`);
    }
  });

  test("title h3-link теж клікабельний і веде на /templates/:slug", async ({ page }) => {
    await page.goto("/templates");
    const titleLink = page
      .locator('[data-testid="template-card"][data-slug="l_bracket"]')
      .getByTestId("template-card-title-link");
    await expect(titleLink).toHaveAttribute("href", "/templates/l_bracket");
    await titleLink.click();
    await expect(page).toHaveURL(/\/templates\/l_bracket$/);
  });

  test("tap-targets усіх CTA ≥ 44×44px (WCAG 2.5.5)", async ({ page }) => {
    await page.goto("/templates");
    const dims = await page.getByTestId("template-card-cta").evaluateAll((ctas) =>
      ctas.map((el) => ({
        w: (el as HTMLElement).offsetWidth,
        h: (el as HTMLElement).offsetHeight,
      })),
    );
    expect(dims.length).toBe(EXPECTED.length);
    for (const { w, h } of dims) {
      expect(w).toBeGreaterThanOrEqual(44);
      expect(h).toBeGreaterThanOrEqual(44);
    }
  });

  for (const { name, width, height } of VIEWPORTS) {
    test(`console-clean на ${name}`, async ({ page }) => {
      const errors: string[] = [];
      page.on("console", (msg) => {
        if (msg.type() === "error") errors.push(msg.text());
      });
      await page.setViewportSize({ width, height });
      await page.goto("/templates");
      await expect(page.getByTestId("templates-grid")).toBeVisible();
      expect(errors, errors.join("\n")).toEqual([]);
    });
  }
});
