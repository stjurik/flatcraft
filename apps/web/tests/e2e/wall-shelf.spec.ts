import { expect, test } from "@playwright/test";

test.describe("/templates/wall_shelf — Wall shelf studio (Phase 2.10.c)", () => {
  test("картка → деталь wall_shelf: заголовок, форма з defaults, R3F canvas, summary", async ({
    page,
  }) => {
    const consoleErrors: string[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") consoleErrors.push(msg.text());
    });

    await page.goto("/templates");
    await page
      .locator('[data-testid="template-card"][data-slug="wall_shelf"]')
      .getByTestId("template-card-cta")
      .click();

    await expect(page).toHaveURL("/templates/wall_shelf");
    await expect(page.getByTestId("template-detail-title")).toHaveText("Полиця настінна");
    await expect(page.getByTestId("wall-shelf-studio")).toBeVisible();
    await expect(page.getByTestId("wall-shelf-editor")).toBeVisible();

    // Дефолти з seed (WALL_SHELF_DEFAULT_PARAMETERS).
    await expect(page.getByTestId("param-back_height_mm")).toHaveValue("80");
    await expect(page.getByTestId("param-shelf_depth_mm")).toHaveValue("150");
    await expect(page.getByTestId("param-front_lip_mm")).toHaveValue("20");
    await expect(page.getByTestId("param-mount_hole_rows")).toHaveValue("2");
    await expect(page.getByTestId("param-mount_hole_cols")).toHaveValue("2");
    await expect(page.getByTestId("validation-ok")).toBeVisible();

    // Summary показує "2 гиби (front lip 20 мм)" і кількість отворів.
    await expect(page.getByTestId("shelf-summary")).toContainText("2 гиби");
    await expect(page.getByTestId("shelf-summary")).toContainText("4 mounting holes");

    // 3D viewport.
    const canvas = page.getByTestId("wall-shelf-viewport").locator("canvas");
    await expect(canvas).toBeVisible({ timeout: 15_000 });
    const dims = await canvas.evaluate((el: HTMLCanvasElement) => ({
      w: el.width,
      h: el.height,
    }));
    expect(dims.w).toBeGreaterThan(0);
    expect(dims.h).toBeGreaterThan(0);

    expect(consoleErrors, consoleErrors.join("\n")).toEqual([]);
  });

  test("front_lip=0 → summary показує 1 гиб", async ({ page }) => {
    await page.goto("/templates/wall_shelf");
    await page.getByTestId("param-front_lip_mm").fill("0");
    await expect(page.getByTestId("shelf-summary")).toContainText("1 гиб (без front lip)");
    await expect(page.getByTestId("validation-ok")).toBeVisible();
  });

  test("front_lip у проміжку (0, 5) → invalid + export disabled", async ({ page }) => {
    await page.goto("/templates/wall_shelf");
    await expect(page.getByTestId("export-button")).toBeEnabled();

    await page.getByTestId("param-front_lip_mm").fill("3");
    await expect(page.getByTestId("field-front_lip_mm")).toHaveAttribute("data-invalid", "true");
    await expect(page.getByTestId("export-button")).toBeDisabled();
  });

  test("Export → mock API → DXF + PDF з template_slug=wall_shelf", async ({ page }) => {
    const jobId = "55555555-6666-7777-8888-999999999999";
    const result = {
      artifacts: {
        dxf: {
          url: "https://example-bucket.s3.amazonaws.com/ws.dxf?Signature=abc&Expires=999",
          bytes: 16384,
          expires_at: "2026-05-18T00:00:00.000Z",
          s3_key: "exports/ws.dxf",
        },
        pdf: {
          url: "https://example-bucket.s3.amazonaws.com/ws.pdf?Signature=abc&Expires=999",
          bytes: 8192,
          expires_at: "2026-05-18T00:00:00.000Z",
          s3_key: "exports/ws.pdf",
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

    await page.goto("/templates/wall_shelf");
    await page.getByTestId("export-button").click();

    await expect(page.getByTestId("export-download-link")).toBeVisible({ timeout: 10_000 });
    await expect(page.getByTestId("export-download-link-pdf")).toBeVisible();
    expect(received).toMatchObject({
      template_slug: "wall_shelf",
      parameters: {
        back_height_mm: 80,
        shelf_depth_mm: 150,
        front_lip_mm: 20,
        mount_hole_rows: 2,
        mount_hole_cols: 2,
      },
    });
  });
});
