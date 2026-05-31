import { expect, test, type Page } from "@playwright/test";

const VIEWPORTS = [
  { name: "mobile-360", width: 360, height: 640 },
  { name: "tablet-768", width: 768, height: 1024 },
  { name: "desktop-1280", width: 1280, height: 800 },
] as const;

async function collectErrors(page: Page): Promise<string[]> {
  const errors: string[] = [];
  page.on("console", (msg) => {
    if (msg.type() === "error") errors.push(msg.text());
  });
  return errors;
}

test.describe("Landing (Phase 2.12.b — hero + how-it-works + trust)", () => {
  test("hero: headline + CTA + secondary anchor", async ({ page }) => {
    await page.goto("/");
    await expect(page.getByTestId("hero-headline")).toContainText("Креслення листового металу");
    const cta = page.getByTestId("hero-cta");
    await expect(cta).toBeVisible();
    await expect(cta).toHaveAttribute("href", "/templates");
    await expect(page.getByTestId("hero-anchor-how")).toHaveAttribute("href", "#how");
  });

  test("CTA веде на каталог шаблонів", async ({ page }) => {
    await page.goto("/");
    await page.getByTestId("hero-cta").click();
    await expect(page).toHaveURL(/\/templates$/);
  });

  test("anchor «Як це працює ↓» скролить до #how", async ({ page }) => {
    await page.goto("/");
    await page.getByTestId("hero-anchor-how").click();
    // Після scroll секція має бути у viewport (top ≤ viewport.height).
    const top = await page.locator("#how").evaluate((el) => el.getBoundingClientRect().top);
    const vh = page.viewportSize()?.height ?? 720;
    expect(top).toBeLessThan(vh);
  });

  test("3 step-cards присутні з очікуваними заголовками", async ({ page }) => {
    await page.goto("/");
    await expect(page.getByTestId("step-card-0")).toContainText("Оберіть шаблон");
    await expect(page.getByTestId("step-card-1")).toContainText("Налаштуйте розміри");
    await expect(page.getByTestId("step-card-2")).toContainText("Скачайте креслення");
  });

  test("3 trust-блоки з лінками на UNITED24 і GitHub", async ({ page }) => {
    await page.goto("/");
    await expect(page.getByTestId("trust-block-0")).toContainText("10 експортів");
    const u24 = page.getByTestId("trust-block-1").getByRole("link");
    await expect(u24).toHaveAttribute("href", "https://u24.gov.ua/");
    const gh = page.getByTestId("trust-block-2").getByRole("link");
    await expect(gh).toHaveAttribute("href", /github\.com\/stjurik\/flatcraft/);
  });

  test("HeroLoopDemo рендериться канвас (RAF режим)", async ({ page }) => {
    await page.goto("/");
    const canvas = page.locator("canvas").first();
    await expect(canvas).toBeVisible({ timeout: 15_000 });
    const dim = await canvas.evaluate((el: HTMLCanvasElement) => ({ w: el.width, h: el.height }));
    expect(dim.w).toBeGreaterThan(0);
    expect(dim.h).toBeGreaterThan(0);
    // Badge «Live demo» поверх canvas.
    await expect(page.getByTestId("hero-loop-badge")).toBeVisible();
    // У звичайному режимі reduced-motion caption відсутній.
    await expect(page.getByTestId("hero-loop-reduced-caption")).toHaveCount(0);
  });

  test("prefers-reduced-motion=reduce → caption видимий, data-reduced-motion=true", async ({
    page,
  }) => {
    // page.emulateMedia() реально пропадає у matchMedia (test.use({reducedMotion})
    // у Playwright 1.48 не доходить до query — лише до CSS).
    await page.emulateMedia({ reducedMotion: "reduce" });
    await page.goto("/");
    const demo = page.getByTestId("hero-loop-demo");
    await expect(demo).toBeVisible({ timeout: 15_000 });
    await expect(demo).toHaveAttribute("data-reduced-motion", "true");
    await expect(page.getByTestId("hero-loop-reduced-caption")).toBeVisible();
  });

  for (const { name, width, height } of VIEWPORTS) {
    test(`console-clean на ${name}`, async ({ page }) => {
      const errors = await collectErrors(page);
      await page.setViewportSize({ width, height });
      await page.goto("/");
      await expect(page.getByTestId("hero-headline")).toBeVisible();
      // дайте лазі-bundle отрисувати canvas (без strict-wait — лише canvas check).
      await page.locator("canvas").first().waitFor({ state: "visible", timeout: 15_000 });
      expect(errors, errors.join("\n")).toEqual([]);
    });
  }

  test("tap-targets hero/anchor/cta ≥ 44×44px (WCAG 2.5.5)", async ({ page }) => {
    await page.goto("/");
    const ids = ["hero-cta", "hero-anchor-how"];
    for (const id of ids) {
      const dim = await page
        .getByTestId(id)
        .evaluate((el: HTMLElement) => ({ w: el.offsetWidth, h: el.offsetHeight }));
      expect(dim.w, `${id} width`).toBeGreaterThanOrEqual(44);
      expect(dim.h, `${id} height`).toBeGreaterThanOrEqual(44);
    }
  });

  test("/soon — placeholder сторінка для майбутніх лінків", async ({ page }) => {
    await page.goto("/soon");
    await expect(page.getByRole("heading", { name: "Запланована сторінка" })).toBeVisible();
    await expect(page.getByRole("link", { name: "← На головну" })).toHaveAttribute("href", "/");
  });
});
