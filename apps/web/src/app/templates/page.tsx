import type { ProductSummary, TemplateSummary } from "@flatcraft/types";

import { CatalogToggle } from "../../components/catalog-toggle";
import { ProductCard } from "../../components/product-card";
import { TemplateCard } from "../../components/template-card";
import { ApiError, fetchPublishedProducts, fetchPublishedTemplates } from "../../lib/api";

export const metadata = {
  title: "Каталог · hart",
  description:
    "Каталог готових виробів і параметричних шаблонів з листового металу. " +
    "Налаштуйте розміри, скачайте DXF + PDF.",
};

const IS_DEV = process.env.NEXT_PUBLIC_ENV === "dev";

type TabValue = "products" | "parts";

function parseTab(raw: string | undefined): TabValue {
  return raw === "parts" ? "parts" : "products";
}

interface SearchParams {
  readonly tab?: string;
}

export default async function TemplatesPage({
  searchParams,
}: {
  // Next.js 15 App Router: searchParams — Promise<...>.
  searchParams: Promise<SearchParams>;
}) {
  const { tab: rawTab } = await searchParams;
  const tab = parseTab(rawTab);

  // Server-side parallel fetch — обидва listing'и завжди загружаються, навіть
  // якщо активний tab показує тільки один. Це дає миттєвий tab-switch (shallow
  // routing на клієнті без round-trip).
  const [templatesResult, productsResult] = await Promise.allSettled([
    fetchPublishedTemplates(),
    fetchPublishedProducts(),
  ]);

  const templates = templatesResult.status === "fulfilled" ? templatesResult.value : [];
  const products = productsResult.status === "fulfilled" ? productsResult.value : [];

  const templatesError =
    templatesResult.status === "rejected" ? errorDetail(templatesResult.reason, "шаблони") : null;
  const productsError =
    productsResult.status === "rejected" ? errorDetail(productsResult.reason, "вироби") : null;

  // base_template lookup для ProductCard «На основі: <name>».
  const baseTemplateNameBySlug = new Map<string, string>(templates.map((t) => [t.slug, t.nameUk]));

  return (
    <>
      {/* Mini-hero */}
      <section className="bg-bg border-border border-b">
        <div className="mx-auto flex max-w-6xl flex-col gap-3 px-4 py-10 md:px-6 md:py-14">
          <p className="text-fg-subtle text-xs uppercase tracking-wide">Каталог</p>
          <h1
            data-testid="templates-page-title"
            className="font-display text-fg xs:text-4xl text-3xl font-semibold md:text-5xl"
          >
            Каталог
          </h1>
          <p className="text-fg-muted max-w-2xl text-lg">
            Готові вироби з мінімальною конфігурацією або параметричні шаблони для повної свободи —
            у будь-якому випадку отримаєте DXF + PDF.
          </p>
          <CatalogToggle
            value={tab}
            counts={{ products: products.length, parts: templates.length }}
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
            />
          ) : (
            <TemplatesGrid templates={templates} error={templatesError} />
          )}
        </div>
      </section>
    </>
  );
}

function errorDetail(reason: unknown, kind: string): string {
  if (reason instanceof ApiError) {
    return `API повернув ${reason.status} (${kind}).`;
  }
  return `Не вдалося завантажити ${kind} з API.`;
}

function TemplatesGrid({
  templates,
  error,
}: {
  templates: readonly TemplateSummary[];
  error: string | null;
}) {
  if (error) return <CatalogError detail={error} kind="templates" />;
  if (templates.length === 0) return <CatalogEmpty kind="templates" />;
  return (
    <div data-testid="templates-grid" className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
      {templates.map((t) => (
        <TemplateCard key={t.id} template={t} />
      ))}
    </div>
  );
}

function ProductsGrid({
  products,
  error,
  baseTemplateNameBySlug,
}: {
  products: readonly ProductSummary[];
  error: string | null;
  baseTemplateNameBySlug: ReadonlyMap<string, string>;
}) {
  if (error) return <CatalogError detail={error} kind="products" />;
  if (products.length === 0) return <CatalogEmpty kind="products" />;
  return (
    <div data-testid="products-grid" className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
      {products.map((p) => (
        <ProductCard key={p.slug} product={p} baseTemplateNameBySlug={baseTemplateNameBySlug} />
      ))}
    </div>
  );
}

function CatalogError({ detail, kind }: { detail: string; kind: "templates" | "products" }) {
  return (
    <div
      data-testid={`${kind}-load-error`}
      className="border-danger/40 bg-danger-surface text-danger mb-8 rounded-md border p-4 text-sm"
    >
      <p className="font-medium">Не вдалося завантажити каталог</p>
      <p className="mt-1 opacity-80">{detail}</p>
      {IS_DEV ? (
        <p className="mt-2 font-mono text-xs opacity-70">
          dev hint: запустіть <code>pnpm --filter @flatcraft/api dev</code>
        </p>
      ) : null}
    </div>
  );
}

function CatalogEmpty({ kind }: { kind: "templates" | "products" }) {
  const text =
    kind === "products"
      ? "Поки немає опублікованих виробів."
      : "Поки немає опублікованих шаблонів.";
  const hint =
    kind === "products"
      ? "Перший продукт додамо у PR 6 — декоративну перфо-панель."
      : "Зайдіть пізніше — ми постійно додаємо нові шаблони.";
  return (
    <div
      data-testid={`${kind}-empty`}
      className="bg-bg-elevated border-border rounded-lg border p-8 text-center"
    >
      <p className="text-fg font-medium">{text}</p>
      <p className="text-fg-muted mt-2 text-sm">{hint}</p>
      {IS_DEV ? (
        <p className="text-fg-subtle mt-3 font-mono text-xs">
          dev hint: запустіть <code>pnpm db:seed</code>
        </p>
      ) : null}
    </div>
  );
}
