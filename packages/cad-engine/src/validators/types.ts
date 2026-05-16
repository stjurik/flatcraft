/**
 * Спільний контракт результату валідації — формат збігається з
 * `model_drafts.validation_errors` (jsonb) у docs/05_DATA_MODEL.md §model_drafts,
 * тому те, що виходить з валідатора, можна писати у БД як є.
 */

export interface ValidationError {
  /** Стабільний код для UI/i18n, наприклад "sheet.thickness_unsupported". */
  readonly code: string;
  /** Чим конкретно це означає для користувача (UA). */
  readonly message_uk: string;
  /** Те саме EN. */
  readonly message_en: string;
  /** Які поля моделі це поламали (для підсвічування у формі). */
  readonly fields: readonly string[];
}

export type ValidationResult =
  | { readonly valid: true }
  | { readonly valid: false; readonly errors: readonly ValidationError[] };

export const ok = (): ValidationResult => ({ valid: true });

export const fail = (...errors: readonly ValidationError[]): ValidationResult => ({
  valid: false,
  errors,
});

export function combine(...results: readonly ValidationResult[]): ValidationResult {
  const errors: ValidationError[] = [];
  for (const r of results) {
    if (!r.valid) errors.push(...r.errors);
  }
  return errors.length === 0 ? ok() : { valid: false, errors };
}
