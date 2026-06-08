import { expect, test } from "@playwright/test";

/**
 * Hotfix 2.9.c (D, ADR-022): клієнтська матрична валідація гибу.
 *
 * Для кожного шаблону з гибами: дефолтний радіус 2.5 мм валідний при t=2 мм,
 * але недопустимий при t=5 мм (дозволено [4, 5]). Зміна товщини на 5 мм має
 * замінити зелений банер на червоний з матричним повідомленням і заблокувати
 * експорт — ДО будь-якого запиту до API (валідація суто клієнтська, bakedSpec).
 *
 * Примітка: радіус — спільне поле шаблону (`bend_radius_mm`), а не per-bend
 * (`bends[]` тримає лише напрям). Тож сценарій «невалідний саме 2-й гиб»
 * непредставний у моделі — перевіряємо єдиний спільний радіус.
 */
const TEMPLATES_WITH_BENDS = [
  { slug: "l_bracket", studio: "l-bracket-studio" },
  { slug: "z_bracket", studio: "z-bracket-studio" },
  { slug: "corner_angle", studio: "corner-angle-studio" },
  { slug: "wall_shelf", studio: "wall-shelf-studio" },
] as const;

test.describe("Матрична валідація гибу (клієнт)", () => {
  for (const { slug, studio } of TEMPLATES_WITH_BENDS) {
    test(`${slug}: t=5 мм + R=2.5 мм → червоний банер + експорт disabled`, async ({ page }) => {
      await page.goto(`/templates/${slug}`);
      await expect(page.getByTestId(studio)).toBeVisible();

      // Старт: t=2 мм (дефолт), R=2.5 мм — валідно.
      await expect(page.getByTestId("select-thickness_mm")).toHaveValue("2");
      await expect(page.getByTestId("validation-ok")).toBeVisible();
      await expect(page.getByTestId("export-button")).toBeEnabled();

      // t=5 мм → R=2.5 мм недопустимий (дозволено 4, 5 мм).
      await page.getByTestId("select-thickness_mm").selectOption("5");

      await expect(page.getByTestId("validation-ok")).toHaveCount(0);
      const errors = page.getByTestId("validation-errors");
      await expect(errors).toBeVisible();
      await expect(errors).toContainText("дозволено");
      await expect(page.getByTestId("export-button")).toBeDisabled();
    });
  }
});
