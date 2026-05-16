import type { TemplateSummary } from "@flatcraft/types";

import { TemplateCard } from "../../components/template-card";
import { ApiError, fetchPublishedTemplates } from "../../lib/api";

export const metadata = {
  title: "Шаблони · flatcraft",
  description: "Каталог параметричних шаблонів виробів з листового металу.",
};

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
    <main className="mx-auto flex min-h-screen max-w-6xl flex-col gap-8 px-6 py-12">
      <header className="flex flex-col gap-2">
        <p className="text-sm uppercase tracking-wider text-zinc-500">Каталог</p>
        <h1
          className="text-4xl font-bold tracking-tight text-zinc-50"
          data-testid="templates-page-title"
        >
          Шаблони
        </h1>
        <p className="max-w-2xl text-zinc-400">
          Оберіть шаблон, налаштуйте розміри і матеріал — отримаєте DXF + PDF + STEP для замовлення
          на виробництві лазерного різання та гибки.
        </p>
      </header>

      {loadError ? (
        <p
          data-testid="templates-load-error"
          className="rounded-lg border border-red-900/50 bg-red-950/30 p-4 text-sm text-red-300"
        >
          {loadError} Запустіть `pnpm --filter @flatcraft/api dev`.
        </p>
      ) : null}

      <section data-testid="templates-grid" className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {templates.map((t) => (
          <TemplateCard key={t.id} template={t} />
        ))}
      </section>

      {templates.length === 0 && !loadError ? (
        <p data-testid="templates-empty" className="text-sm text-zinc-500">
          Поки немає опублікованих шаблонів. Запустіть `pnpm db:seed`.
        </p>
      ) : null}
    </main>
  );
}
