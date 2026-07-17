import { expect, test } from "@playwright/test";

/**
 * Issue #70 DoD: Playwright e2e для /f/{exportId} — форма mount + submit → 200.
 * Мобільна-перша форма (Phase 3.4, PR #69) — 360×640 viewport, як mobile-studio.spec.ts.
 * POST /feedback/:exportId мокається через page.route (не залежить від реального
 * export_id у Postgres — тестуємо форму, не БД-flow).
 */
const MOBILE = { width: 360, height: 640 } as const;
const EXPORT_ID = "11111111-2222-3333-4444-555555555555";

test.describe("Phase 3.4 / issue #70 — /f/{exportId} feedback form (360×640)", () => {
  test.use({ viewport: MOBILE });

  test("mount + вибір outcome + submit → 200 → success toast", async ({ page }) => {
    let received: unknown = null;
    await page.route(/\/feedback\/[^/]+$/, async (route) => {
      received = route.request().postDataJSON();
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ status: "received" }),
      });
    });

    await page.goto(`/f/${EXPORT_ID}`);
    await expect(page.getByRole("heading", { name: "Як вийшла деталь?" })).toBeVisible();

    await page.getByLabel("✅ Так, все ок").check();
    await page.getByRole("button", { name: "Надіслати" }).click();

    await expect(page.getByRole("status")).toContainText("Дякуємо!");
    expect(received).toMatchObject({ outcome: "made", locale: "uk" });
  });

  test("outcome=failed без коментаря → required блокує submit (клієнтська валідація)", async ({
    page,
  }) => {
    let called = false;
    await page.route(/\/feedback\/[^/]+$/, async (route) => {
      called = true;
      await route.fulfill({ status: 200, body: JSON.stringify({ status: "received" }) });
    });

    await page.goto(`/f/${EXPORT_ID}`);
    await page.getByLabel("❌ Не вийшла").check();
    await page.getByRole("button", { name: "Надіслати" }).click();

    // required textarea → браузер блокує submit, fetch не викликається.
    expect(called).toBe(false);
  });

  test("API повертає 404 (невідомий export_id) → error banner", async ({ page }) => {
    await page.route(/\/feedback\/[^/]+$/, async (route) => {
      await route.fulfill({
        status: 404,
        contentType: "application/json",
        body: JSON.stringify({ error: "export_not_found" }),
      });
    });

    await page.goto(`/f/${EXPORT_ID}`);
    await page.getByLabel("✅ Так, все ок").check();
    await page.getByRole("button", { name: "Надіслати" }).click();

    // getByRole("alert") також матчить Next.js route-announcer — беремо конкретний текст.
    await expect(page.getByText("Не вдалося надіслати", { exact: false })).toBeVisible();
  });
});
