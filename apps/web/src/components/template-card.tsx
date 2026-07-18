import type { TemplateSummary } from "@flatcraft/types";
import { Button } from "@flatcraft/ui";
import Link from "next/link";

import { dictionaries } from "../i18n/dictionaries";
import { DEFAULT_LOCALE, type Locale } from "../i18n/locale";
import { TemplateThumb } from "./template-thumb";

interface TemplateCardProps {
  readonly template: TemplateSummary;
  readonly locale?: Locale;
}

/**
 * Шаблон-картка для каталогу `/templates`. Не клікабельна цілком —
 * вкладені анкори ламали б a11y (HTML5 не дозволяє `<a>` в `<a>`).
 * Замість того: окремі сиблінг-анкори — клікабельне прев'ю (thumb),
 * клікабельний `<h3>` (title) і явна CTA-Button — усі ведуть на `href`.
 * Hover на article додає `shadow-lg` і змінює тон thumb-іконки —
 * через `group` пар.
 *
 * `locale` (ADR-037 §2/§4) обирає `nameEn`/`descriptionEn` замість
 * `nameUk`/`descriptionUk` (обидва поля вже в DB-схемі) і веде на `/en/*`.
 */
export function TemplateCard({ template, locale = DEFAULT_LOCALE }: TemplateCardProps) {
  const dict = dictionaries[locale].templateCard;
  const href = locale === "en" ? `/en/templates/${template.slug}` : `/templates/${template.slug}`;
  const name = locale === "en" ? template.nameEn : template.nameUk;
  const description = locale === "en" ? template.descriptionEn : template.descriptionUk;

  return (
    <article
      data-testid="template-card"
      data-slug={template.slug}
      className="bg-bg-elevated border-border hover:border-border-strong duration-base group flex flex-col overflow-hidden rounded-lg border shadow-md transition-shadow ease-out hover:shadow-lg"
    >
      <Link
        href={href}
        prefetch
        aria-label={dict.configureAria(name)}
        data-testid="template-card-thumb-link"
        className="focus-visible:ring-primary focus-visible:outline-none focus-visible:ring-2"
      >
        <div className="bg-surface-sunken border-border text-fg-subtle group-hover:text-primary duration-base flex aspect-[4/3] items-center justify-center border-b transition-colors ease-out">
          {template.previewImageUrl ? (
            <img src={template.previewImageUrl} alt={name} className="h-full w-full object-cover" />
          ) : (
            <TemplateThumb slug={template.slug} />
          )}
        </div>
      </Link>

      <div className="flex flex-col gap-2 p-5">
        <h3 className="font-display text-fg text-xl font-semibold">
          <Link
            href={href}
            prefetch
            data-testid="template-card-title-link"
            className="hover:text-primary duration-fast transition-colors ease-out"
          >
            {name}
          </Link>
        </h3>

        {description ? <p className="text-fg-muted text-sm">{description}</p> : null}

        <div className="mt-3 flex items-center justify-between gap-3">
          <Button asChild variant="default" size="md">
            <Link href={href} prefetch data-testid="template-card-cta">
              {dict.cta}
            </Link>
          </Button>
          <span className="text-fg-subtle font-mono text-xs" data-testid="template-card-slug">
            {template.slug}
          </span>
        </div>
      </div>
    </article>
  );
}
