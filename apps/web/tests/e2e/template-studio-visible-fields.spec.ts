import { expect, test } from "@playwright/test";

/**
 * Issue #96 / T2 — форма студії (part/template-mode) має ховати поля за
 * `TemplateDefinition.ui.visibleFields`, так само як product-mode вже ховає
 * за `product.userEditableFields`. До фіксу `registry-template-studio.tsx`
 * передавав `visibleFields` у `RegistryTemplateEditor` ЛИШЕ коли
 * `mode === "product"` — `def.ui.visibleFields` (заповнений у l_bracket,
 * corner_angle, z_bracket) був мертвим кодом.
 *
 * z_bracket: докстрінг задачі (`docs/promts/t2-visible-fields.md`)
 * припускав, що поле напряму лишається видимим («два гиби, параметр
 * змістовний»). Факт коду інший: `z-bracket/index.ts` ховає `bends` тим
 * самим `HIDDEN_FIELDS`-патерном, що й l_bracket/corner_angle ховають
 * `bend_direction` — і ховав ще ДО Registry-міграції
 * (`z-bracket-editor.tsx` мав `.omit({ bends: true })`, Hotfix 2.10.e).
 * Це підтверджено окремо в issue #96 (коментар «Рішення-запит», 2026-08-12):
 * «Той самий розрив у сусідів: corner_angle (...) і z_bracket (...— bends/
 * holes)». Тест нижче звіряється з фактичною поведінкою, не з докстрінгом
 * задачі.
 */
test.describe("Template studio — форма читає ui.visibleFields (issue #96)", () => {
  test("l_bracket: «Напрям згину» приховано, holes — лише summary, решта полів на місці", async ({
    page,
  }) => {
    await page.goto("/templates/l_bracket");
    await expect(page.getByTestId("l-bracket-editor")).toBeVisible();

    await expect(page.getByTestId("field-bend_direction")).toHaveCount(0);
    await expect(page.getByTestId("auto-form-unsupported-holes")).toHaveCount(0);
    await expect(page.getByTestId("auto-form-holes-placeholder")).toBeVisible();

    await expect(page.getByTestId("param-legA_mm")).toBeVisible();
    await expect(page.getByTestId("param-legB_mm")).toBeVisible();
    await expect(page.getByTestId("param-bend_radius_mm")).toBeVisible();
    await expect(page.getByTestId("literal-bend_angle_deg")).toBeVisible();
    await expect(page.getByTestId("param-width_mm")).toBeVisible();
  });

  test("z_bracket: напрям гибів (bends) приховано так само, як bend_direction у l_bracket", async ({
    page,
  }) => {
    await page.goto("/templates/z_bracket");
    await expect(page.getByTestId("z-bracket-editor")).toBeVisible();

    await expect(page.getByTestId("field-bends")).toHaveCount(0);
    await expect(page.getByTestId("auto-form-unsupported-bends")).toHaveCount(0);
    await expect(page.getByTestId("auto-form-unsupported-holes")).toHaveCount(0);
    await expect(page.getByTestId("auto-form-holes-placeholder")).toBeVisible();

    await expect(page.getByTestId("param-top_flange_mm")).toBeVisible();
    await expect(page.getByTestId("param-bottom_flange_mm")).toBeVisible();
    await expect(page.getByTestId("param-offset_mm")).toBeVisible();
    await expect(page.getByTestId("param-bend_radius_mm")).toBeVisible();
    await expect(page.getByTestId("literal-bend_angle_deg")).toBeVisible();
    await expect(page.getByTestId("param-width_mm")).toBeVisible();
  });

  test("corner_angle: набір полів форми точно дорівнює def.ui.visibleFields (10 полів схеми мінус bend_direction)", async ({
    page,
  }) => {
    await page.goto("/templates/corner_angle");
    await expect(page.getByTestId("corner-angle-editor")).toBeVisible();

    await expect(page.getByTestId("field-bend_direction")).toHaveCount(0);

    const expectedVisible = [
      "param-legA_mm",
      "param-legB_mm",
      "param-bend_radius_mm",
      "param-width_mm",
      "param-hole_diameter_mm",
      "param-hole_rows",
      "param-hole_cols",
      "param-hole_margin_mm",
    ];
    for (const testId of expectedVisible) {
      await expect(page.getByTestId(testId)).toBeVisible();
    }
    await expect(page.getByTestId("literal-bend_angle_deg")).toBeVisible();

    // Рівно 9 видимих полів (10 схеми − bend_direction) — жодне зайве поле
    // не просочилось, жодне з очікуваних не пропало.
    const fieldCount = await page
      .getByTestId("corner-angle-editor")
      .locator(
        '[data-testid^="field-"], [data-testid^="literal-"], [data-testid^="auto-form-unsupported-"]',
      )
      .count();
    expect(fieldCount).toBe(9);
  });

  test("perforated_panel: visibleFields не задано → всі 10 полів схеми видимі (зворотна сумісність)", async ({
    page,
  }) => {
    await page.goto("/templates/perforated_panel");
    await expect(page.getByTestId("perforated-panel-editor")).toBeVisible();

    await expect(page.getByTestId("hole-shape-toggle")).toBeVisible();

    const expectedVisible = [
      "param-length_mm",
      "param-width_mm",
      "param-hole_size_mm",
      "param-pitch_x_mm",
      "param-pitch_y_mm",
      "param-margin_mm",
      "param-rib_height_mm",
      "param-bend_radius_mm",
    ];
    for (const testId of expectedVisible) {
      await expect(page.getByTestId(testId)).toBeVisible();
    }
    await expect(page.getByTestId("literal-bend_angle_deg")).toBeVisible();
  });
});
