import { expect, test } from "@playwright/test";

test.describe("/templates/corner_angle — Corner angle studio (Phase 2.10.b)", () => {
  test("картка → деталь corner_angle: заголовок, форма з defaults, R3F canvas, hole-summary", async ({
    page,
  }) => {
    const consoleErrors: string[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") consoleErrors.push(msg.text());
    });

    await page.goto("/templates?tab=parts");
    await page
      .locator('[data-testid="template-card"][data-slug="corner_angle"]')
      .getByTestId("template-card-cta")
      .click();

    await expect(page).toHaveURL("/templates/corner_angle");
    await expect(page.getByTestId("template-detail-title")).toHaveText("Кутник");
    await expect(page.getByTestId("corner-angle-studio")).toBeVisible();
    await expect(page.getByTestId("corner-angle-editor")).toBeVisible();

    // Дефолти з seed (CORNER_ANGLE_DEFAULT_PARAMETERS).
    await expect(page.getByTestId("param-legA_mm")).toHaveValue("50");
    await expect(page.getByTestId("param-legB_mm")).toHaveValue("50");
    await expect(page.getByTestId("param-hole_rows")).toHaveValue("1");
    await expect(page.getByTestId("param-hole_cols")).toHaveValue("2");
    await expect(page.getByTestId("param-hole_diameter_mm")).toHaveValue("5");
    await expect(page.getByTestId("validation-ok")).toBeVisible();

    // 1×2 × 2 полиці = 4 отвори.
    await expect(page.getByTestId("hole-grid-summary")).toContainText("всього 4 отворів");

    // 3D viewport.
    await expect(page.getByTestId("corner-angle-viewport")).toBeVisible();
    const canvas = page.getByTestId("corner-angle-viewport").locator("canvas");
    await expect(canvas).toBeVisible({ timeout: 15_000 });
    const dims = await canvas.evaluate((el: HTMLCanvasElement) => ({
      w: el.width,
      h: el.height,
    }));
    expect(dims.w).toBeGreaterThan(0);
    expect(dims.h).toBeGreaterThan(0);

    expect(consoleErrors, consoleErrors.join("\n")).toEqual([]);
  });

  test("зміна hole_rows/cols оновлює summary", async ({ page }) => {
    await page.goto("/templates/corner_angle");
    await expect(page.getByTestId("hole-grid-summary")).toContainText("всього 4 отворів");

    await page.getByTestId("param-hole_rows").fill("2");
    await page.getByTestId("param-hole_cols").fill("3");

    await expect(page.getByTestId("hole-grid-summary")).toContainText("всього 12 отворів");
  });

  test("hole_diameter поза діапазоном → invalid + export disabled", async ({ page }) => {
    await page.goto("/templates/corner_angle");
    await expect(page.getByTestId("export-button")).toBeEnabled();

    await page.getByTestId("param-hole_diameter_mm").fill("2");
    await expect(page.getByTestId("field-hole_diameter_mm")).toHaveAttribute(
      "data-invalid",
      "true",
    );
    await expect(page.getByTestId("export-button")).toBeDisabled();
  });

  test("Export → mock API → DXF + PDF з template_slug=corner_angle", async ({ page }) => {
    const jobId = "44444444-5555-6666-7777-888888888888";
    const result = {
      artifacts: {
        dxf: {
          url: "https://example-bucket.s3.amazonaws.com/c.dxf?Signature=abc&Expires=999",
          bytes: 16384,
          expires_at: "2026-05-18T00:00:00.000Z",
          s3_key: "exports/c.dxf",
        },
        pdf: {
          url: "https://example-bucket.s3.amazonaws.com/c.pdf?Signature=abc&Expires=999",
          bytes: 8192,
          expires_at: "2026-05-18T00:00:00.000Z",
          s3_key: "exports/c.pdf",
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

    await page.goto("/templates/corner_angle");
    await page.getByTestId("export-button").click();

    await expect(page.getByTestId("export-download-link")).toBeVisible({ timeout: 10_000 });
    await expect(page.getByTestId("export-download-link-pdf")).toBeVisible();
    expect(received).toMatchObject({
      template_slug: "corner_angle",
      parameters: {
        legA_mm: 50,
        legB_mm: 50,
        hole_rows: 1,
        hole_cols: 2,
        hole_diameter_mm: 5,
      },
    });
  });
});
