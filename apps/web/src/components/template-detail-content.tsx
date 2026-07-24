import { TEMPLATE_REGISTRY, type TemplateSlug } from "@flatcraft/templates";
import type { MaterialChoice, TemplateDetail } from "@flatcraft/types";
import {
  ENCLOSED_SHELF_DEFAULT_PARAMETERS,
  EnclosedShelfParametersSchema,
  LBracketParametersSchema,
  L_BRACKET_DEFAULT_PARAMETERS,
  WALL_SHELF_DEFAULT_PARAMETERS,
  WallShelfParametersSchema,
  ZBracketParametersSchema,
  Z_BRACKET_DEFAULT_PARAMETERS,
} from "@flatcraft/types";
import Link from "next/link";

import { EnclosedShelfStudio } from "./enclosed-shelf-studio";
import { LBracketStudio } from "./l-bracket-studio";
import { RegistryTemplateStudio } from "./registry-template-studio";
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
  // Registry-driven шлях (Run 7 Master Registry Track, Етап 2) — ПЕРШИЙ,
  // перед хардкод-гілками, що по одній зникають з кожною наступною міграцією.
  const registryDef = TEMPLATE_REGISTRY[slug as TemplateSlug] as
    | (typeof TEMPLATE_REGISTRY)[TemplateSlug]
    | undefined;
  if (registryDef) {
    const parsed = registryDef.schema.safeParse(defaults);
    return (
      <RegistryTemplateStudio
        slug={slug as TemplateSlug}
        initialParameters={parsed.success ? parsed.data : registryDef.defaults}
        materials={materials}
      />
    );
  }
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
  if (slug === "wall_shelf") {
    const parsed = WallShelfParametersSchema.safeParse(defaults);
    return (
      <WallShelfStudio
        initialParameters={parsed.success ? parsed.data : WALL_SHELF_DEFAULT_PARAMETERS}
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
