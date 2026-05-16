import type { TemplateSummary } from "@flatcraft/types";

interface TemplateCardProps {
  readonly template: TemplateSummary;
}

export function TemplateCard({ template }: TemplateCardProps) {
  return (
    <article
      data-testid="template-card"
      data-slug={template.slug}
      className="group flex flex-col gap-3 rounded-xl border border-zinc-800 bg-zinc-900/40 p-5 transition hover:border-zinc-700 hover:bg-zinc-900/70"
    >
      <div className="flex aspect-video w-full items-center justify-center rounded-lg border border-dashed border-zinc-800 bg-zinc-950/50 text-xs uppercase tracking-wider text-zinc-600">
        {template.previewImageUrl ? (
          <img
            src={template.previewImageUrl}
            alt={template.nameUk}
            className="h-full w-full rounded-lg object-cover"
          />
        ) : (
          <span data-testid="template-card-preview-placeholder">Прев'ю — Phase 2.6</span>
        )}
      </div>

      <header className="flex flex-col gap-1">
        <h3 className="text-lg font-semibold text-zinc-100">{template.nameUk}</h3>
        <p className="text-xs text-zinc-500" data-testid="template-card-slug">
          {template.slug}
        </p>
      </header>

      {template.descriptionUk ? (
        <p className="text-sm text-zinc-400">{template.descriptionUk}</p>
      ) : null}
    </article>
  );
}
