import { expect, test } from "@playwright/test";

test.describe("/templates/z_bracket — Z-bracket studio (Phase 2.10)", () => {
  test("картка → деталь Z-bracket: заголовок, форма з defaults, R3F canvas", async ({ page }) => {
    const consoleErrors: string[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") consoleErrors.push(msg.text());
    });

    await page.goto("/templates?tab=parts");
    await page
      .locator('[data-testid="template-card"][data-slug="z_bracket"]')
      .getByTestId("template-card-cta")
      .click();

    await expect(page).toHaveURL("/templates/z_bracket");
    await expect(page.getByTestId("template-detail-title")).toHaveText("Z-кронштейн");
    await expect(page.getByTestId("z-bracket-studio")).toBeVisible();
    await expect(page.getByTestId("z-bracket-editor")).toBeVisible();

    // Дефолти з seed (Z_BRACKET_DEFAULT_PARAMETERS).
    await expect(page.getByTestId("param-top_flange_mm")).toHaveValue("60");
    await expect(page.getByTestId("param-bottom_flange_mm")).toHaveValue("60");
    await expect(page.getByTestId("param-offset_mm")).toHaveValue("40");
    await expect(page.getByTestId("param-bend_radius_mm")).toHaveValue("2.5");
    await expect(page.getByTestId("validation-ok")).toBeVisible();

    // 3D viewport.
    await expect(page.getByTestId("z-bracket-viewport")).toBeVisible();
    const canvas = page.getByTestId("z-bracket-viewport").locator("canvas");
    await expect(canvas).toBeVisible({ timeout: 15_000 });
    const dims = await canvas.evaluate((el: HTMLCanvasElement) => ({
      w: el.width,
      h: el.height,
    }));
    expect(dims.w).toBeGreaterThan(0);
    expect(dims.h).toBeGreaterThan(0);

    expect(consoleErrors, consoleErrors.join("\n")).toEqual([]);
  });

  test("offset поза діапазоном → invalid поле + export disabled", async ({ page }) => {
    await page.goto("/templates/z_bracket");
    await expect(page.getByTestId("export-button")).toBeEnabled();

    await page.getByTestId("param-offset_mm").fill("10");
    await expect(page.getByTestId("field-offset_mm")).toHaveAttribute("data-invalid", "true");
    await expect(page.getByTestId("export-button")).toBeDisabled();
  });

  test("Export → mock API → DXF + PDF посилання", async ({ page }) => {
    const jobId = "33333333-4444-5555-6666-777777777777";
    const result = {
      artifacts: {
        dxf: {
          url: "https://example-bucket.s3.amazonaws.com/z.dxf?Signature=abc&Expires=999",
          bytes: 16384,
          expires_at: "2026-05-18T00:00:00.000Z",
          s3_key: "exports/z.dxf",
        },
        pdf: {
          url: "https://example-bucket.s3.amazonaws.com/z.pdf?Signature=abc&Expires=999",
          bytes: 8192,
          expires_at: "2026-05-18T00:00:00.000Z",
          s3_key: "exports/z.pdf",
        },
      },
    };
    let received: unknown = null;
    await page.route(/\/exports$/, async (route) => {
      received = route.request().postDataJSON();
      await route.fulfill({
        status: 202,
        contentType: "application/json",
        body: JSON.stringify({ id: jobId, status: "queued" }),
      });
    });
    await page.route(/\/exports\/.*\/events$/, async (route) => {
      await route.fulfill({
        status: 200,
        headers: { "Content-Type": "text/event-stream" },
        body: `data: ${JSON.stringify({ id: jobId, status: "done", progress: 100, result })}\n\n`,
      });
    });

    await page.goto("/templates/z_bracket");
    await page.getByTestId("export-button").click();

    await expect(page.getByTestId("export-download-link")).toBeVisible({ timeout: 10_000 });
    await expect(page.getByTestId("export-download-link-pdf")).toBeVisible();
    expect(received).toMatchObject({
      template_slug: "z_bracket",
      parameters: { top_flange_mm: 60, bottom_flange_mm: 60, offset_mm: 40 },
    });
  });
});
