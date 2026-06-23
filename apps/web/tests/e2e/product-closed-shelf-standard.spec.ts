import { expect, test } from "@playwright/test";

/**
 * E2E для /products/closed-shelf-standard (Phase 3.0 PR 8b, issue #2).
 *
 * enclosed_shelf переведено з parts-каталогу у products. Перевіряємо
 * product-mode header (з product.name + description), AutoForm рендериться
 * у TemplateStudio mode='product', R3F canvas з'являється з EnclosedShelfScene,
 * export-payload містить `template_slug=enclosed_shelf` (НЕ slug продукту).
 */

test.describe("/products/closed-shelf-standard — product-mode studio (Phase 3.0 PR 8b)", () => {
  test("заголовок продукту + 3 видимих поля + R3F canvas + summary", async ({ page }) => {
    const consoleErrors: string[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") consoleErrors.push(msg.text());
    });

    await page.goto("/products/closed-shelf-standard");

    // Header (product-mode) — назва продукту, а не назва базового шаблону.
    await expect(page.getByTestId("product-detail-title")).toHaveText("Закрита полиця стандартна");
    await expect(page.getByTestId("product-detail-slug")).toHaveText("closed-shelf-standard");

    // Studio контейнер — той самий wrapper, що для part-mode (slug-based testId).
    await expect(page.getByTestId("enclosed-shelf-studio")).toBeVisible();
    await expect(page.getByTestId("enclosed-shelf-editor")).toBeVisible();

    // product-mode header у TemplateStudio
    await expect(page.getByTestId("product-studio-header")).toBeVisible();

    // 3 user_editable полів — присутні; bend_angle/material/інше — НЕ редаговані.
    await expect(page.getByTestId("param-width_mm")).toHaveValue("600");
    await expect(page.getByTestId("param-depth_mm")).toHaveValue("200");
    await expect(page.getByTestId("param-bend_radius_mm")).toHaveValue("2.5");

    // Валідація OK для дефолтів.
    await expect(page.getByTestId("validation-ok")).toBeVisible();

    // Summary: "3 гиби UP · без перфорації".
    await expect(page.getByTestId("enclosed-shelf-summary")).toContainText("3 гиби UP");

    // R3F canvas рендериться (валідні params, render-gate ADR-026 пропускає).
    const canvas = page.getByTestId("enclosed-shelf-canvas").locator("canvas");
    await expect(canvas).toBeVisible({ timeout: 15_000 });
    const dims = await canvas.evaluate((el: HTMLCanvasElement) => ({
      w: el.width,
      h: el.height,
    }));
    expect(dims.w).toBeGreaterThan(0);
    expect(dims.h).toBeGreaterThan(0);

    expect(consoleErrors, consoleErrors.join("\n")).toEqual([]);
  });

  test("Export → payload містить template_slug=enclosed_shelf (НЕ product slug)", async ({
    page,
  }) => {
    const jobId = "cccccccc-dddd-eeee-ffff-000000000000";
    const result = {
      artifacts: {
        dxf: {
          url: "https://example-bucket.s3.amazonaws.com/cs.dxf?Signature=abc&Expires=999",
          bytes: 12000,
          expires_at: "2026-05-18T00:00:00.000Z",
          s3_key: "exports/cs.dxf",
        },
        pdf: {
          url: "https://example-bucket.s3.amazonaws.com/cs.pdf?Signature=abc&Expires=999",
          bytes: 6000,
          expires_at: "2026-05-18T00:00:00.000Z",
          s3_key: "exports/cs.pdf",
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

    await page.goto("/products/closed-shelf-standard");
    await page.getByTestId("export-button").click();

    await expect(page.getByTestId("export-download-link")).toBeVisible({ timeout: 10_000 });
    expect(received).toMatchObject({
      template_slug: "enclosed_shelf",
      parameters: {
        width_mm: 600,
        depth_mm: 200,
        bend_radius_mm: 2.5,
        bend_angle_deg: 90,
      },
    });
  });
});
