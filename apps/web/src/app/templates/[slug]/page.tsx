import {
  CORNER_ANGLE_DEFAULT_PARAMETERS,
  CornerAngleParametersSchema,
  ENCLOSED_SHELF_DEFAULT_PARAMETERS,
  EnclosedShelfParametersSchema,
  LBracketParametersSchema,
  L_BRACKET_DEFAULT_PARAMETERS,
  PERFORATED_PANEL_DEFAULT_PARAMETERS,
  PERFORATED_PANEL_SQUARE_DEFAULT_PARAMETERS,
  PerforatedPanelParametersSchema,
  PerforatedPanelSquareParametersSchema,
  WALL_SHELF_DEFAULT_PARAMETERS,
  WallShelfParametersSchema,
  ZBracketParametersSchema,
  Z_BRACKET_DEFAULT_PARAMETERS,
  type MaterialChoice,
} from "@flatcraft/types";
import Link from "next/link";
import { notFound } from "next/navigation";

import { CornerAngleStudio } from "../../../components/corner-angle-studio";
import { EnclosedShelfStudio } from "../../../components/enclosed-shelf-studio";
import { LBracketStudio } from "../../../components/l-bracket-studio";
import { PerforatedPanelSquareStudio } from "../../../components/perforated-panel-square-studio";
import { PerforatedPanelStudio } from "../../../components/perforated-panel-studio";
import { WallShelfStudio } from "../../../components/wall-shelf-studio";
import { ZBracketStudio } from "../../../components/z-bracket-studio";
import { fetchMaterials, fetchTemplate } from "../../../lib/api";

interface PageProps {
  readonly params: Promise<{ slug: string }>;
}

export async function generateMetadata({ params }: PageProps) {
  const { slug } = await params;
  const template = await fetchTemplate(slug).catch(() => null);
  return {
    title: template ? `${template.nameUk} · hart` : "Шаблон не знайдено · hart",
  };
}

export default async function TemplatePage({ params }: PageProps) {
  const { slug } = await params;
  // Materials і template можна fetch'ити паралельно — обидва server-side.
  const [template, materials] = await Promise.all([fetchTemplate(slug), fetchMaterials()]);
  if (!template) notFound();

  return (
    <main className="mx-auto flex min-h-screen max-w-6xl flex-col gap-8 px-6 py-12">
      <header className="flex flex-col gap-2">
        <Link href="/templates" className="text-fg-muted hover:text-fg text-sm">
          ← Усі шаблони
        </Link>
        <h1
          className="font-display text-fg text-4xl font-semibold tracking-tight"
          data-testid="template-detail-title"
        >
          {template.nameUk}
        </h1>
        {template.descriptionUk ? (
          <p className="text-fg-muted max-w-2xl">{template.descriptionUk}</p>
        ) : null}
        <p
          className="text-fg-subtle text-xs uppercase tracking-wider"
          data-testid="template-detail-slug"
        >
          {template.slug}
        </p>
      </header>

      <TemplateStudio
        slug={template.slug}
        defaults={template.defaultParameters}
        materials={materials}
      />
    </main>
  );
}

function TemplateStudio({
  slug,
  defaults,
  materials,
}: {
  readonly slug: string;
  readonly defaults: Record<string, unknown>;
  readonly materials: ReadonlyArray<MaterialChoice>;
}) {
  if (slug === "l_bracket") {
    const parsed = LBracketParametersSchema.safeParse(defaults);
    return (
      <LBracketStudio
        initialParameters={parsed.success ? parsed.data : L_BRACKET_DEFAULT_PARAMETERS}
        materials={materials}
      />
    );
  }
  if (slug === "z_bracket") {
    const parsed = ZBracketParametersSchema.safeParse(defaults);
    return (
      <ZBracketStudio
        initialParameters={parsed.success ? parsed.data : Z_BRACKET_DEFAULT_PARAMETERS}
        materials={materials}
      />
    );
  }
  if (slug === "corner_angle") {
    const parsed = CornerAngleParametersSchema.safeParse(defaults);
    return (
      <CornerAngleStudio
        initialParameters={parsed.success ? parsed.data : CORNER_ANGLE_DEFAULT_PARAMETERS}
        materials={materials}
      />
    );
  }
  if (slug === "wall_shelf") {
    const parsed = WallShelfParametersSchema.safeParse(defaults);
    return (
      <WallShelfStudio
        initialParameters={parsed.success ? parsed.data : WALL_SHELF_DEFAULT_PARAMETERS}
        materials={materials}
      />
    );
  }
  if (slug === "perforated_panel") {
    const parsed = PerforatedPanelParametersSchema.safeParse(defaults);
    return (
      <PerforatedPanelStudio
        initialParameters={parsed.success ? parsed.data : PERFORATED_PANEL_DEFAULT_PARAMETERS}
        materials={materials}
      />
    );
  }
  if (slug === "perforated_panel_square") {
    const parsed = PerforatedPanelSquareParametersSchema.safeParse(defaults);
    return (
      <PerforatedPanelSquareStudio
        initialParameters={
          parsed.success ? parsed.data : PERFORATED_PANEL_SQUARE_DEFAULT_PARAMETERS
        }
        materials={materials}
      />
    );
  }
  if (slug === "enclosed_shelf") {
    const parsed = EnclosedShelfParametersSchema.safeParse(defaults);
    return (
      <EnclosedShelfStudio
        initialParameters={parsed.success ? parsed.data : ENCLOSED_SHELF_DEFAULT_PARAMETERS}
        materials={materials}
      />
    );
  }
  return (
    <p data-testid="template-editor-unsupported" className="text-fg-muted text-sm">
      Студія для slug «{slug}» з'явиться у наступних фазах.
    </p>
  );
}
