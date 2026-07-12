import { expect, test, type Page } from "@playwright/test";

const VIEWPORTS = [
  { name: "mobile-360", width: 360, height: 640 },
  { name: "desktop-1280", width: 1280, height: 800 },
] as const;

const SECTIONS = [
  "pii",
  "cookies",
  "sentry",
  "location",
  "backups",
  "donations",
  "drawings",
  "uptime",
] as const;

test.describe("/privacy (WP3 legal-мінімум)", () => {
  test("UA версія: draft-банер + 8 змістовних секцій", async ({ page }) => {
    await page.goto("/privacy");
    await expect(page.getByTestId("privacy-draft-banner")).toContainText(/Драфт/);
    await expect(page.getByTestId("privacy-hero")).toContainText("Політика приватності");
    for (const id of SECTIONS) {
      await expect(page.getByTestId(`privacy-section-${id}`)).toBeVisible();
    }
  });

  test("EN версія: draft banner + 8 sections", async ({ page }) => {
    await page.goto("/privacy/en");
    await expect(page.getByTestId("privacy-draft-banner")).toContainText(/Draft/);
    await expect(page.getByTestId("privacy-hero")).toContainText("Privacy Policy");
    for (const id of SECTIONS) {
      await expect(page.getByTestId(`privacy-section-${id}`)).toBeVisible();
    }
  });

  test("Footer SiteLinks «Privacy» веде на /privacy (не /soon)", async ({ page }) => {
    await page.goto("/");
    const link = page.getByTestId("site-links").getByRole("link", { name: "Privacy" });
    await expect(link).toHaveAttribute("href", "/privacy");
    await link.click();
    await expect(page).toHaveURL(/\/privacy$/);
    await expect(page.getByTestId("privacy-hero")).toBeVisible();
  });

  test("Footer cookie-note: «Без трекінг-cookies» видимий на головній", async ({ page }) => {
    await page.goto("/");
    await expect(page.getByTestId("site-cookie-note")).toContainText(/Без трекінг-cookies/);
  });

  test("UA→EN cross-link працює", async ({ page }) => {
    await page.goto("/privacy");
    await page.getByRole("link", { name: "/privacy/en" }).click();
    await expect(page).toHaveURL(/\/privacy\/en$/);
    await expect(page.getByTestId("privacy-hero")).toContainText("Privacy Policy");
  });

  test("Cookies-anchor у SiteLinks веде на /privacy#cookies", async ({ page }) => {
    await page.goto("/");
    const link = page.getByTestId("site-links").getByRole("link", { name: "Cookies" });
    await expect(link).toHaveAttribute("href", "/privacy#cookies");
  });

  for (const { name, width, height } of VIEWPORTS) {
    test(`console-clean на ${name}`, async ({ page }: { page: Page }) => {
      const errors: string[] = [];
      page.on("console", (msg) => {
        if (msg.type() === "error") errors.push(msg.text());
      });
      await page.setViewportSize({ width, height });
      await page.goto("/privacy");
      await page.waitForLoadState("networkidle");
      expect(errors, `Console errors: ${errors.join(" | ")}`).toEqual([]);
    });
  }
});
