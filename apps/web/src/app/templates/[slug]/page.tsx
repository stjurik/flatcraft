import { LBracketParametersSchema, L_BRACKET_DEFAULT_PARAMETERS } from "@flatcraft/types";
import Link from "next/link";
import { notFound } from "next/navigation";

import { LBracketEditor } from "../../../components/l-bracket-editor";
import { fetchTemplate } from "../../../lib/api";

interface PageProps {
  readonly params: Promise<{ slug: string }>;
}

export async function generateMetadata({ params }: PageProps) {
  const { slug } = await params;
  const template = await fetchTemplate(slug).catch(() => null);
  return {
    title: template ? `${template.nameUk} · flatcraft` : "Шаблон не знайдено · flatcraft",
  };
}

export default async function TemplatePage({ params }: PageProps) {
  const { slug } = await params;
  const template = await fetchTemplate(slug);
  if (!template) notFound();

  return (
    <main className="mx-auto flex min-h-screen max-w-6xl flex-col gap-8 px-6 py-12">
      <header className="flex flex-col gap-2">
        <Link href="/templates" className="text-sm text-zinc-500 hover:text-zinc-300">
          ← Усі шаблони
        </Link>
        <h1
          className="text-4xl font-bold tracking-tight text-zinc-50"
          data-testid="template-detail-title"
        >
          {template.nameUk}
        </h1>
        {template.descriptionUk ? (
          <p className="max-w-2xl text-zinc-400">{template.descriptionUk}</p>
        ) : null}
        <p
          className="text-xs uppercase tracking-wider text-zinc-600"
          data-testid="template-detail-slug"
        >
          {template.slug}
        </p>
      </header>

      <section
        data-testid="template-detail-editor-section"
        className="grid gap-6 lg:grid-cols-[1fr_2fr]"
      >
        <div className="rounded-2xl border border-zinc-800 bg-zinc-900/40 p-5">
          <h2 className="mb-4 text-lg font-semibold text-zinc-100">Параметри</h2>
          <TemplateEditor slug={template.slug} defaults={template.defaultParameters} />
        </div>

        <div
          className="flex aspect-video items-center justify-center rounded-2xl border border-zinc-800 bg-zinc-900/40 p-2 text-sm text-zinc-500"
          data-testid="template-detail-viewport-placeholder"
        >
          3D-viewport — Phase 2.2c
        </div>
      </section>
    </main>
  );
}

function TemplateEditor({
  slug,
  defaults,
}: {
  readonly slug: string;
  readonly defaults: Record<string, unknown>;
}) {
  if (slug === "l_bracket") {
    // defaults з БД — JSON; уточнюємо Zod-схемою, бо API повертає `unknown`-record.
    const parsed = LBracketParametersSchema.safeParse(defaults);
    return (
      <LBracketEditor
        initialParameters={parsed.success ? parsed.data : L_BRACKET_DEFAULT_PARAMETERS}
      />
    );
  }
  return (
    <p data-testid="template-editor-unsupported" className="text-sm text-zinc-500">
      Редактор для slug «{slug}» з'явиться у наступних фазах.
    </p>
  );
}
