import { expect, test, type Page } from "@playwright/test";

const VIEWPORTS = [
  { name: "mobile-360", width: 360, height: 640 },
  { name: "desktop-1280", width: 1280, height: 800 },
] as const;

const SECTIONS = [
  "about",
  "usage",
  "acceptable-use",
  "drawings-liability",
  "donations",
  "ip",
  "changes",
  "uptime",
] as const;

test.describe("/terms (WP3 legal-мінімум)", () => {
  test("UA версія: draft-банер + 8 секцій + drawings-liability явно про рекомендаційність", async ({
    page,
  }) => {
    await page.goto("/terms");
    await expect(page.getByTestId("terms-draft-banner")).toContainText(/Драфт/);
    await expect(page.getByTestId("terms-hero")).toContainText("Умови користування");
    for (const id of SECTIONS) {
      await expect(page.getByTestId(`terms-section-${id}`)).toBeVisible();
    }
    // ключове застереження R-09 — must be there
    await expect(page.getByTestId("terms-section-drawings-liability")).toContainText(
      /рекомендаційна/,
    );
  });

  test("EN версія: draft banner + 8 sections", async ({ page }) => {
    await page.goto("/terms/en");
    await expect(page.getByTestId("terms-draft-banner")).toContainText(/Draft/);
    await expect(page.getByTestId("terms-hero")).toContainText("Terms of Service");
    for (const id of SECTIONS) {
      await expect(page.getByTestId(`terms-section-${id}`)).toBeVisible();
    }
  });

  test("Footer SiteLinks «Terms» веде на /terms (не /soon)", async ({ page }) => {
    await page.goto("/");
    const link = page.getByTestId("site-links").getByRole("link", { name: "Terms" });
    await expect(link).toHaveAttribute("href", "/terms");
    await link.click();
    await expect(page).toHaveURL(/\/terms$/);
    await expect(page.getByTestId("terms-hero")).toBeVisible();
  });

  test("UA→EN cross-link працює", async ({ page }) => {
    await page.goto("/terms");
    await page.getByRole("link", { name: "/terms/en" }).click();
    await expect(page).toHaveURL(/\/terms\/en$/);
    await expect(page.getByTestId("terms-hero")).toContainText("Terms of Service");
  });

  for (const { name, width, height } of VIEWPORTS) {
    test(`console-clean на ${name}`, async ({ page }: { page: Page }) => {
      const errors: string[] = [];
      page.on("console", (msg) => {
        if (msg.type() === "error") errors.push(msg.text());
      });
      await page.setViewportSize({ width, height });
      await page.goto("/terms");
      await page.waitForLoadState("networkidle");
      expect(errors, `Console errors: ${errors.join(" | ")}`).toEqual([]);
    });
  }
});
