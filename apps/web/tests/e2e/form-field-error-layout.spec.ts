import { expect, test } from "@playwright/test";

/**
 * Регресія до #264 (рецензія PR #311): після subgrid-вирівнювання полів
 * повідомлення про помилку поля не має накладатися на саме поле і має лишатися
 * в межах свого блоку — інакше на ноутбуці червоний текст лягає поверх вводу.
 * Вирівнювання полів у рядку при цьому зберігається.
 */
test.describe("#264 — помилка поля під полем, без накладання", () => {
  test.use({ viewport: { width: 1280, height: 900 } });

  test("l_bracket: legA_mm поза діапазоном", async ({ page }) => {
    await page.goto("/templates/l_bracket");
    await expect(page.getByTestId("validation-ok")).toBeVisible();

    await page.getByTestId("param-legA_mm").fill("10");
    const error = page.getByTestId("field-error-legA_mm");
    await expect(error).toBeVisible();

    const input = await page.getByTestId("param-legA_mm").boundingBox();
    const err = await error.boundingBox();
    const shell = await page.getByTestId("field-legA_mm").boundingBox();
    const neighbour = await page.getByTestId("param-legB_mm").boundingBox();
    if (!input || !err || !shell || !neighbour) throw new Error("немає boundingBox");

    expect(err.y, "помилка починається під полем, а не поверх нього").toBeGreaterThanOrEqual(
      input.y + input.height - 1,
    );
    expect(err.y + err.height, "помилка в межах блоку поля").toBeLessThanOrEqual(
      shell.y + shell.height + 1,
    );
    expect(Math.abs(neighbour.y - input.y), "сусіднє поле на тій самій лінії").toBeLessThanOrEqual(
      1,
    );
  });
});
