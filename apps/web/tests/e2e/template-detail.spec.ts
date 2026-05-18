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

  test("Export → async SSE → progress bar → download links (DXF + PDF)", async ({ page }) => {
    const jobId = "11111111-2222-3333-4444-555555555555";
    const resultObj = {
      artifacts: {
        dxf: {
          url: "https://example-bucket.s3.amazonaws.com/exports/test.dxf?Signature=abc&Expires=999",
          bytes: 16384,
          expires_at: "2026-05-17T00:00:00.000Z",
          s3_key: "exports/test.dxf",
        },
        pdf: {
          url: "https://example-bucket.s3.amazonaws.com/exports/test.pdf?Signature=abc&Expires=999",
          bytes: 8192,
          expires_at: "2026-05-17T00:00:00.000Z",
          s3_key: "exports/test.pdf",
        },
      },
    };
    let received: unknown = null;
    // POST /exports → 202 + jobId.
    await page.route(/\/exports$/, async (route) => {
      received = route.request().postDataJSON();
      await route.fulfill({
        status: 202,
        contentType: "application/json",
        body: JSON.stringify({ id: jobId, status: "queued" }),
      });
    });
    // GET /exports/:id/events → SSE stream: running 50%, потім done з result.
    await page.route(/\/exports\/.*\/events$/, async (route) => {
      const body =
        `data: ${JSON.stringify({ id: jobId, status: "running", progress: 50 })}\n\n` +
        `data: ${JSON.stringify({ id: jobId, status: "done", progress: 100, result: resultObj })}\n\n`;
      await route.fulfill({
        status: 200,
        headers: { "Content-Type": "text/event-stream", "Cache-Control": "no-cache" },
        body,
      });
    });

    await page.goto("/templates/l_bracket");
    const exportBtn = page.getByTestId("export-button");
    await expect(exportBtn).toHaveAttribute("data-state", "idle");
    await exportBtn.click();

    await expect(page.getByTestId("export-download-link")).toBeVisible({ timeout: 10_000 });
    await expect(page.getByTestId("export-download-link-pdf")).toBeVisible();
    await expect(exportBtn).toHaveAttribute("data-state", "done");

    const dxfHref = await page.getByTestId("export-download-link").getAttribute("href");
    const pdfHref = await page.getByTestId("export-download-link-pdf").getAttribute("href");
    expect(dxfHref).toBe(resultObj.artifacts.dxf.url);
    expect(pdfHref).toBe(resultObj.artifacts.pdf.url);
    expect(received).toMatchObject({ template_slug: "l_bracket", thickness_mm: 2 });
  });

  test("Export disabled коли параметри невалідні", async ({ page }) => {
    await page.goto("/templates/l_bracket");
    await expect(page.getByTestId("export-button")).toBeEnabled();

    await page.getByTestId("param-legA_mm").fill("10");
    await expect(page.getByTestId("export-button")).toBeDisabled();
  });

  test("Export → SSE failed event → error banner", async ({ page }) => {
    const jobId = "22222222-3333-4444-5555-666666666666";
    await page.route(/\/exports$/, (route) =>
      route.fulfill({
        status: 202,
        contentType: "application/json",
        body: JSON.stringify({ id: jobId, status: "queued" }),
      }),
    );
    await page.route(/\/exports\/.*\/events$/, (route) =>
      route.fulfill({
        status: 200,
        headers: { "Content-Type": "text/event-stream" },
        body: `data: ${JSON.stringify({
          id: jobId,
          status: "failed",
          progress: 0,
          error: "cad-worker 500: trace",
        })}\n\n`,
      }),
    );

    await page.goto("/templates/l_bracket");
    await page.getByTestId("export-button").click();

    await expect(page.getByTestId("export-error")).toBeVisible({ timeout: 10_000 });
    await expect(page.getByTestId("export-error")).toContainText("cad-worker");
    await expect(page.getByTestId("export-button")).toHaveAttribute("data-state", "error");
  });

  test("неіснуючий шаблон → 404", async ({ page }) => {
    const res = await page.goto("/templates/does_not_exist");
    expect(res?.status()).toBe(404);
  });

  test("неопублікований corner_angle → 404", async ({ page }) => {
    const res = await page.goto("/templates/corner_angle");
    expect(res?.status()).toBe(404);
  });
});
