import type { TemplateSummary } from "@flatcraft/types";
import { Button } from "@flatcraft/ui";
import Link from "next/link";

import { TemplateThumb } from "./template-thumb";

interface TemplateCardProps {
  readonly template: TemplateSummary;
}

/**
 * Шаблон-картка для каталогу `/templates`. Не клікабельна цілком —
 * вкладені анкори ламали б a11y (HTML5 не дозволяє `<a>` в `<a>`).
 * Замість того: окремий клікабельний `<h3>` (title) і явна CTA-Button.
 * Hover на article додає `shadow-lg` і змінює тон thumb-іконки —
 * через `group` пар.
 */
export function TemplateCard({ template }: TemplateCardProps) {
  const href = `/templates/${template.slug}`;
  return (
    <article
      data-testid="template-card"
      data-slug={template.slug}
      className="bg-bg-elevated border-border hover:border-border-strong duration-base group flex flex-col overflow-hidden rounded-lg border shadow-md transition-shadow ease-out hover:shadow-lg"
    >
      <div className="bg-surface-sunken border-border text-fg-subtle group-hover:text-primary duration-base flex aspect-[4/3] items-center justify-center border-b transition-colors ease-out">
        {template.previewImageUrl ? (
          <img
            src={template.previewImageUrl}
            alt={template.nameUk}
            className="h-full w-full object-cover"
          />
        ) : (
          <TemplateThumb slug={template.slug} />
        )}
      </div>

      <div className="flex flex-col gap-2 p-5">
        <h3 className="font-display text-fg text-xl font-semibold">
          <Link
            href={href}
            prefetch
            data-testid="template-card-title-link"
            className="hover:text-primary duration-fast transition-colors ease-out"
          >
            {template.nameUk}
          </Link>
        </h3>

        {template.descriptionUk ? (
          <p className="text-fg-muted text-sm">{template.descriptionUk}</p>
        ) : null}

        <div className="mt-3 flex items-center justify-between gap-3">
          <Button asChild variant="default" size="md">
            <Link href={href} prefetch data-testid="template-card-cta">
              Налаштувати →
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
