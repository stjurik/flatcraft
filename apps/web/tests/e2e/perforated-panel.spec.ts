import { expect, test } from "@playwright/test";

test.describe("/templates/perforated_panel — Perforated panel studio (Phase 2.10.d)", () => {
  test("картка → деталь perforated_panel: заголовок, форма з defaults, R3F canvas, grid summary", async ({
    page,
  }) => {
    const consoleErrors: string[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") consoleErrors.push(msg.text());
    });

    await page.goto("/templates");
    await page
      .locator('[data-testid="template-card"][data-slug="perforated_panel"]')
      .getByTestId("template-card-cta")
      .click();

    await expect(page).toHaveURL("/templates/perforated_panel");
    await expect(page.getByTestId("template-detail-title")).toHaveText("Перфо-панель");
    await expect(page.getByTestId("perforated-panel-studio")).toBeVisible();
    await expect(page.getByTestId("perforated-panel-editor")).toBeVisible();

    // Дефолти з seed (PERFORATED_PANEL_DEFAULT_PARAMETERS).
    await expect(page.getByTestId("param-length_mm")).toHaveValue("200");
    await expect(page.getByTestId("param-width_mm")).toHaveValue("150");
    await expect(page.getByTestId("param-hole_diameter_mm")).toHaveValue("8");
    await expect(page.getByTestId("param-pitch_x_mm")).toHaveValue("20");
    await expect(page.getByTestId("param-pitch_y_mm")).toHaveValue("20");
    await expect(page.getByTestId("validation-ok")).toBeVisible();

    // Grid summary: 9×7 = 63 з pitch=20, margin=15, length=200, width=150.
    await expect(page.getByTestId("grid-summary")).toContainText("9×7");
    await expect(page.getByTestId("grid-summary")).toContainText("63 отворів");

    // 3D viewport.
    const canvas = page.getByTestId("perforated-panel-viewport").locator("canvas");
    await expect(canvas).toBeVisible({ timeout: 15_000 });
    const dims = await canvas.evaluate((el: HTMLCanvasElement) => ({
      w: el.width,
      h: el.height,
    }));
    expect(dims.w).toBeGreaterThan(0);
    expect(dims.h).toBeGreaterThan(0);

    expect(consoleErrors, consoleErrors.join("\n")).toEqual([]);
  });

  test("більший pitch → менше отворів у summary", async ({ page }) => {
    await page.goto("/templates/perforated_panel");
    await expect(page.getByTestId("grid-summary")).toContainText("63 отворів");

    await page.getByTestId("param-pitch_x_mm").fill("50");
    await page.getByTestId("param-pitch_y_mm").fill("50");

    // pitch=50, length=200, margin=15: avail=170, cols = 170//50+1=4. Аналогічно rows=3.
    // 4×3 = 12.
    await expect(page.getByTestId("grid-summary")).toContainText("4×3");
    await expect(page.getByTestId("grid-summary")).toContainText("12 отворів");
  });

  test("hole_diameter поза діапазоном → invalid + export disabled", async ({ page }) => {
    await page.goto("/templates/perforated_panel");
    await expect(page.getByTestId("export-button")).toBeEnabled();

    await page.getByTestId("param-hole_diameter_mm").fill("40");
    await expect(page.getByTestId("field-hole_diameter_mm")).toHaveAttribute(
      "data-invalid",
      "true",
    );
    await expect(page.getByTestId("export-button")).toBeDisabled();
  });

  test("Export → mock API → DXF + PDF з template_slug=perforated_panel", async ({ page }) => {
    const jobId = "66666666-7777-8888-9999-aaaaaaaaaaaa";
    const result = {
      artifacts: {
        dxf: {
          url: "https://example-bucket.s3.amazonaws.com/p.dxf?Signature=abc&Expires=999",
          bytes: 16384,
          expires_at: "2026-05-18T00:00:00.000Z",
          s3_key: "exports/p.dxf",
        },
        pdf: {
          url: "https://example-bucket.s3.amazonaws.com/p.pdf?Signature=abc&Expires=999",
          bytes: 8192,
          expires_at: "2026-05-18T00:00:00.000Z",
          s3_key: "exports/p.pdf",
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

    await page.goto("/templates/perforated_panel");
    await page.getByTestId("export-button").click();

    await expect(page.getByTestId("export-download-link")).toBeVisible({ timeout: 10_000 });
    await expect(page.getByTestId("export-download-link-pdf")).toBeVisible();
    expect(received).toMatchObject({
      template_slug: "perforated_panel",
      parameters: {
        length_mm: 200,
        width_mm: 150,
        hole_diameter_mm: 8,
        pitch_x_mm: 20,
        pitch_y_mm: 20,
      },
    });
  });
});
