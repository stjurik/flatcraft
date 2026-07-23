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

for (const slug of Object.keys(TEMPLATE_REGISTRY) as TemplateSlug[]) {
  test(`studio smoke — ${slug}`, async ({ page }) => {
    await page.goto(`/templates/${slug}`);
    await expect(page.getByRole("heading").first()).toBeVisible();
    const firstNumberInput = page.locator('input[type="number"]').first();
    const min = await firstNumberInput.getAttribute("min");
    await firstNumberInput.fill(min ?? "50");
    await expect(page.getByRole("button", { name: /експорт|export/i })).not.toBeDisabled();
  });
}
