/**
 * Конвертує Zod issues у Record<field, string[]>, де field — top-level
 * ім'я поля (path[0]). Nested-помилки (array/object) груповані під
 * top-level — окремий редактор (holes-editor) розкриває їх детальніше.
 *
 * Зберігаємо порядок issues, щоб UI рендерив у послідовності, що Zod
 * їх знайшов (зазвичай top-down структура схеми).
 */
import type { ZodIssue } from "zod";

export type FieldErrors = Readonly<Record<string, ReadonlyArray<string>>>;

export function zodIssuesToFieldErrors(issues: ReadonlyArray<ZodIssue>): FieldErrors {
  const out: Record<string, string[]> = {};
  for (const issue of issues) {
    const top = issue.path[0];
    if (top === undefined) continue;
    const key = String(top);
    (out[key] ??= []).push(issue.message);
  }
  return out;
}
