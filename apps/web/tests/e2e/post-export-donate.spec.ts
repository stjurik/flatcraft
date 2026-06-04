import { expect, test, type Page, type Route } from "@playwright/test";

const VIEWPORTS = [
  { name: "mobile-360", width: 360, height: 640 },
  { name: "tablet-768", width: 768, height: 1024 },
  { name: "desktop-1280", width: 1280, height: 800 },
] as const;

const JOB_ID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
const RESULT = {
  artifacts: {
    dxf: {
      url: "https://example-bucket.s3.amazonaws.com/exports/test.dxf?Signature=abc&Expires=999",
      bytes: 16384,
      expires_at: "2026-06-04T00:00:00.000Z",
      s3_key: "exports/test.dxf",
    },
    pdf: {
      url: "https://example-bucket.s3.amazonaws.com/exports/test.pdf?Signature=abc&Expires=999",
      bytes: 8192,
      expires_at: "2026-06-04T00:00:00.000Z",
      s3_key: "exports/test.pdf",
    },
  },
};

/** Мокає POST /exports (202) + SSE done — без реального cad-worker. */
async function mockExport(page: Page): Promise<void> {
  await page.route(/\/exports$/, (route: Route) =>
    route.fulfill({
      status: 202,
      contentType: "application/json",
      body: JSON.stringify({ id: JOB_ID, status: "queued" }),
    }),
  );
  await page.route(/\/exports\/.*\/events$/, (route: Route) =>
    route.fulfill({
      status: 200,
      headers: { "Content-Type": "text/event-stream", "Cache-Control": "no-cache" },
      body: `data: ${JSON.stringify({ id: JOB_ID, status: "done", progress: 100, result: RESULT })}\n\n`,
    }),
  );
}

test.describe("Post-export ЗСУ-CTA (Phase X.1 C)", () => {
  test("після успіху видно блок «Платформа була корисною?» з двома ЗСУ-кнопками", async ({
    page,
  }) => {
    await mockExport(page);
    await page.goto("/templates/l_bracket");
    await page.getByTestId("export-button").click();

    const nudge = page.getByTestId("post-export-donate");
    await expect(nudge).toBeVisible({ timeout: 10_000 });
    await expect(nudge).toContainText("Платформа була корисною?");

    const mono = page.getByTestId("donate-monobank");
    await expect(mono).toHaveAttribute("href", "https://send.monobank.ua/jar/A1u3M7VqQz");
    await expect(mono).toHaveAttribute("target", "_blank");
    await expect(mono).toHaveAttribute("rel", /noopener/);

    const u24 = page.getByTestId("donate-united24");
    await expect(u24).toHaveAttribute("href", "https://u24.gov.ua/");
    await expect(u24).toHaveAttribute("target", "_blank");
    await expect(u24).toHaveAttribute("rel", /noopener/);
  });

  test("CTA з'являється лише ПІСЛЯ експорту (не в idle-стані)", async ({ page }) => {
    await mockExport(page);
    await page.goto("/templates/l_bracket");
    await expect(page.getByTestId("post-export-donate")).toHaveCount(0);
    await page.getByTestId("export-button").click();
    await expect(page.getByTestId("post-export-donate")).toBeVisible({ timeout: 10_000 });
  });

  for (const { name, width, height } of VIEWPORTS) {
    test(`console-clean + tap-targets ≥44 на ${name}`, async ({ page }) => {
      const errors: string[] = [];
      page.on("console", (msg) => {
        if (msg.type() === "error") errors.push(msg.text());
      });
      await page.setViewportSize({ width, height });
      await mockExport(page);
      await page.goto("/templates/l_bracket");
      await page.getByTestId("export-button").click();
      await expect(page.getByTestId("post-export-donate")).toBeVisible({ timeout: 10_000 });

      for (const id of ["donate-monobank", "donate-united24"]) {
        const box = await page.getByTestId(id).boundingBox();
        expect(box, `${id} має bounding box`).not.toBeNull();
        expect(box!.height).toBeGreaterThanOrEqual(44);
      }
      expect(errors, errors.join("\n")).toEqual([]);
    });
  }
});
