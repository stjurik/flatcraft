import { expect, test, type Page } from "@playwright/test";

const VIEWPORTS = [
  { name: "mobile-360", width: 360, height: 640 },
  { name: "tablet-768", width: 768, height: 1024 },
  { name: "desktop-1280", width: 1280, height: 800 },
] as const;

test.describe("/about (Phase X.1 D)", () => {
  test("чотири секції рендеряться", async ({ page }) => {
    await page.goto("/about");
    await expect(page.getByTestId("about-hero")).toContainText("Креслення листового металу");
    await expect(page.getByTestId("about-what")).toBeVisible();
    await expect(page.getByTestId("about-free")).toBeVisible();
    await expect(page.getByTestId("about-zsu")).toBeVisible();
    await expect(page.getByTestId("about-feedback")).toBeVisible();
  });

  test("ЗСУ-кнопки мають правильні href + target", async ({ page }) => {
    await page.goto("/about");
    const mono = page.getByTestId("about-donate-monobank");
    await expect(mono).toHaveAttribute("href", "https://send.monobank.ua/jar/A1u3M7VqQz");
    await expect(mono).toHaveAttribute("target", "_blank");
    const u24 = page.getByTestId("about-donate-united24");
    await expect(u24).toHaveAttribute("href", "https://u24.gov.ua/");
    await expect(u24).toHaveAttribute("target", "_blank");
    await expect(page.getByTestId("about-feedback-email")).toHaveAttribute(
      "href",
      "mailto:feedback@hart.crimea.ua",
    );
  });

  test("Footer SiteLinks «Про проєкт» веде на /about (не /soon)", async ({ page }) => {
    await page.goto("/");
    const aboutLink = page.getByTestId("site-links").getByRole("link", { name: "Про проєкт" });
    await expect(aboutLink).toHaveAttribute("href", "/about");
    await aboutLink.click();
    await expect(page).toHaveURL(/\/about$/);
    await expect(page.getByTestId("about-hero")).toBeVisible();
  });

  test("Footer Discord-лінк — зовнішній інвайт (не /soon)", async ({ page }) => {
    await page.goto("/");
    const discord = page.getByTestId("site-links").getByRole("link", { name: /Discord/ });
    await expect(discord).toHaveAttribute("href", /^https:\/\/discord\.gg\//);
    await expect(discord).toHaveAttribute("target", "_blank");
  });

  test("/about: Discord-спільнота — зовнішнє посилання", async ({ page }) => {
    await page.goto("/about");
    const discord = page.getByTestId("about-feedback-discord");
    await expect(discord).toHaveAttribute("href", /^https:\/\/discord\.gg\//);
    await expect(discord).toHaveAttribute("target", "_blank");
  });

  for (const { name, width, height } of VIEWPORTS) {
    test(`console-clean + tap-targets ≥44 на ${name}`, async ({ page }: { page: Page }) => {
      const errors: string[] = [];
      page.on("console", (msg) => {
        if (msg.type() === "error") errors.push(msg.text());
      });
      await page.setViewportSize({ width, height });
      await page.goto("/about");
      await expect(page.getByTestId("about-hero")).toBeVisible();

      for (const id of [
        "about-donate-monobank",
        "about-donate-united24",
        "about-feedback-email",
        "about-feedback-github",
      ]) {
        const box = await page.getByTestId(id).boundingBox();
        expect(box, `${id} має bounding box`).not.toBeNull();
        expect(box!.height).toBeGreaterThanOrEqual(44);
      }
      expect(errors, errors.join("\n")).toEqual([]);
    });
  }
});
