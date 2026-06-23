import { expect, test } from "@playwright/test";

// PR 8b: enclosed_shelf переведено у Вироби (`/products/closed-shelf-standard`),
// тому в parts-каталозі знов 5 deталей (як до PR 7d).
const EXPECTED: ReadonlyArray<{ slug: string; name: string; hasPreview: boolean }> = [
  { slug: "l_bracket", name: "L-кронштейн", hasPreview: true },
  { slug: "z_bracket", name: "Z-кронштейн", hasPreview: true },
  { slug: "corner_angle", name: "Кутник", hasPreview: true },
  { slug: "wall_shelf", name: "Полиця настінна", hasPreview: true },
  { slug: "perforated_panel", name: "Перфо-панель", hasPreview: true },
];

const VIEWPORTS = [
  { name: "mobile-360", width: 360, height: 640 },
  { name: "tablet-768", width: 768, height: 1024 },
  { name: "desktop-1280", width: 1280, height: 800 },
] as const;

test.describe("Каталог /templates?tab=parts (Phase 2.13 → Phase 3.0)", () => {
  test("hero + усі 5 опублікованих шаблонів під ?tab=parts", async ({ page }) => {
    const consoleErrors: string[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") consoleErrors.push(msg.text());
    });

    await page.goto("/templates?tab=parts");
    // Phase 3.0: заголовок змінено на "Каталог" (двомодовий — Вироби + Деталі).
    await expect(page.getByTestId("templates-page-title")).toHaveText("Каталог");

    for (const { slug, name, hasPreview } of EXPECTED) {
      const card = page.locator(`[data-testid="template-card"][data-slug="${slug}"]`);
      await expect(card).toBeVisible();
      await expect(card).toContainText(name);
      if (hasPreview) {
        // Phase 2.16.b: previewImageUrl задано → рендериться <img>, не SVG-thumb.
        const img = card.locator("img");
        await expect(img).toBeVisible();
        await expect(img).toHaveAttribute("src", new RegExp(`/template-previews/${slug}\\.png$`));
      }
    }

    expect(consoleErrors, consoleErrors.join("\n")).toEqual([]);
  });

  test("CTA «Налаштувати →» на кожній картці веде на /templates/:slug", async ({ page }) => {
    await page.goto("/templates?tab=parts");
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
    await page.goto("/templates?tab=parts");
    const titleLink = page
      .locator('[data-testid="template-card"][data-slug="l_bracket"]')
      .getByTestId("template-card-title-link");
    await expect(titleLink).toHaveAttribute("href", "/templates/l_bracket");
    await titleLink.click();
    await expect(page).toHaveURL(/\/templates\/l_bracket$/);
  });

  test("tap-targets усіх CTA ≥ 44×44px (WCAG 2.5.5)", async ({ page }) => {
    await page.goto("/templates?tab=parts");
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
      await page.goto("/templates?tab=parts");
      await expect(page.getByTestId("templates-grid")).toBeVisible();
      expect(errors, errors.join("\n")).toEqual([]);
    });
  }
});
