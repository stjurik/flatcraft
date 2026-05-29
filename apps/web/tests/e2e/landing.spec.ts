import { expect, test } from "@playwright/test";

test.describe("Landing page (Phase 0.5 hello-world)", () => {
  test("показує hero-заголовок і фазовий маркер", async ({ page }) => {
    await page.goto("/");
    await expect(page.getByTestId("hero-title")).toHaveText("flatcraft");
    await expect(page.getByTestId("phase-marker")).toContainText("Phase 0.5");
    await expect(page.getByTestId("viewport-frame")).toBeVisible();
  });

  test("CTA веде на каталог шаблонів", async ({ page }) => {
    await page.goto("/");
    const cta = page.getByTestId("cta-templates");
    await expect(cta).toHaveAttribute("href", "/templates");
    await cta.click();
    await expect(page).toHaveURL(/\/templates$/);
    await expect(page.getByTestId("templates-page-title")).toBeVisible();
  });

  test("react-three-fiber Canvas рендериться (наявний <canvas>)", async ({ page }) => {
    const consoleErrors: string[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") consoleErrors.push(msg.text());
    });

    await page.goto("/");

    // dynamic({ssr:false}) → canvas з'являється після завантаження client-chunk.
    const canvas = page.locator("canvas").first();
    await expect(canvas).toBeVisible({ timeout: 15_000 });

    // WebGL контекст реально активний — кадр відмалював width/height > 0.
    const dimensions = await canvas.evaluate((el: HTMLCanvasElement) => ({
      width: el.width,
      height: el.height,
    }));
    expect(dimensions.width).toBeGreaterThan(0);
    expect(dimensions.height).toBeGreaterThan(0);

    expect(consoleErrors, consoleErrors.join("\n")).toEqual([]);
  });
});
