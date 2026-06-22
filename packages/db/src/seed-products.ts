/**
 * Seed для products (ADR-027, Phase 3.0).
 *
 * Idempotent: повторний запуск upsert'ить кожен запис (як у seedTemplates).
 *
 * Phase 3.0 PR 2 — лише 1 placeholder продукт `__seed_placeholder__` з
 * isPublished=false. Він НЕ потрапляє у каталог `/products` (фільтрується
 * is_published=true у route), але дає unit-тестам реальну row для query-test'ів.
 *
 * Реальні products додаються:
 *   - PR 6: perforated-panel-decorative (base: perforated_panel_square)
 *   - PR 8: wall-shelf-custom (base: enclosed_shelf)
 *
 * Інваріант (cross-перевірка з template.parameters_schema) — у seed-валідаторі
 * Phase 3.0 PR 5+ (коли parameters_schema перестане бути порожнім `{}`).
 * Тут лише плейсхолдер для CI/unit.
 */
import { createClient, type DatabaseClient } from "./client.js";
import { products } from "./schema.js";

export interface ProductSeed {
  readonly slug: string;
  readonly name: string;
  readonly description: string | null;
  readonly baseTemplateSlug: string;
  readonly fixedParameters: Readonly<Record<string, unknown>>;
  readonly userEditableFields: readonly string[];
  readonly previewImageUrl: string | null;
  readonly useCases: readonly string[];
  readonly isPublished: boolean;
}

export const SEED_PRODUCTS: ReadonlyArray<ProductSeed> = [
  {
    // Placeholder: не публікується у каталозі. Існує тільки для unit/integration
    // тестів проти реальної БД (insert/query відбувається у seed flow).
    slug: "seed-placeholder",
    name: "[seed placeholder]",
    description: null,
    baseTemplateSlug: "perforated_panel",
    fixedParameters: { thickness_mm: 1.5 },
    userEditableFields: ["width_mm", "height_mm"],
    previewImageUrl: null,
    useCases: [],
    isPublished: false,
  },
];

export async function seedProducts(client: DatabaseClient): Promise<void> {
  const { db } = client;

  for (const p of SEED_PRODUCTS) {
    await db
      .insert(products)
      .values({
        slug: p.slug,
        name: p.name,
        description: p.description,
        baseTemplateSlug: p.baseTemplateSlug,
        fixedParameters: p.fixedParameters,
        userEditableFields: [...p.userEditableFields],
        previewImageUrl: p.previewImageUrl,
        useCases: [...p.useCases],
        isPublished: p.isPublished,
      })
      .onConflictDoUpdate({
        target: products.slug,
        set: {
          name: p.name,
          description: p.description,
          baseTemplateSlug: p.baseTemplateSlug,
          fixedParameters: p.fixedParameters,
          userEditableFields: [...p.userEditableFields],
          previewImageUrl: p.previewImageUrl,
          useCases: [...p.useCases],
          isPublished: p.isPublished,
          updatedAt: new Date(),
        },
      });
  }
}

// CLI entrypoint
export interface RunSeedProductsOptions {
  readonly url?: string;
}

export async function runSeedProducts(options: RunSeedProductsOptions = {}): Promise<void> {
  const client = createClient(options.url);
  try {
    await seedProducts(client);
  } finally {
    await client.close();
  }
}
