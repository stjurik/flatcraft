/**
 * Клієнтська матрична валідація гибу (Hotfix 2.9.c, ADR-022).
 *
 * Тонка обгортка над `validateExportBends` з `@flatcraft/cad-engine` —
 * ТІЄЮ Ж функцією, що й серверний gate (ADR-019). Браузер бере запечений
 * snapshot матриці (`bakedSpec`), тож не потребує `node:fs`.
 *
 * Призначення — лише UX: підсвітити невалідний (матеріал, товщина, радіус) і
 * заблокувати кнопку «Експортувати» ДО запиту. Сервер усе одно перевіряє
 * незалежно — клієнтська валідація недостатня (ADR-019 інваріант).
 */
import { bakedSpec, validateExportBends, type ProblemError } from "@flatcraft/cad-engine";
import type { ExportRequest } from "@flatcraft/types";

/** Матричні помилки гибу для готового export-payload (порожньо — валідно). */
export function bendMatrixIssues(request: ExportRequest): ProblemError[] {
  return validateExportBends(request, bakedSpec);
}

/**
 * Дружнє повідомлення першої матричної помилки для банера (UA). Fallback на
 * код, якщо message відсутній. `null` — помилок немає.
 */
export function firstMatrixMessage(issues: readonly ProblemError[]): string | null {
  const first = issues[0];
  if (!first) return null;
  return first.message ?? `Гиб не відповідає обмеженням машини (${first.code}).`;
}
