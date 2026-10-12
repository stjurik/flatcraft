/**
 * Автогенерований e2e-smoke з Template Registry (docs/12_TEMPLATE_CONTRACT.md
 * §3.4, ADR-033 §6). Один `test()` на кожен зареєстрований slug —
 * `TEMPLATE_REGISTRY` ПОРОЖНІЙ у Run 7 Етапі 1 (registry-скафолдинг без
 * міграції жодного шаблону), тож цей файл поки не генерує жодного test-case
 * (Playwright не падає на 0 тестів в окремому файлі, доки є тести деінде).
 * Коли Етап 2 реєструє перший slug — його студія автоматично отримує smoke
 * покриття тут, без ручних правок (закриває F7 — `l_bracket`/`enclosed_shelf`
 * досі не мали dedicated e2e-spec).
 *
 * ВИПРАВЛЕНО (Run 7 Етап 2, PR perforated_panel, знайдено реальним e2e-прогоном):
 * первісний sketch (docs/12 §3.4) заповнював перше number-поле хардкодним
 * "50" — валідно для l_bracket (legA_mm: 20-500), але НЕВАЛІДНО для
 * perforated_panel (length_mm: min 100) → Zod-помилка → export-button лишався
 * disabled, тест падав. Тепер бере `min`-атрибут самого поля (AutoForm
 * рендерить його з Zod-схеми) — гарантовано валідне значення для БУДЬ-ЯКОГО
 * майбутнього зареєстрованого шаблону.
 */
import { expect, test } from "@playwright/test";

import { TEMPLATE_REGISTRY, type TemplateSlug } from "@flatcraft/templates";

/**
 * Smoke-перевірка для slug-ів без публічної сторінки Деталі (`/templates/<slug>`).
 *
 * `enclosed_shelf` у `packages/db/src/seed.ts` (~193) має `isPublished: false` —
 * це Виріб (PR 8b, issue #2: закрита полиця — не Деталь), і GET
 * `/templates/enclosed_shelf` повертає 404 (на сторінці немає жодного
 * `input[type=number]`). Публічний доступ дає Виріб `closed-shelf-standard`
 * (`packages/db/src/seed-products.ts`, `baseTemplateSlug: "enclosed_shelf"`) —
 * той самий registry-template-editor під капотом, тож той самий smoke має
 * сенс на `/products/<slug>`. Мапу тримаємо явною (не "усі неопубліковані
 * автоматично"), бо з'ясувати, який саме Виріб використовує slug — продуктове
 * рішення (seed-products.ts), а не механічне правило.
 */
const UNPUBLISHED_TEMPLATE_PRODUCT_PATH: Partial<Record<TemplateSlug, string>> = {
  enclosed_shelf: "/products/closed-shelf-standard",
};

for (const slug of Object.keys(TEMPLATE_REGISTRY) as TemplateSlug[]) {
  const productPath = UNPUBLISHED_TEMPLATE_PRODUCT_PATH[slug];

  test(`studio smoke — ${slug}`, async ({ page }) => {
    await page.goto(productPath ?? `/templates/${slug}`);
    await expect(page.getByRole("heading").first()).toBeVisible();

    const firstNumberInput = page.locator('input[type="number"]').first();
    const exportButton = page.getByRole("button", { name: /експорт|export/i });

    if (
      productPath &&
      ((await firstNumberInput.count()) === 0 || (await exportButton.count()) === 0)
    ) {
      // Рішення без питання (CLAUDE.md §0 п.4 — дрібниця з очевидним
      // дефолтом): якщо колись Виріб перестане мати number-поле чи кнопку
      // експорту — не підганяємо smoke, пропускаємо з посиланням на
      // dedicated-спек замість хиткого селектора.
      test.skip(true, `див. apps/web/tests/e2e/product-closed-shelf-standard.spec.ts для ${slug}`);
    }

    const min = await firstNumberInput.getAttribute("min");
    await firstNumberInput.fill(min ?? "50");
    await expect(exportButton).not.toBeDisabled();
  });
}
