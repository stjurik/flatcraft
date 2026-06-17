import { expect, test } from "@playwright/test";

/**
 * Hotfix 2.9.f (ADR-026): render-gate + ErrorBoundary проти крашу R3F на
 * невалідній геометрії.
 *
 * Repro (P0): у студії гибового шаблону ввести замале значення плеча (1 мм при
 * товщина+радіус = 4.5 мм) → раніше `build*ShapeCommands` кидав throw у useMemo
 * сцени → uncaught у React-дереві → WebGL Context Lost → white-screen
 * «Application error».
 *
 * Очікування після фіксу: НЕ white-screen; viewport показує fallback «Виправте
 * параметри у формі»; форма показує банер + блокує експорт; у консолі нема
 * "Context Lost"/"useMemo".
 */
const CASES = [
  {
    slug: "l_bracket",
    studio: "l-bracket-studio",
    viewport: "l-bracket-viewport",
    field: "param-legA_mm",
  },
  {
    slug: "z_bracket",
    studio: "z-bracket-studio",
    viewport: "z-bracket-viewport",
    field: "param-top_flange_mm",
  },
  {
    slug: "corner_angle",
    studio: "corner-angle-studio",
    viewport: "corner-angle-viewport",
    field: "param-legA_mm",
  },
  {
    slug: "wall_shelf",
    studio: "wall-shelf-studio",
    viewport: "wall-shelf-viewport",
    field: "param-back_height_mm",
  },
] as const;

for (const { slug, studio, viewport, field } of CASES) {
  test(`${slug}: замале плече → fallback, без крашу R3F`, async ({ page }) => {
    const consoleErrors: string[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") consoleErrors.push(msg.text());
    });
    const pageErrors: string[] = [];
    page.on("pageerror", (err) => pageErrors.push(err.message));

    await page.goto(`/templates/${slug}`);
    await expect(page.getByTestId(studio)).toBeVisible();
    await expect(page.getByTestId("export-button")).toBeEnabled();

    // Вводимо замале значення (1 мм) — нижче товщина+радіус (4.5 мм).
    await page.getByTestId(field).fill("1");

    // Viewport показує fallback замість сцени (НЕ крашить).
    await expect(
      page.getByTestId(viewport).getByTestId("invalid-parameters-fallback"),
    ).toBeVisible();
    await expect(page.getByTestId(viewport)).toContainText("Виправте параметри у формі");

    // Студія жива (нема white-screen «Application error»).
    await expect(page.getByTestId(studio)).toBeVisible();
    await expect(page.locator("body")).not.toContainText("Application error");

    // Форма блокує експорт + показує банер.
    await expect(page.getByTestId("export-button")).toBeDisabled();
    await expect(page.getByTestId("validation-errors")).toBeVisible();

    // Нема R3F-крашу у консолі/неперехоплених помилок.
    const ctxLost = [...consoleErrors, ...pageErrors].filter(
      (m) => /context lost/i.test(m) || /useMemo/i.test(m) || /too small for thickness/i.test(m),
    );
    expect(ctxLost, `несподівані R3F-помилки: ${ctxLost.join(" | ")}`).toHaveLength(0);

    // Виправлення повертає сцену.
    await page.getByTestId(field).fill("60");
    await expect(page.getByTestId(viewport).getByTestId("invalid-parameters-fallback")).toHaveCount(
      0,
    );
  });
}
