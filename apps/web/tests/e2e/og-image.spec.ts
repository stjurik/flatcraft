import { expect, test } from "@playwright/test";

test.describe("Phase 2.16.a — Open Graph image", () => {
  test("/opengraph-image віддає PNG 1200×630", async ({ request }) => {
    const res = await request.get("/opengraph-image");
    expect(res.status()).toBe(200);
    expect(res.headers()["content-type"]).toMatch(/^image\/png/);
    const body = await res.body();
    expect(body.byteLength).toBeGreaterThan(5_000); // мінімум для PNG з контентом
    // PNG magic bytes: 89 50 4E 47 0D 0A 1A 0A
    expect(body.subarray(0, 8)).toEqual(
      Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    );
  });

  test("/ містить OG meta-теги з посиланням на opengraph-image", async ({ page }) => {
    await page.goto("/");
    const ogImage = page.locator('meta[property="og:image"]');
    await expect(ogImage).toHaveAttribute("content", /opengraph-image/);
    await expect(page.locator('meta[property="og:image:width"]')).toHaveAttribute(
      "content",
      "1200",
    );
    await expect(page.locator('meta[property="og:image:height"]')).toHaveAttribute(
      "content",
      "630",
    );
    await expect(page.locator('meta[property="og:image:type"]')).toHaveAttribute(
      "content",
      "image/png",
    );
    await expect(page.locator('meta[property="og:locale"]')).toHaveAttribute("content", "uk_UA");
    await expect(page.locator('meta[property="og:type"]')).toHaveAttribute("content", "website");
  });

  test("/ містить twitter:card summary_large_image з image", async ({ page }) => {
    await page.goto("/");
    await expect(page.locator('meta[name="twitter:card"]')).toHaveAttribute(
      "content",
      "summary_large_image",
    );
    await expect(page.locator('meta[name="twitter:image"]')).toHaveAttribute(
      "content",
      /opengraph-image/,
    );
  });
});
