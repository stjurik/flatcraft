import { expect, test } from "@playwright/test";

const VIEWPORTS = [
  { name: "mobile-360", width: 360, height: 640 },
  { name: "tablet-768", width: 768, height: 1024 },
  { name: "desktop-1280", width: 1280, height: 800 },
] as const;

test.describe("Phase 2.12 — material selector + grouped fieldsets (corner_angle)", () => {
  test("legends усіх 5 груп присутні", async ({ page }) => {
    await page.goto("/templates/corner_angle");
    for (const legend of ["Матеріал і товщина", "Полиця A", "Полиця B", "Гиб", "Сітка отворів"]) {
      await expect(page.getByRole("group", { name: legend })).toBeVisible();
    }
  });

  test("default material = cold_rolled_steel, default thickness = 2.0", async ({ page }) => {
    await page.goto("/templates/corner_angle");
    const material = page.getByTestId("select-material_code");
    await expect(material).toHaveValue("cold_rolled_steel");
    const thickness = page.getByTestId("select-thickness_mm");
    await expect(thickness).toHaveValue("2");
  });

  test("зміна на stainless_304 → у thicknesses нема 10мм (seed §4)", async ({ page }) => {
    await page.goto("/templates/corner_angle");
    await page.getByTestId("select-material_code").selectOption("stainless_304");
    const options = await page
      .getByTestId("select-thickness_mm")
      .locator("option")
      .allTextContents();
    expect(options.some((o) => o.startsWith("10"))).toBe(false);
  });

  test("Export POST /exports → request body містить material_code", async ({ page }) => {
    await page.goto("/templates/corner_angle");
    await expect(page.getByTestId("validation-ok")).toBeVisible();

    const requests: Array<Record<string, unknown>> = [];
    await page.route("**/exports", async (route) => {
      const body = route.request().postDataJSON();
      requests.push(body);
      await route.fulfill({
        status: 202,
        contentType: "application/json",
        body: JSON.stringify({
          id: "00000000-0000-0000-0000-000000000001",
          status: "queued",
        }),
      });
    });

    await page.getByTestId("export-button").click();
    await expect.poll(() => requests.length).toBeGreaterThan(0);
    expect(requests[0]).toMatchObject({
      template_slug: "corner_angle",
      material_code: "cold_rolled_steel",
      thickness_mm: 2,
    });
  });

  for (const { name, width, height } of VIEWPORTS) {
    test(`console-clean на ${name}`, async ({ page }) => {
      const errors: string[] = [];
      page.on("console", (msg) => {
        if (msg.type() === "error") errors.push(msg.text());
      });
      await page.setViewportSize({ width, height });
      await page.goto("/templates/corner_angle");
      await expect(page.getByTestId("auto-form-group-Матеріал і товщина")).toBeVisible();
      expect(errors, errors.join("\n")).toEqual([]);
    });
  }
});
