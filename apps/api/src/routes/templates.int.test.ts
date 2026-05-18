/**
 * Інтеграційний тест GET /templates — проти реальної Postgres.
 *
 * Запускається коли `DATABASE_URL` визначений (локально через docker compose,
 * у CI через postgres service-контейнер). Без env — describe.skip, щоб
 * `pnpm test` не падав на машинах без бази.
 *
 * У beforeAll: повна setup state — migrate + seed. Tearndown: client.close().
 */
import { createClient, runMigrations, runSeed, type DatabaseClient } from "@flatcraft/db";
import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { createServer } from "../server.js";

const DATABASE_URL = process.env["DATABASE_URL"];

describe.skipIf(!DATABASE_URL)("GET /templates — integration", () => {
  let app: FastifyInstance;
  let client: DatabaseClient;

  beforeAll(async () => {
    if (!DATABASE_URL) throw new Error("DATABASE_URL required");
    await runMigrations({ url: DATABASE_URL });
    await runSeed({ url: DATABASE_URL });
    client = createClient(DATABASE_URL);
    app = await createServer({ logger: false, dbClient: client });
  }, 30_000);

  afterAll(async () => {
    await app?.close();
    await client?.close();
  });

  it("повертає лише опубліковані шаблони (L-bracket, Z-bracket, corner_angle)", async () => {
    const res = await app.inject({ method: "GET", url: "/templates" });
    expect(res.statusCode).toBe(200);
    const body = res.json<{
      items: Array<{ slug: string; isPublished: boolean; nameUk: string }>;
    }>();
    expect(body.items.length).toBeGreaterThanOrEqual(3);
    expect(body.items.every((t) => t.isPublished)).toBe(true);
    const slugs = body.items.map((t) => t.slug);
    expect(slugs).toContain("l_bracket");
    expect(slugs).toContain("z_bracket");
    expect(slugs).toContain("corner_angle");
    // Phase 2.10.c/d ще не опубліковано:
    for (const slug of ["wall_shelf", "perforated_panel"]) {
      expect(slugs).not.toContain(slug);
    }
  });

  it("response відповідає TemplateListResponseSchema", async () => {
    const { TemplateListResponseSchema } = await import("@flatcraft/types");
    const res = await app.inject({ method: "GET", url: "/templates" });
    const parsed = TemplateListResponseSchema.safeParse(res.json());
    expect(parsed.success).toBe(true);
  });

  it("відсортовано по slug ASC (стабільний порядок для UI)", async () => {
    const res = await app.inject({ method: "GET", url: "/templates" });
    const body = res.json<{ items: Array<{ slug: string }> }>();
    const slugs = body.items.map((t) => t.slug);
    expect(slugs).toEqual([...slugs].sort());
  });

  it("GET /templates/l_bracket → 200 з defaultParameters", async () => {
    const { TemplateDetailSchema } = await import("@flatcraft/types");
    const res = await app.inject({ method: "GET", url: "/templates/l_bracket" });
    expect(res.statusCode).toBe(200);
    const parsed = TemplateDetailSchema.safeParse(res.json());
    expect(parsed.success).toBe(true);
    if (parsed.success) {
      expect(parsed.data.slug).toBe("l_bracket");
      expect(parsed.data.defaultParameters).toMatchObject({
        legA_mm: expect.any(Number),
        legB_mm: expect.any(Number),
        bend_radius_mm: expect.any(Number),
        bend_angle_deg: 90,
        width_mm: expect.any(Number),
      });
    }
  });

  it("GET /templates/z_bracket → 200 з offset_mm у defaults (Phase 2.10)", async () => {
    const res = await app.inject({ method: "GET", url: "/templates/z_bracket" });
    expect(res.statusCode).toBe(200);
    const body = res.json<{ slug: string; defaultParameters: Record<string, unknown> }>();
    expect(body.slug).toBe("z_bracket");
    expect(body.defaultParameters).toMatchObject({
      top_flange_mm: expect.any(Number),
      bottom_flange_mm: expect.any(Number),
      offset_mm: expect.any(Number),
    });
  });

  it("GET /templates/corner_angle → 200 з hole_rows/cols у defaults (Phase 2.10.b)", async () => {
    const res = await app.inject({ method: "GET", url: "/templates/corner_angle" });
    expect(res.statusCode).toBe(200);
    const body = res.json<{ slug: string; defaultParameters: Record<string, unknown> }>();
    expect(body.slug).toBe("corner_angle");
    expect(body.defaultParameters).toMatchObject({
      legA_mm: expect.any(Number),
      legB_mm: expect.any(Number),
      hole_rows: expect.any(Number),
      hole_cols: expect.any(Number),
      hole_diameter_mm: expect.any(Number),
    });
  });

  it("GET /templates/wall_shelf → 404 (неопублікований)", async () => {
    const res = await app.inject({ method: "GET", url: "/templates/wall_shelf" });
    expect(res.statusCode).toBe(404);
  });

  it("GET /templates/does_not_exist → 404", async () => {
    const res = await app.inject({ method: "GET", url: "/templates/does_not_exist" });
    expect(res.statusCode).toBe(404);
  });

  it("GET /templates/INVALID-SLUG → 400 (regex validation)", async () => {
    const res = await app.inject({ method: "GET", url: "/templates/INVALID-SLUG" });
    expect(res.statusCode).toBe(400);
  });
});
