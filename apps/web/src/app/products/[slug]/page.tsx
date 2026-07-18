/**
 * Сторінка продукту: `/products/[slug]` (Phase 3.0 PR 6, ADR-027 Рішення 3).
 *
 * Сервер-сайд паралельно тягне детальний product (з resolved base_template)
 * і materials, далі рендерить локалізовану обгортку (ADR-037 §2/§5) —
 * `../../../components/product-detail-content.tsx`.
 */
import { notFound } from "next/navigation";

import { ProductDetailContent } from "../../../components/product-detail-content";
import { dictionaries } from "../../../i18n/dictionaries";
import { fetchMaterials, fetchProduct } from "../../../lib/api";

interface PageProps {
  readonly params: Promise<{ slug: string }>;
}

export async function generateMetadata({ params }: PageProps) {
  const { slug } = await params;
  const product = await fetchProduct(slug).catch(() => null);
  return {
    title: product ? `${product.name} · hart` : dictionaries.uk.productDetail.notFoundTitle,
  };
}

export default async function ProductPage({ params }: PageProps) {
  const { slug } = await params;
  const [product, materials] = await Promise.all([fetchProduct(slug), fetchMaterials()]);
  if (!product) notFound();

  return <ProductDetailContent product={product} materials={materials} locale="uk" />;
}
