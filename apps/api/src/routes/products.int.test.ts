/**
 * Інтеграційний тест GET /products + /products/:slug — проти реальної Postgres.
 *
 * Запускається коли `DATABASE_URL` визначений (локально через docker compose,
 * у CI через postgres service). Без env — describe.skip (як templates.int.test.ts).
 *
 * Phase 3.0 PR 2 — seed має лише placeholder (isPublished=false), тож:
 *   - GET /products повертає [] (нема опублікованих).
 *   - GET /products/seed-placeholder → 404 (фільтр is_published=true).
 *
 * Реальні products → PR 6 (perforated-panel-decorative) і PR 8 (wall-shelf-custom),
 * тоді ця інтеграція розширюється на нові сценарії.
 */
import { createClient, runMigrations, runSeed, schema, type DatabaseClient } from "@flatcraft/db";
import { eq } from "drizzle-orm";
import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { createServer } from "../server.js";

const DATABASE_URL = process.env["DATABASE_URL"];

describe.skipIf(!DATABASE_URL)("GET /products — integration", () => {
  let app: FastifyInstance;
  let client: DatabaseClient;

  beforeAll(async () => {
    if (!DATABASE_URL) throw new Error("DATABASE_URL required");
    await runMigrations({ url: DATABASE_URL });
    await runSeed({ url: DATABASE_URL });
    client = createClient(DATABASE_URL);
    app = await createServer({ logger: false, dbClient: client });

    // PR 2 seed містить лише placeholder з isPublished=false. Для integration-тестів
    // вставляємо тимчасовий опублікований запис, що базується на існуючому шаблоні
    // l_bracket (щоб detail route мав що резолвити). Cleanup — у afterAll.
    await client.db
      .insert(schema.products)
      .values({
        slug: "test-published-product",
        name: "Test Published Product",
        description: "Integration test placeholder для GET /products.",
        baseTemplateSlug: "l_bracket",
        fixedParameters: { thickness_mm: 2 },
        userEditableFields: ["legA_mm", "legB_mm"],
        previewImageUrl: "/product-previews/test.png",
        useCases: ["тест"],
        isPublished: true,
      })
      .onConflictDoNothing({ target: schema.products.slug });
  }, 30_000);

  afterAll(async () => {
    // Cleanup published-test record (не чіпаємо seed placeholder).
    if (client) {
      await client.db
        .delete(schema.products)
        .where(eq(schema.products.slug, "test-published-product"));
    }
    await app?.close();
    await client?.close();
  });

  it("повертає лише опубліковані продукти (placeholder isPublished=false ховається)", async () => {
    const res = await app.inject({ method: "GET", url: "/products" });
    expect(res.statusCode).toBe(200);
    const body = res.json<{ items: Array<{ slug: string; isPublished: boolean }> }>();
    expect(body.items.every((p) => p.isPublished)).toBe(true);
    const slugs = body.items.map((p) => p.slug);
    expect(slugs).toContain("test-published-product");
    expect(slugs).not.toContain("seed-placeholder");
  });

  it("response відповідає ProductListResponseSchema", async () => {
    const { ProductListResponseSchema } = await import("@flatcraft/types");
    const res = await app.inject({ method: "GET", url: "/products" });
    const parsed = ProductListResponseSchema.safeParse(res.json());
    expect(parsed.success).toBe(true);
  });

  it("listing маскує fixed_parameters і user_editable_fields (Summary, не Detail)", async () => {
    const res = await app.inject({ method: "GET", url: "/products" });
    const body = res.json<{ items: Array<Record<string, unknown>> }>();
    const item = body.items.find((p) => p["slug"] === "test-published-product");
    expect(item).toBeDefined();
    expect(item).not.toHaveProperty("fixedParameters");
    expect(item).not.toHaveProperty("userEditableFields");
  });

  it("сортує по slug ASC (стабільний порядок для UI)", async () => {
    const res = await app.inject({ method: "GET", url: "/products" });
    const body = res.json<{ items: Array<{ slug: string }> }>();
    const slugs = body.items.map((p) => p.slug);
    expect(slugs).toEqual([...slugs].sort());
  });

  it("GET /products/test-published-product → 200 з resolved baseTemplate і fixedParameters", async () => {
    const { ProductDetailSchema } = await import("@flatcraft/types");
    const res = await app.inject({ method: "GET", url: "/products/test-published-product" });
    expect(res.statusCode).toBe(200);
    const parsed = ProductDetailSchema.safeParse(res.json());
    expect(parsed.success).toBe(true);
    if (parsed.success) {
      expect(parsed.data.slug).toBe("test-published-product");
      expect(parsed.data.fixedParameters).toEqual({ thickness_mm: 2 });
      expect(parsed.data.userEditableFields).toEqual(["legA_mm", "legB_mm"]);
      expect(parsed.data.baseTemplate.slug).toBe("l_bracket");
      expect(parsed.data.baseTemplate.defaultParameters).toMatchObject({
        legA_mm: expect.any(Number),
        legB_mm: expect.any(Number),
      });
    }
  });

  it("GET /products/seed-placeholder → 404 (placeholder isPublished=false)", async () => {
    const res = await app.inject({ method: "GET", url: "/products/seed-placeholder" });
    expect(res.statusCode).toBe(404);
  });

  it("GET /products/does-not-exist → 404", async () => {
    const res = await app.inject({ method: "GET", url: "/products/does-not-exist" });
    expect(res.statusCode).toBe(404);
  });

  it("GET /products/INVALID_SLUG → 400 (regex validation, products = kebab-case)", async () => {
    // underscore — НЕ валідний продуктовий slug (templates pattern, не products)
    const res = await app.inject({ method: "GET", url: "/products/invalid_slug" });
    expect(res.statusCode).toBe(400);
  });

  it("GET /products/Capital → 400 (regex: lowercase ASCII)", async () => {
    const res = await app.inject({ method: "GET", url: "/products/Capital" });
    expect(res.statusCode).toBe(400);
  });
});
