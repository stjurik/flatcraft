import { expect, test } from "@playwright/test";

test.describe("/templates/[slug] — L-bracket editor (Phase 2.2)", () => {
  test("картка → деталь L-bracket: заголовок, форма з defaults, валідація", async ({ page }) => {
    const consoleErrors: string[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") consoleErrors.push(msg.text());
    });

    await page.goto("/templates");
    await page.locator('[data-testid="template-card"][data-slug="l_bracket"]').click();

    await expect(page).toHaveURL("/templates/l_bracket");
    await expect(page.getByTestId("template-detail-title")).toHaveText("L-кронштейн");
    await expect(page.getByTestId("template-detail-slug")).toHaveText("l_bracket");
    await expect(page.getByTestId("l-bracket-editor")).toBeVisible();

    // Дефолтні значення з seed (L_BRACKET_DEFAULT_PARAMETERS).
    await expect(page.getByTestId("param-legA_mm")).toHaveValue("60");
    await expect(page.getByTestId("param-legB_mm")).toHaveValue("60");
    await expect(page.getByTestId("param-width_mm")).toHaveValue("100");
    await expect(page.getByTestId("param-bend_radius_mm")).toHaveValue("2.5");

    // Дефолтні значення валідні.
    await expect(page.getByTestId("validation-ok")).toBeVisible();

    // 3D viewport — поки що placeholder.
    await expect(page.getByTestId("template-detail-viewport-placeholder")).toBeVisible();

    expect(consoleErrors, consoleErrors.join("\n")).toEqual([]);
  });

  test("параметр поза діапазоном → showsValidationError", async ({ page }) => {
    await page.goto("/templates/l_bracket");
    await expect(page.getByTestId("validation-ok")).toBeVisible();

    // legA_mm < 20 → Zod min(20) fails.
    await page.getByTestId("param-legA_mm").fill("10");

    await expect(page.getByTestId("validation-errors")).toBeVisible();
    await expect(page.getByTestId("validation-ok")).toHaveCount(0);
  });

  test("неіснуючий шаблон → 404", async ({ page }) => {
    const res = await page.goto("/templates/does_not_exist");
    expect(res?.status()).toBe(404);
  });

  test("неопублікований z_bracket → 404", async ({ page }) => {
    const res = await page.goto("/templates/z_bracket");
    expect(res?.status()).toBe(404);
  });
});
