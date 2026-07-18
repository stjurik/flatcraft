import type { MaterialChoice, TemplateDetail } from "@flatcraft/types";
import {
  CORNER_ANGLE_DEFAULT_PARAMETERS,
  CornerAngleParametersSchema,
  ENCLOSED_SHELF_DEFAULT_PARAMETERS,
  EnclosedShelfParametersSchema,
  LBracketParametersSchema,
  L_BRACKET_DEFAULT_PARAMETERS,
  PERFORATED_PANEL_DEFAULT_PARAMETERS,
  PerforatedPanelParametersSchema,
  WALL_SHELF_DEFAULT_PARAMETERS,
  WallShelfParametersSchema,
  ZBracketParametersSchema,
  Z_BRACKET_DEFAULT_PARAMETERS,
} from "@flatcraft/types";
import Link from "next/link";

import { CornerAngleStudio } from "./corner-angle-studio";
import { EnclosedShelfStudio } from "./enclosed-shelf-studio";
import { LBracketStudio } from "./l-bracket-studio";
import { PerforatedPanelStudio } from "./perforated-panel-studio";
import { WallShelfStudio } from "./wall-shelf-studio";
import { ZBracketStudio } from "./z-bracket-studio";
import { dictionaries } from "../i18n/dictionaries";
import { DEFAULT_LOCALE, type Locale } from "../i18n/locale";

interface TemplateDetailContentProps {
  readonly template: TemplateDetail;
  readonly materials: ReadonlyArray<MaterialChoice>;
  readonly locale?: Locale;
}

/**
 * `/templates/[slug]` (ADR-037 §2/§5) — breadcrumb/header локалізовано,
 * студія (`TemplateStudio`) — СВІДОМО НЕ ЧІПАЄТЬСЯ (AutoForm-лейбли/Zod
 * мігрують на Registry, Run 7). Тому на `/en/templates/[slug]` студія
 * лишається українською — задокументований компроміс Etap A.
 */
export function TemplateDetailContent({
  template,
  materials,
  locale = DEFAULT_LOCALE,
}: TemplateDetailContentProps) {
  const dict = dictionaries[locale].templateDetail;
  const catalogHref = locale === "en" ? "/en/templates" : "/templates";
  const name = locale === "en" ? template.nameEn : template.nameUk;
  const description = locale === "en" ? template.descriptionEn : template.descriptionUk;

  return (
    <main className="mx-auto flex min-h-screen max-w-6xl flex-col gap-8 px-6 py-12">
      <header className="flex flex-col gap-2">
        <Link href={catalogHref} className="text-fg-muted hover:text-fg text-sm">
          {dict.back}
        </Link>
        <h1
          className="font-display text-fg text-4xl font-semibold tracking-tight"
          data-testid="template-detail-title"
        >
          {name}
        </h1>
        {description ? <p className="text-fg-muted max-w-2xl">{description}</p> : null}
        <p
          className="text-fg-subtle text-xs uppercase tracking-wider"
          data-testid="template-detail-slug"
        >
          {template.slug}
        </p>
      </header>

      <TemplateStudioSwitch
        slug={template.slug}
        defaults={template.defaultParameters}
        materials={materials}
        unsupported={dict.unsupported}
      />
    </main>
  );
}

function TemplateStudioSwitch({
  slug,
  defaults,
  materials,
  unsupported,
}: {
  readonly slug: string;
  readonly defaults: Record<string, unknown>;
  readonly materials: ReadonlyArray<MaterialChoice>;
  readonly unsupported: (slug: string) => string;
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
      {unsupported(slug)}
    </p>
  );
}
