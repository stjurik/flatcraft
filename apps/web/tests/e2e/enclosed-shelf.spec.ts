import { expect, test } from "@playwright/test";

test.describe("/templates/enclosed_shelf — Enclosed shelf studio (Phase 3.0 PR 7d)", () => {
  test("картка → деталь enclosed_shelf: заголовок, форма з defaults, R3F canvas, summary", async ({
    page,
  }) => {
    const consoleErrors: string[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") consoleErrors.push(msg.text());
    });

    await page.goto("/templates?tab=parts");
    await page
      .locator('[data-testid="template-card"][data-slug="enclosed_shelf"]')
      .getByTestId("template-card-cta")
      .click();

    await expect(page).toHaveURL("/templates/enclosed_shelf");
    await expect(page.getByTestId("template-detail-title")).toHaveText(
      "Закрита полиця (cross-розгортка)",
    );
    await expect(page.getByTestId("enclosed-shelf-studio")).toBeVisible();
    await expect(page.getByTestId("enclosed-shelf-editor")).toBeVisible();

    // Дефолти з seed (ENCLOSED_SHELF_DEFAULT_PARAMETERS).
    await expect(page.getByTestId("param-width_mm")).toHaveValue("600");
    await expect(page.getByTestId("param-depth_mm")).toHaveValue("200");
    await expect(page.getByTestId("param-bend_radius_mm")).toHaveValue("2.5");
    await expect(page.getByTestId("validation-ok")).toBeVisible();

    // Summary показує "3 гиби UP · без перфорації" (default: rib=null, perf=null).
    await expect(page.getByTestId("enclosed-shelf-summary")).toContainText("3 гиби UP");
    await expect(page.getByTestId("enclosed-shelf-summary")).toContainText("без перфорації");

    // 3D viewport.
    const canvas = page.getByTestId("enclosed-shelf-viewport").locator("canvas");
    await expect(canvas).toBeVisible({ timeout: 15_000 });
    const dims = await canvas.evaluate((el: HTMLCanvasElement) => ({
      w: el.width,
      h: el.height,
    }));
    expect(dims.w).toBeGreaterThan(0);
    expect(dims.h).toBeGreaterThan(0);

    expect(consoleErrors, consoleErrors.join("\n")).toEqual([]);
  });

  test("Export → mock API → DXF + PDF з template_slug=enclosed_shelf", async ({ page }) => {
    const jobId = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
    const result = {
      artifacts: {
        dxf: {
          url: "https://example-bucket.s3.amazonaws.com/es.dxf?Signature=abc&Expires=999",
          bytes: 12000,
          expires_at: "2026-05-18T00:00:00.000Z",
          s3_key: "exports/es.dxf",
        },
        pdf: {
          url: "https://example-bucket.s3.amazonaws.com/es.pdf?Signature=abc&Expires=999",
          bytes: 6000,
          expires_at: "2026-05-18T00:00:00.000Z",
          s3_key: "exports/es.pdf",
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

    await page.goto("/templates/enclosed_shelf");
    await page.getByTestId("export-button").click();

    await expect(page.getByTestId("export-download-link")).toBeVisible({ timeout: 10_000 });
    await expect(page.getByTestId("export-download-link-pdf")).toBeVisible();
    expect(received).toMatchObject({
      template_slug: "enclosed_shelf",
      parameters: {
        width_mm: 600,
        depth_mm: 200,
        bend_radius_mm: 2.5,
        bend_angle_deg: 90,
        side_perforation: null,
        stiffening_rib: null,
      },
    });
  });
});
