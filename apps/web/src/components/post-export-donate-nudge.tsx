import { Heart } from "@flatcraft/ui";

/**
 * Post-export ЗСУ-CTA (Phase X.1 C, ADR-020).
 *
 * Рендериться ПІД блоком завантаження файлів у success-стані ExportButton.
 * Ненав'язливе нагадування — БЕЗ auto-redirect / modal / blocking-overlay:
 * користувач уже отримав свої DXF/PDF, це лише запрошення подякувати ЗСУ.
 */
const MONOBANK_JAR_URL = "https://send.monobank.ua/jar/A1u3M7VqQz";
const UNITED24_URL = "https://u24.gov.ua/";

export function PostExportDonateNudge() {
  return (
    <div
      data-testid="post-export-donate"
      className="border-border bg-surface-sunken mt-6 rounded-md border p-4"
    >
      <p className="text-fg-muted mb-3 text-sm">Платформа була корисною? Підтримайте ЗСУ:</p>
      <div className="flex flex-col gap-3 sm:flex-row">
        <a
          data-testid="donate-monobank"
          href={MONOBANK_JAR_URL}
          target="_blank"
          rel="noopener noreferrer"
          className="bg-zsu-bg text-zsu-fg hover:bg-zsu-bg-hover min-h-tap inline-flex items-center justify-center gap-2 rounded-md px-4 py-2 text-sm font-medium"
        >
          <Heart className="h-4 w-4" aria-hidden="true" />
          Monobank банка ↗
        </a>
        <a
          data-testid="donate-united24"
          href={UNITED24_URL}
          target="_blank"
          rel="noopener noreferrer"
          className="border-border text-fg hover:bg-surface-muted min-h-tap inline-flex items-center justify-center gap-2 rounded-md border px-4 py-2 text-sm font-medium"
        >
          UNITED24 ↗
        </a>
      </div>
    </div>
  );
}
