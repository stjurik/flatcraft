import type { ProductSummary } from "@flatcraft/types";
import { Button } from "@flatcraft/ui";
import Link from "next/link";

interface ProductCardProps {
  readonly product: ProductSummary;
  /**
   * Map slug → name_uk для опису «На основі: <шаблон>». Резолвиться у консумері
   * (templates/page.tsx уже fetch'ить templates listing — використовуємо ту ж
   * мапу замість додаткового JOIN у API).
   */
  readonly baseTemplateNameBySlug: ReadonlyMap<string, string>;
}

/**
 * Картка продукту для каталогу `/templates?tab=products` (Phase 3.0 PR 3, ADR-027).
 *
 * Аналог `<TemplateCard>` за структурою (article + thumb + title-link + CTA),
 * але дзеркалить product-аспекти: «На основі: <base_template>» замість slug'у,
 * `previewImageUrl` обов'язково — для published-продукту seed має згенерований
 * рендер (PR 8). Якщо відсутній — placeholder (для drafts).
 */
export function ProductCard({ product, baseTemplateNameBySlug }: ProductCardProps) {
  const href = `/products/${product.slug}`;
  const baseTemplateName =
    baseTemplateNameBySlug.get(product.baseTemplateSlug) ?? product.baseTemplateSlug;

  return (
    <article
      data-testid="product-card"
      data-slug={product.slug}
      className="bg-bg-elevated border-border hover:border-border-strong duration-base group flex flex-col overflow-hidden rounded-lg border shadow-md transition-shadow ease-out hover:shadow-lg"
    >
      <div className="bg-surface-sunken border-border text-fg-subtle group-hover:text-primary duration-base flex aspect-[4/3] items-center justify-center border-b transition-colors ease-out">
        {product.previewImageUrl ? (
          <img
            src={product.previewImageUrl}
            alt={product.name}
            className="h-full w-full object-cover"
          />
        ) : (
          <ProductCardPlaceholder />
        )}
      </div>

      <div className="flex flex-col gap-2 p-5">
        <h3 className="font-display text-fg text-xl font-semibold">
          <Link
            href={href}
            prefetch
            data-testid="product-card-title-link"
            className="hover:text-primary duration-fast transition-colors ease-out"
          >
            {product.name}
          </Link>
        </h3>

        {product.description ? (
          <p className="text-fg-muted text-sm">{product.description}</p>
        ) : null}

        <p className="text-fg-subtle font-mono text-xs" data-testid="product-card-base-template">
          На основі: <span className="text-fg-muted">{baseTemplateName}</span>
        </p>

        <div className="mt-3 flex items-center justify-between gap-3">
          <Button asChild variant="default" size="md">
            <Link href={href} prefetch data-testid="product-card-cta">
              Налаштувати →
            </Link>
          </Button>
          <span className="text-fg-subtle font-mono text-xs" data-testid="product-card-slug">
            {product.slug}
          </span>
        </div>
      </div>
    </article>
  );
}

function ProductCardPlaceholder() {
  return (
    <div className="text-fg-subtle/40 flex flex-col items-center gap-1">
      <svg
        width="64"
        height="64"
        viewBox="0 0 64 64"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.5"
        aria-hidden
      >
        <rect x="8" y="8" width="48" height="48" rx="2" />
        <line x1="8" y1="20" x2="56" y2="20" />
      </svg>
      <span className="font-mono text-xs">рендер скоро</span>
    </div>
  );
}
