import {
  CORNER_ANGLE_DEFAULT_PARAMETERS,
  CornerAngleParametersSchema,
  LBracketParametersSchema,
  L_BRACKET_DEFAULT_PARAMETERS,
  WALL_SHELF_DEFAULT_PARAMETERS,
  WallShelfParametersSchema,
  ZBracketParametersSchema,
  Z_BRACKET_DEFAULT_PARAMETERS,
} from "@flatcraft/types";
import Link from "next/link";
import { notFound } from "next/navigation";

import { CornerAngleStudio } from "../../../components/corner-angle-studio";
import { LBracketStudio } from "../../../components/l-bracket-studio";
import { WallShelfStudio } from "../../../components/wall-shelf-studio";
import { ZBracketStudio } from "../../../components/z-bracket-studio";
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

      <TemplateStudio slug={template.slug} defaults={template.defaultParameters} />
    </main>
  );
}

function TemplateStudio({
  slug,
  defaults,
}: {
  readonly slug: string;
  readonly defaults: Record<string, unknown>;
}) {
  if (slug === "l_bracket") {
    const parsed = LBracketParametersSchema.safeParse(defaults);
    return (
      <LBracketStudio
        initialParameters={parsed.success ? parsed.data : L_BRACKET_DEFAULT_PARAMETERS}
      />
    );
  }
  if (slug === "z_bracket") {
    const parsed = ZBracketParametersSchema.safeParse(defaults);
    return (
      <ZBracketStudio
        initialParameters={parsed.success ? parsed.data : Z_BRACKET_DEFAULT_PARAMETERS}
      />
    );
  }
  if (slug === "corner_angle") {
    const parsed = CornerAngleParametersSchema.safeParse(defaults);
    return (
      <CornerAngleStudio
        initialParameters={parsed.success ? parsed.data : CORNER_ANGLE_DEFAULT_PARAMETERS}
      />
    );
  }
  if (slug === "wall_shelf") {
    const parsed = WallShelfParametersSchema.safeParse(defaults);
    return (
      <WallShelfStudio
        initialParameters={parsed.success ? parsed.data : WALL_SHELF_DEFAULT_PARAMETERS}
      />
    );
  }
  return (
    <p data-testid="template-editor-unsupported" className="text-sm text-zinc-500">
      Студія для slug «{slug}» з'явиться у наступних фазах.
    </p>
  );
}
