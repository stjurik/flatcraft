import { expect, test } from "@playwright/test";

const VIEWPORTS = [
  { name: "mobile-360", width: 360, height: 640 },
  { name: "tablet-768", width: 768, height: 1024 },
  { name: "desktop-1280", width: 1280, height: 800 },
] as const;

test.describe("Каталог-toggle Вироби | Деталі (Phase 3.0 PR 3, ADR-027)", () => {
  test("default /templates відкриває tab=products активним", async ({ page }) => {
    await page.goto("/templates");
    await expect(page.getByTestId("catalog-toggle")).toBeVisible();
    const productsBtn = page.getByTestId("catalog-toggle-item-products");
    const partsBtn = page.getByTestId("catalog-toggle-item-parts");
    await expect(productsBtn).toHaveAttribute("aria-pressed", "true");
    await expect(partsBtn).toHaveAttribute("aria-pressed", "false");
  });

  test("URL ?tab=parts активує partsBtn", async ({ page }) => {
    await page.goto("/templates?tab=parts");
    await expect(page.getByTestId("catalog-toggle-item-parts")).toHaveAttribute(
      "aria-pressed",
      "true",
    );
    await expect(page.getByTestId("catalog-toggle-item-products")).toHaveAttribute(
      "aria-pressed",
      "false",
    );
    // Grid шаблонів видимий.
    await expect(page.getByTestId("templates-grid")).toBeVisible();
  });

  test("клік на Деталі — URL стає ?tab=parts, активний parts, grid templates видимий", async ({
    page,
  }) => {
    await page.goto("/templates");
    await page.getByTestId("catalog-toggle-item-parts").click();
    await expect(page).toHaveURL(/\?tab=parts$/);
    await expect(page.getByTestId("catalog-toggle-item-parts")).toHaveAttribute(
      "aria-pressed",
      "true",
    );
    await expect(page.getByTestId("templates-grid")).toBeVisible();
  });

  test("клік на Вироби з ?tab=parts — URL чистий, активний products", async ({ page }) => {
    await page.goto("/templates?tab=parts");
    await page.getByTestId("catalog-toggle-item-products").click();
    // Default — без query param у URL (PR 3 design: чистий /templates).
    await expect(page).toHaveURL(/\/templates$/);
    await expect(page.getByTestId("catalog-toggle-item-products")).toHaveAttribute(
      "aria-pressed",
      "true",
    );
  });

  test("кліки на parts-картку ведуть на /templates/:slug (existing flow)", async ({ page }) => {
    await page.goto("/templates?tab=parts");
    await page
      .locator('[data-testid="template-card"][data-slug="l_bracket"]')
      .getByTestId("template-card-cta")
      .click();
    await expect(page).toHaveURL(/\/templates\/l_bracket$/);
  });

  test("products grid порожній на PR 3 — empty-state з ясним посиланням на PR 6", async ({
    page,
  }) => {
    await page.goto("/templates");
    // PR 3 seed має лише placeholder isPublished=false → /products повертає [].
    await expect(page.getByTestId("products-empty")).toBeVisible();
    await expect(page.getByTestId("products-empty")).toContainText("PR 6");
  });

  test("tap-targets обох tab-items ≥ 44×44px (WCAG 2.5.5)", async ({ page }) => {
    await page.goto("/templates");
    const items = page.locator('[data-testid^="catalog-toggle-item-"]');
    const dims = await items.evaluateAll((els) =>
      els.map((el) => ({
        w: (el as HTMLElement).offsetWidth,
        h: (el as HTMLElement).offsetHeight,
      })),
    );
    expect(dims.length).toBe(2);
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
      await expect(page.getByTestId("catalog-toggle")).toBeVisible();
      expect(errors, errors.join("\n")).toEqual([]);
    });
  }
});
