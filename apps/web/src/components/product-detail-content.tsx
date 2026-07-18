import type { MaterialChoice, ProductDetail } from "@flatcraft/types";
import {
  ENCLOSED_SHELF_DEFAULT_PARAMETERS,
  EnclosedShelfParametersSchema,
  PERFORATED_PANEL_DEFAULT_PARAMETERS,
  PerforatedPanelParametersSchema,
} from "@flatcraft/types";
import Link from "next/link";

import { EnclosedShelfStudio } from "./enclosed-shelf-studio";
import { PerforatedPanelStudio } from "./perforated-panel-studio";
import { dictionaries } from "../i18n/dictionaries";
import { DEFAULT_LOCALE, type Locale } from "../i18n/locale";

interface ProductDetailContentProps {
  readonly product: ProductDetail;
  readonly materials: ReadonlyArray<MaterialChoice>;
  readonly locale?: Locale;
}

/**
 * `/products/[slug]` (ADR-037 §2/§5) — breadcrumb/header локалізовано,
 * студія СВІДОМО НЕ ЧІПАЄТЬСЯ (як templateDetail). `product.name`/
 * `.description` не має `_en`-поля у схемі — лишається UA-контентом на
 * обох локалях (задокументовано ADR-037 §4).
 */
export function ProductDetailContent({
  product,
  materials,
  locale = DEFAULT_LOCALE,
}: ProductDetailContentProps) {
  const dict = dictionaries[locale].productDetail;
  const catalogHref = locale === "en" ? "/en/templates" : "/templates";

  return (
    <main className="mx-auto flex min-h-screen max-w-6xl flex-col gap-8 px-6 py-12">
      <header className="flex flex-col gap-2">
        <Link href={catalogHref} className="text-fg-muted hover:text-fg text-sm">
          {dict.back}
        </Link>
        <h1
          className="font-display text-fg text-4xl font-semibold tracking-tight"
          data-testid="product-detail-title"
        >
          {product.name}
        </h1>
        {product.description ? (
          <p className="text-fg-muted max-w-2xl">{product.description}</p>
        ) : null}
        <p
          className="text-fg-subtle text-xs uppercase tracking-wider"
          data-testid="product-detail-slug"
        >
          {product.slug}
        </p>
      </header>

      <ProductStudioSwitch
        product={product}
        materials={materials}
        unsupportedBase={dict.unsupportedBase}
      />
    </main>
  );
}

function ProductStudioSwitch({
  product,
  materials,
  unsupportedBase,
}: {
  readonly product: ProductDetail;
  readonly materials: ReadonlyArray<MaterialChoice>;
  readonly unsupportedBase: (baseSlug: string) => string;
}) {
  // Resolved initial = base defaults ← merge fixedParameters (для product-mode
  // TemplateStudio додатково ре-мерджить fixed на кожному onChange — захист
  // від випадкового override). Тут — стартова форма для першого render'у.
  const baseDefaults = product.baseTemplate.defaultParameters;

  if (product.baseTemplateSlug === "perforated_panel") {
    const merged = { ...baseDefaults, ...product.fixedParameters };
    const parsed = PerforatedPanelParametersSchema.safeParse(merged);
    return (
      <PerforatedPanelStudio
        initialParameters={parsed.success ? parsed.data : PERFORATED_PANEL_DEFAULT_PARAMETERS}
        materials={materials}
        product={{
          name: product.name,
          description: product.description,
          fixedParameters: product.fixedParameters,
          userEditableFields: product.userEditableFields,
        }}
      />
    );
  }

  if (product.baseTemplateSlug === "enclosed_shelf") {
    const merged = { ...baseDefaults, ...product.fixedParameters };
    const parsed = EnclosedShelfParametersSchema.safeParse(merged);
    return (
      <EnclosedShelfStudio
        initialParameters={parsed.success ? parsed.data : ENCLOSED_SHELF_DEFAULT_PARAMETERS}
        materials={materials}
        product={{
          name: product.name,
          description: product.description,
          fixedParameters: product.fixedParameters,
          userEditableFields: product.userEditableFields,
        }}
      />
    );
  }

  return (
    <p data-testid="product-base-unsupported" className="text-fg-muted text-sm">
      {unsupportedBase(product.baseTemplateSlug)}
    </p>
  );
}
