/**
 * Автогенерований e2e-smoke з Template Registry (docs/12_TEMPLATE_CONTRACT.md
 * §3.4, ADR-033 §6). Один `test()` на кожен зареєстрований slug —
 * `TEMPLATE_REGISTRY` ПОРОЖНІЙ у Run 7 Етапі 1 (registry-скафолдинг без
 * міграції жодного шаблону), тож цей файл поки не генерує жодного test-case
 * (Playwright не падає на 0 тестів в окремому файлі, доки є тести деінде).
 * Коли Етап 2 реєструє перший slug — його студія автоматично отримує smoke
 * покриття тут, без ручних правок (закриває F7 — `l_bracket`/`enclosed_shelf`
 * досі не мали dedicated e2e-spec).
 */
import { expect, test } from "@playwright/test";

import { TEMPLATE_REGISTRY, type TemplateSlug } from "@flatcraft/templates";

for (const slug of Object.keys(TEMPLATE_REGISTRY) as TemplateSlug[]) {
  test(`studio smoke — ${slug}`, async ({ page }) => {
    await page.goto(`/templates/${slug}`);
    await expect(page.getByRole("heading").first()).toBeVisible();
    await page.locator('input[type="number"]').first().fill("50");
    await expect(page.getByRole("button", { name: /експорт|export/i })).not.toBeDisabled();
  });
}
