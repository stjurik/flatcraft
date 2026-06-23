/**
 * Сторінка продукту: `/products/[slug]` (Phase 3.0 PR 6, ADR-027 Рішення 3).
 *
 * Сервер-сайд паралельно тягне детальний product (з resolved base_template)
 * і materials, далі рендерить TemplateStudio у product-mode через відповідний
 * `*Studio` wrapper за `baseTemplateSlug`. У PR 6 підтриманий лише один
 * base — `perforated_panel_square`; для невідомого base — placeholder з
 * посиланням на каталог (інваріант ADR-027: seed-валідація гарантує, що
 * published продукти мають base серед знаних, runtime — safety net).
 */
import {
  PERFORATED_PANEL_SQUARE_DEFAULT_PARAMETERS,
  PerforatedPanelSquareParametersSchema,
  type MaterialChoice,
  type ProductDetail,
} from "@flatcraft/types";
import Link from "next/link";
import { notFound } from "next/navigation";

import { PerforatedPanelSquareStudio } from "../../../components/perforated-panel-square-studio";
import { fetchMaterials, fetchProduct } from "../../../lib/api";

interface PageProps {
  readonly params: Promise<{ slug: string }>;
}

export async function generateMetadata({ params }: PageProps) {
  const { slug } = await params;
  const product = await fetchProduct(slug).catch(() => null);
  return {
    title: product ? `${product.name} · hart` : "Виріб не знайдено · hart",
  };
}

export default async function ProductPage({ params }: PageProps) {
  const { slug } = await params;
  const [product, materials] = await Promise.all([fetchProduct(slug), fetchMaterials()]);
  if (!product) notFound();

  return (
    <main className="mx-auto flex min-h-screen max-w-6xl flex-col gap-8 px-6 py-12">
      <header className="flex flex-col gap-2">
        <Link href="/templates" className="text-fg-muted hover:text-fg text-sm">
          ← Усі вироби
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

      <ProductStudio product={product} materials={materials} />
    </main>
  );
}

function ProductStudio({
  product,
  materials,
}: {
  readonly product: ProductDetail;
  readonly materials: ReadonlyArray<MaterialChoice>;
}) {
  // Resolved initial = base defaults ← merge fixedParameters (для product-mode
  // TemplateStudio додатково ре-мерджить fixed на кожному onChange — захист
  // від випадкового override). Тут — стартова форма для першого render'у.
  const baseDefaults = product.baseTemplate.defaultParameters;

  if (product.baseTemplateSlug === "perforated_panel_square") {
    const merged = { ...baseDefaults, ...product.fixedParameters };
    const parsed = PerforatedPanelSquareParametersSchema.safeParse(merged);
    return (
      <PerforatedPanelSquareStudio
        initialParameters={
          parsed.success ? parsed.data : PERFORATED_PANEL_SQUARE_DEFAULT_PARAMETERS
        }
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
      Студія для базового шаблону «{product.baseTemplateSlug}» з&apos;явиться у наступних PR Phase
      3.0.
    </p>
  );
}
