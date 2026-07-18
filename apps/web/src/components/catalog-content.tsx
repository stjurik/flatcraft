import type { ProductSummary, TemplateSummary } from "@flatcraft/types";

import { dictionaries } from "../i18n/dictionaries";
import { DEFAULT_LOCALE, type Locale } from "../i18n/locale";
import { ApiError, fetchPublishedProducts, fetchPublishedTemplates } from "../lib/api";
import { CatalogToggle } from "./catalog-toggle";
import { ProductCard } from "./product-card";
import { TemplateCard } from "./template-card";

const IS_DEV = process.env.NEXT_PUBLIC_ENV === "dev";

export type TabValue = "products" | "parts";

export function parseTab(raw: string | undefined): TabValue {
  return raw === "parts" ? "parts" : "products";
}

interface CatalogContentProps {
  readonly tab: TabValue;
  readonly locale?: Locale;
}

/**
 * `/templates` каталог (ADR-037 §2) — спільний server-компонент для uk/en
 * дзеркал. Server-side parallel fetch — обидва listing'и завжди
 * загружаються, навіть якщо активний tab показує тільки один. Це дає
 * миттєвий tab-switch (shallow routing на клієнті без round-trip).
 */
export async function CatalogContent({ tab, locale = DEFAULT_LOCALE }: CatalogContentProps) {
  const dict = dictionaries[locale].catalog;

  const [templatesResult, productsResult] = await Promise.allSettled([
    fetchPublishedTemplates(),
    fetchPublishedProducts(),
  ]);

  const templates = templatesResult.status === "fulfilled" ? templatesResult.value : [];
  const products = productsResult.status === "fulfilled" ? productsResult.value : [];

  const templatesError =
    templatesResult.status === "rejected"
      ? errorDetail(templatesResult.reason, dict.kindTemplates, dict)
      : null;
  const productsError =
    productsResult.status === "rejected"
      ? errorDetail(productsResult.reason, dict.kindProducts, dict)
      : null;

  // base_template lookup для ProductCard «На основі: <name>».
  const baseTemplateNameBySlug = new Map<string, string>(
    templates.map((t) => [t.slug, locale === "en" ? t.nameEn : t.nameUk]),
  );

  return (
    <>
      {/* Mini-hero */}
      <section className="bg-bg border-border border-b">
        <div className="mx-auto flex max-w-6xl flex-col gap-3 px-4 py-10 md:px-6 md:py-14">
          <p className="text-fg-subtle text-xs uppercase tracking-wide">{dict.eyebrow}</p>
          <h1
            data-testid="templates-page-title"
            className="font-display text-fg xs:text-4xl text-3xl font-semibold md:text-5xl"
          >
            {dict.title}
          </h1>
          <p className="text-fg-muted max-w-2xl text-lg">{dict.subtitle}</p>
          <CatalogToggle
            value={tab}
            counts={{ products: products.length, parts: templates.length }}
            locale={locale}
          />
        </div>
      </section>

      {/* Grid */}
      <section className="bg-surface-sunken flex-1">
        <div className="mx-auto max-w-6xl px-4 py-10 md:px-6 md:py-14">
          {tab === "products" ? (
            <ProductsGrid
              products={products}
              error={productsError}
              baseTemplateNameBySlug={baseTemplateNameBySlug}
              locale={locale}
              dict={dict}
            />
          ) : (
            <TemplatesGrid
              templates={templates}
              error={templatesError}
              locale={locale}
              dict={dict}
            />
          )}
        </div>
      </section>
    </>
  );
}

type CatalogDict = (typeof dictionaries)["uk"]["catalog"];

function errorDetail(reason: unknown, kind: string, dict: CatalogDict): string {
  if (reason instanceof ApiError) {
    return dict.apiErrorStatus(reason.status, kind);
  }
  return dict.apiErrorGeneric(kind);
}

function TemplatesGrid({
  templates,
  error,
  locale,
  dict,
}: {
  templates: readonly TemplateSummary[];
  error: string | null;
  locale: Locale;
  dict: CatalogDict;
}) {
  if (error) return <CatalogError detail={error} kind="templates" dict={dict} />;
  if (templates.length === 0) return <CatalogEmpty kind="templates" dict={dict} />;
  return (
    <div data-testid="templates-grid" className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
      {templates.map((t) => (
        <TemplateCard key={t.id} template={t} locale={locale} />
      ))}
    </div>
  );
}

function ProductsGrid({
  products,
  error,
  baseTemplateNameBySlug,
  locale,
  dict,
}: {
  products: readonly ProductSummary[];
  error: string | null;
  baseTemplateNameBySlug: ReadonlyMap<string, string>;
  locale: Locale;
  dict: CatalogDict;
}) {
  if (error) return <CatalogError detail={error} kind="products" dict={dict} />;
  if (products.length === 0) return <CatalogEmpty kind="products" dict={dict} />;
  return (
    <div data-testid="products-grid" className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
      {products.map((p) => (
        <ProductCard
          key={p.slug}
          product={p}
          baseTemplateNameBySlug={baseTemplateNameBySlug}
          locale={locale}
        />
      ))}
    </div>
  );
}

function CatalogError({
  detail,
  kind,
  dict,
}: {
  detail: string;
  kind: "templates" | "products";
  dict: CatalogDict;
}) {
  return (
    <div
      data-testid={`${kind}-load-error`}
      className="border-danger/40 bg-danger-surface text-danger mb-8 rounded-md border p-4 text-sm"
    >
      <p className="font-medium">{dict.errorTitle}</p>
      <p className="mt-1 opacity-80">{detail}</p>
      {IS_DEV ? (
        <p className="mt-2 font-mono text-xs opacity-70">
          {dict.devHintApi} <code>pnpm --filter @flatcraft/api dev</code>
        </p>
      ) : null}
    </div>
  );
}

function CatalogEmpty({ kind, dict }: { kind: "templates" | "products"; dict: CatalogDict }) {
  const text = kind === "products" ? dict.emptyProducts : dict.emptyParts;
  const hint = kind === "products" ? dict.emptyProductsHint : dict.emptyPartsHint;
  return (
    <div
      data-testid={`${kind}-empty`}
      className="bg-bg-elevated border-border rounded-lg border p-8 text-center"
    >
      <p className="text-fg font-medium">{text}</p>
      <p className="text-fg-muted mt-2 text-sm">{hint}</p>
      {IS_DEV ? (
        <p className="text-fg-subtle mt-3 font-mono text-xs">
          {dict.devHintSeed} <code>pnpm db:seed</code>
        </p>
      ) : null}
    </div>
  );
}
