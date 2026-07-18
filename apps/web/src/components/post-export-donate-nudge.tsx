import { Heart } from "@flatcraft/ui";

import { dictionaries } from "../i18n/dictionaries";
import { DEFAULT_LOCALE, type Locale } from "../i18n/locale";

/**
 * Post-export ЗСУ-CTA (Phase X.1 C, ADR-020).
 *
 * Рендериться ПІД блоком завантаження файлів у success-стані ExportButton.
 * Ненав'язливе нагадування — БЕЗ auto-redirect / modal / blocking-overlay:
 * користувач уже отримав свої DXF/PDF, це лише запрошення подякувати ЗСУ.
 *
 * `locale` (ADR-037 §5) — опційний, дефолт `"uk"`: dictionary-ready для
 * майбутнього wiring з `/en/templates/[slug]`, але студії (єдиний наявний
 * call-site) цим PR НЕ чіпаються, тому live-поведінка не змінюється.
 */
const MONOBANK_JAR_URL = "https://send.monobank.ua/jar/A1u3M7VqQz";
const UNITED24_URL = "https://u24.gov.ua/";

interface PostExportDonateNudgeProps {
  readonly locale?: Locale;
}

export function PostExportDonateNudge({
  locale = DEFAULT_LOCALE,
}: PostExportDonateNudgeProps = {}) {
  const dict = dictionaries[locale].exportFlow;

  return (
    <div
      data-testid="post-export-donate"
      className="border-border bg-surface-sunken mt-6 rounded-md border p-4"
    >
      <p className="text-fg-muted mb-3 text-sm">{dict.donateQuestion}</p>
      <div className="flex flex-col gap-3 sm:flex-row">
        <a
          data-testid="donate-monobank"
          href={MONOBANK_JAR_URL}
          target="_blank"
          rel="noopener noreferrer"
          className="bg-zsu-bg text-zsu-fg hover:bg-zsu-bg-hover min-h-tap inline-flex items-center justify-center gap-2 rounded-md px-4 py-2 text-sm font-medium"
        >
          <Heart className="h-4 w-4" aria-hidden="true" />
          {dict.donateMonobank}
        </a>
        <a
          data-testid="donate-united24"
          href={UNITED24_URL}
          target="_blank"
          rel="noopener noreferrer"
          className="border-border text-fg hover:bg-surface-muted min-h-tap inline-flex items-center justify-center gap-2 rounded-md border px-4 py-2 text-sm font-medium"
        >
          {dict.donateUnited24}
        </a>
      </div>
    </div>
  );
}
