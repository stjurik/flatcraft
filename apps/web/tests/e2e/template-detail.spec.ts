import { expect, test } from "@playwright/test";

test.describe("/templates/[slug] — L-bracket studio (Phase 2.2)", () => {
  test("картка → деталь L-bracket: заголовок, форма з defaults, R3F canvas", async ({ page }) => {
    const consoleErrors: string[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") consoleErrors.push(msg.text());
    });

    await page.goto("/templates");
    await page.locator('[data-testid="template-card"][data-slug="l_bracket"]').click();

    await expect(page).toHaveURL("/templates/l_bracket");
    await expect(page.getByTestId("template-detail-title")).toHaveText("L-кронштейн");
    await expect(page.getByTestId("l-bracket-studio")).toBeVisible();
    await expect(page.getByTestId("l-bracket-editor")).toBeVisible();

    // Дефолтні значення з seed (L_BRACKET_DEFAULT_PARAMETERS).
    await expect(page.getByTestId("param-legA_mm")).toHaveValue("60");
    await expect(page.getByTestId("param-legB_mm")).toHaveValue("60");
    await expect(page.getByTestId("param-width_mm")).toHaveValue("100");
    await expect(page.getByTestId("param-bend_radius_mm")).toHaveValue("2.5");
    await expect(page.getByTestId("validation-ok")).toBeVisible();

    // 3D viewport — Canvas з'являється після dynamic chunk load.
    await expect(page.getByTestId("l-bracket-viewport")).toBeVisible();
    const canvas = page.getByTestId("l-bracket-viewport").locator("canvas");
    await expect(canvas).toBeVisible({ timeout: 15_000 });
    const dims = await canvas.evaluate((el: HTMLCanvasElement) => ({
      w: el.width,
      h: el.height,
    }));
    expect(dims.w).toBeGreaterThan(0);
    expect(dims.h).toBeGreaterThan(0);

    expect(consoleErrors, consoleErrors.join("\n")).toEqual([]);
  });

  test("параметр поза діапазоном → showsValidationError + підсвічення поля", async ({ page }) => {
    await page.goto("/templates/l_bracket");
    await expect(page.getByTestId("validation-ok")).toBeVisible();
    // Дефолтне поле — не invalid.
    await expect(page.getByTestId("field-legA_mm")).toHaveAttribute("data-invalid", "false");

    // legA_mm < 20 → Zod min(20) fails.
    await page.getByTestId("param-legA_mm").fill("10");

    // Summary list з'явився.
    await expect(page.getByTestId("validation-errors")).toBeVisible();
    await expect(page.getByTestId("validation-ok")).toHaveCount(0);

    // Конкретне поле підсвічене: data-invalid=true + aria-invalid + inline error.
    await expect(page.getByTestId("field-legA_mm")).toHaveAttribute("data-invalid", "true");
    await expect(page.getByTestId("param-legA_mm")).toHaveAttribute("aria-invalid", "true");
    await expect(page.getByTestId("field-error-legA_mm")).toBeVisible();

    // Інші поля лишаються невинуватими.
    await expect(page.getByTestId("field-legB_mm")).toHaveAttribute("data-invalid", "false");
    await expect(page.getByTestId("field-error-legB_mm")).toHaveCount(0);
  });

  test("виправлення значення прибирає підсвічення", async ({ page }) => {
    await page.goto("/templates/l_bracket");
    await page.getByTestId("param-legA_mm").fill("10");
    await expect(page.getByTestId("field-legA_mm")).toHaveAttribute("data-invalid", "true");

    // Повертаємо у валідний діапазон.
    await page.getByTestId("param-legA_mm").fill("80");
    await expect(page.getByTestId("field-legA_mm")).toHaveAttribute("data-invalid", "false");
    await expect(page.getByTestId("field-error-legA_mm")).toHaveCount(0);
    await expect(page.getByTestId("validation-ok")).toBeVisible();
  });

  test("зміна параметра live-update'ить JSON preview", async ({ page }) => {
    await page.goto("/templates/l_bracket");
    await expect(page.getByTestId("params-preview")).toContainText('"legA_mm": 60');

    await page.getByTestId("param-legA_mm").fill("120");

    await expect(page.getByTestId("params-preview")).toContainText('"legA_mm": 120');
    // Canvas після зміни лишається видимим (mesh перегенеровано).
    await expect(page.getByTestId("l-bracket-viewport").locator("canvas")).toBeVisible();
  });

  test("Export → mock API → presigned download link", async ({ page }) => {
    const mockResponse = {
      dxf_url: "https://example-bucket.s3.amazonaws.com/exports/test.dxf?Signature=abc&Expires=999",
      bytes: 16384,
      expires_at: "2026-05-17T00:00:00.000Z",
      s3_key: "exports/test.dxf",
    };
    let received: unknown = null;
    await page.route("**/exports", async (route) => {
      received = route.request().postDataJSON();
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify(mockResponse),
      });
    });

    await page.goto("/templates/l_bracket");
    const exportBtn = page.getByTestId("export-button");
    await expect(exportBtn).toBeEnabled();
    await expect(exportBtn).toHaveAttribute("data-state", "idle");

    await exportBtn.click();

    await expect(page.getByTestId("export-download-link")).toBeVisible({ timeout: 5_000 });
    await expect(exportBtn).toHaveAttribute("data-state", "success");
    const href = await page.getByTestId("export-download-link").getAttribute("href");
    expect(href).toBe(mockResponse.dxf_url);
    expect(received).toMatchObject({
      template_slug: "l_bracket",
      thickness_mm: 2,
      parameters: { legA_mm: 60, legB_mm: 60, bend_radius_mm: 2.5 },
    });
  });

  test("Export disabled коли параметри невалідні", async ({ page }) => {
    await page.goto("/templates/l_bracket");
    await expect(page.getByTestId("export-button")).toBeEnabled();

    await page.getByTestId("param-legA_mm").fill("10");
    await expect(page.getByTestId("export-button")).toBeDisabled();
  });

  test("Export показує помилку коли API повертає 5xx", async ({ page }) => {
    await page.route("**/exports", (route) =>
      route.fulfill({
        status: 502,
        contentType: "application/json",
        body: JSON.stringify({ error: "cad_worker_failed", status: 500 }),
      }),
    );

    await page.goto("/templates/l_bracket");
    await page.getByTestId("export-button").click();

    await expect(page.getByTestId("export-error")).toBeVisible();
    await expect(page.getByTestId("export-button")).toHaveAttribute("data-state", "error");
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
