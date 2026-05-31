import type { TemplateSummary } from "@flatcraft/types";

import { TemplateCard } from "../../components/template-card";
import { ApiError, fetchPublishedTemplates } from "../../lib/api";

export const metadata = {
  title: "Шаблони · hart",
  description:
    "Каталог параметричних шаблонів виробів з листового металу. " +
    "Налаштуйте розміри, скачайте DXF + PDF.",
};

const IS_DEV = process.env.NEXT_PUBLIC_ENV === "dev";

export default async function TemplatesPage() {
  let templates: TemplateSummary[];
  let loadError: string | null = null;
  try {
    templates = await fetchPublishedTemplates();
  } catch (err) {
    templates = [];
    loadError =
      err instanceof ApiError
        ? `API повернув ${err.status}.`
        : "Не вдалося завантажити шаблони з API.";
  }

  return (
    <>
      {/* Mini-hero */}
      <section className="bg-bg border-border border-b">
        <div className="mx-auto flex max-w-6xl flex-col gap-3 px-4 py-10 md:px-6 md:py-14">
          <p className="text-fg-subtle text-xs uppercase tracking-wide">Каталог</p>
          <h1
            data-testid="templates-page-title"
            className="font-display text-fg xs:text-4xl text-3xl font-semibold md:text-5xl"
          >
            Каталог шаблонів
          </h1>
          <p className="text-fg-muted max-w-2xl text-lg">
            Оберіть шаблон, налаштуйте розміри і матеріал — отримаєте DXF + PDF для замовлення на
            лазерній різці й гибці.
          </p>
        </div>
      </section>

      {/* Grid */}
      <section className="bg-surface-sunken flex-1">
        <div className="mx-auto max-w-6xl px-4 py-10 md:px-6 md:py-14">
          {loadError ? <CatalogError detail={loadError} /> : null}
          {templates.length === 0 && !loadError ? <CatalogEmpty /> : null}
          {templates.length > 0 ? (
            <div data-testid="templates-grid" className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
              {templates.map((t) => (
                <TemplateCard key={t.id} template={t} />
              ))}
            </div>
          ) : null}
        </div>
      </section>
    </>
  );
}

function CatalogError({ detail }: { detail: string }) {
  return (
    <div
      data-testid="templates-load-error"
      className="border-danger/40 bg-danger-surface text-danger mb-8 rounded-md border p-4 text-sm"
    >
      <p className="font-medium">Не вдалося завантажити каталог</p>
      <p className="mt-1 opacity-80">{detail}</p>
      {IS_DEV ? (
        <p className="mt-2 font-mono text-xs opacity-70">
          dev hint: запустіть <code>pnpm --filter @flatcraft/api dev</code>
        </p>
      ) : null}
    </div>
  );
}

function CatalogEmpty() {
  return (
    <div
      data-testid="templates-empty"
      className="bg-bg-elevated border-border rounded-lg border p-8 text-center"
    >
      <p className="text-fg font-medium">Поки немає опублікованих шаблонів.</p>
      <p className="text-fg-muted mt-2 text-sm">
        Зайдіть пізніше — ми постійно додаємо нові вироби.
      </p>
      {IS_DEV ? (
        <p className="text-fg-subtle mt-3 font-mono text-xs">
          dev hint: запустіть <code>pnpm db:seed</code>
        </p>
      ) : null}
    </div>
  );
}
