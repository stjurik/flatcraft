import { expect, test } from "@playwright/test";

/**
 * E2E для /products/perforated-panel-decorative (Phase 3.0 PR 6, ADR-027).
 *
 * Перевіряє: product-mode header (з product.name + description), AutoForm
 * фільтрується по userEditableFields (геометрія + висота ребра), R3F canvas
 * з'являється (PerforatedPanelScene, ADR-031), експорт-payload містить
 * `template_slug=perforated_panel` (а НЕ slug продукту).
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

    // Studio контейнер — спільна перфо-студія (Варіант B: один wrapper для
    // обох форм отвору, slug-based testId).
    await expect(page.getByTestId("perforated-panel-studio")).toBeVisible();
    await expect(page.getByTestId("perforated-panel-editor")).toBeVisible();

    // Перемикач форми отвору присутній, стартова форма — квадрат (square product).
    await expect(page.getByTestId("hole-shape-toggle")).toBeVisible();
    await expect(page.getByTestId("hole-shape-toggle-item-square")).toHaveAttribute(
      "data-active",
      "true",
    );

    // product-mode header у TemplateStudio
    await expect(page.getByTestId("product-studio-header")).toBeVisible();

    // 6 user_editable полів — присутні; thickness/material/інше — НЕ перфо-fields.
    await expect(page.getByTestId("param-length_mm")).toHaveValue("200");
    await expect(page.getByTestId("param-width_mm")).toHaveValue("150");
    await expect(page.getByTestId("param-hole_size_mm")).toHaveValue("8");
    await expect(page.getByTestId("param-pitch_x_mm")).toHaveValue("25");
    await expect(page.getByTestId("param-pitch_y_mm")).toHaveValue("25");
    await expect(page.getByTestId("param-margin_mm")).toHaveValue("15");
    // ADR-031: висота ребра редагована у формі продукту.
    await expect(page.getByTestId("param-rib_height_mm")).toHaveValue("30");

    // Валідація OK для дефолтів.
    await expect(page.getByTestId("validation-ok")).toBeVisible();

    // Grid summary з square holes (□ glyph, не Ø).
    await expect(page.getByTestId("grid-summary")).toBeVisible();
    await expect(page.getByTestId("grid-summary")).toContainText("□");

    // Регрес: toggle «Круглі» працює у product-mode (hole_shape НЕ fixed) — клік
    // активує circle і grid-summary переходить на Ø. Раніше fixedParameters
    // затирав вибір назад на square (ADR-031 fix).
    await page.getByTestId("hole-shape-toggle-item-circle").click();
    await expect(page.getByTestId("hole-shape-toggle-item-circle")).toHaveAttribute(
      "data-active",
      "true",
    );
    await expect(page.getByTestId("grid-summary")).toContainText("Ø");
    // Назад на «Квадратні».
    await page.getByTestId("hole-shape-toggle-item-square").click();
    await expect(page.getByTestId("hole-shape-toggle-item-square")).toHaveAttribute(
      "data-active",
      "true",
    );
    await expect(page.getByTestId("grid-summary")).toContainText("□");

    // R3F canvas рендериться (валідні params, render-gate ADR-026 пропускає).
    // getByTestId на R3F <Canvas> резолвиться у wrapper div; html-canvas — всередині.
    const canvas = page.getByTestId("perforated-panel-canvas").locator("canvas");
    await expect(canvas).toBeVisible({ timeout: 15_000 });
    const dims = await canvas.evaluate((el: HTMLCanvasElement) => ({
      w: el.width,
      h: el.height,
    }));
    expect(dims.w).toBeGreaterThan(0);
    expect(dims.h).toBeGreaterThan(0);

    expect(consoleErrors, consoleErrors.join("\n")).toEqual([]);
  });

  test("Export → payload містить template_slug=perforated_panel (НЕ product slug)", async ({
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
      template_slug: "perforated_panel",
      parameters: {
        length_mm: 200,
        width_mm: 150,
        hole_shape: "square",
        hole_size_mm: 8,
      },
    });
  });
});
