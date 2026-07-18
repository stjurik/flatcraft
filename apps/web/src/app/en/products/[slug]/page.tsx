import { notFound } from "next/navigation";

import { ProductDetailContent } from "../../../../components/product-detail-content";
import { dictionaries } from "../../../../i18n/dictionaries";
import { fetchMaterials, fetchProduct } from "../../../../lib/api";

interface PageProps {
  readonly params: Promise<{ slug: string }>;
}

export async function generateMetadata({ params }: PageProps) {
  const { slug } = await params;
  const product = await fetchProduct(slug).catch(() => null);
  return {
    title: product ? `${product.name} · hart` : dictionaries.en.productDetail.notFoundTitle,
  };
}

export default async function ProductPageEn({ params }: PageProps) {
  const { slug } = await params;
  const [product, materials] = await Promise.all([fetchProduct(slug), fetchMaterials()]);
  if (!product) notFound();

  return <ProductDetailContent product={product} materials={materials} locale="en" />;
}
