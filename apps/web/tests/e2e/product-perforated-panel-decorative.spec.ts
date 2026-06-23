import { expect, test } from "@playwright/test";

/**
 * E2E для /products/perforated-panel-decorative (Phase 3.0 PR 6, ADR-027).
 *
 * Перевіряє: product-mode header (з product.name + description), AutoForm
 * фільтрується по userEditableFields (рендериться лише 6 геометричних полів),
 * R3F canvas з'являється з PerforatedPanelSquareScene, експорт-payload містить
 * `template_slug=perforated_panel_square` (а НЕ slug продукту).
 */

test.describe("/products/perforated-panel-decorative — product-mode studio (Phase 3.0 PR 6)", () => {
  test("заголовок продукту + 6 видимих полів + R3F canvas + grid summary", async ({ page }) => {
    const consoleErrors: string[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") consoleErrors.push(msg.text());
    });

    await page.goto("/products/perforated-panel-decorative");

    // Header (product-mode) — назва продукту, а не назва базового шаблону.
    await expect(page.getByTestId("product-detail-title")).toHaveText("Декоративна перфо-панель");
    await expect(page.getByTestId("product-detail-slug")).toHaveText("perforated-panel-decorative");

    // Studio контейнер — той самий wrapper, що для part-mode (slug-based testId).
    await expect(page.getByTestId("perforated-panel-square-studio")).toBeVisible();
    await expect(page.getByTestId("perforated-panel-square-editor")).toBeVisible();

    // product-mode header у TemplateStudio
    await expect(page.getByTestId("product-studio-header")).toBeVisible();

    // 6 user_editable полів — присутні; thickness/material/інше — НЕ перфо-fields.
    await expect(page.getByTestId("param-length_mm")).toHaveValue("200");
    await expect(page.getByTestId("param-width_mm")).toHaveValue("150");
    await expect(page.getByTestId("param-hole_size_mm")).toHaveValue("8");
    await expect(page.getByTestId("param-pitch_x_mm")).toHaveValue("30");
    await expect(page.getByTestId("param-pitch_y_mm")).toHaveValue("30");
    await expect(page.getByTestId("param-margin_mm")).toHaveValue("15");

    // Валідація OK для дефолтів.
    await expect(page.getByTestId("validation-ok")).toBeVisible();

    // Grid summary з square holes (□ glyph, не Ø).
    await expect(page.getByTestId("grid-summary-square")).toBeVisible();
    await expect(page.getByTestId("grid-summary-square")).toContainText("□");

    // R3F canvas рендериться (валідні params, render-gate ADR-026 пропускає).
    const canvas = page.getByTestId("perforated-panel-square-canvas");
    await expect(canvas).toBeVisible({ timeout: 15_000 });
    const dims = await canvas.evaluate((el: HTMLCanvasElement) => ({
      w: el.width,
      h: el.height,
    }));
    expect(dims.w).toBeGreaterThan(0);
    expect(dims.h).toBeGreaterThan(0);

    expect(consoleErrors, consoleErrors.join("\n")).toEqual([]);
  });

  test("Export → payload містить template_slug=perforated_panel_square (НЕ product slug)", async ({
    page,
  }) => {
    const jobId = "77777777-8888-9999-aaaa-bbbbbbbbbbbb";
    const result = {
      artifacts: {
        dxf: {
          url: "https://example-bucket.s3.amazonaws.com/d.dxf?Signature=abc&Expires=999",
          bytes: 12345,
          expires_at: "2026-05-18T00:00:00.000Z",
          s3_key: "exports/d.dxf",
        },
        pdf: {
          url: "https://example-bucket.s3.amazonaws.com/d.pdf?Signature=abc&Expires=999",
          bytes: 6789,
          expires_at: "2026-05-18T00:00:00.000Z",
          s3_key: "exports/d.pdf",
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

    await page.goto("/products/perforated-panel-decorative");
    await page.getByTestId("export-button").click();

    await expect(page.getByTestId("export-download-link")).toBeVisible({ timeout: 10_000 });
    expect(received).toMatchObject({
      template_slug: "perforated_panel_square",
      parameters: {
        length_mm: 200,
        width_mm: 150,
        hole_size_mm: 8,
      },
    });
  });
});
