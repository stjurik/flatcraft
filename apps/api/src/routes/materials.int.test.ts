/**
 * Інтеграційний тест GET /materials проти реальної Postgres + seed.
 * Skip-нутий, якщо DATABASE_URL відсутній (як templates.int.test.ts).
 */
import { createClient, runMigrations, runSeed, type DatabaseClient } from "@flatcraft/db";
import { MaterialListResponseSchema } from "@flatcraft/types";
import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { createServer } from "../server.js";

const DATABASE_URL = process.env["DATABASE_URL"];

describe.skipIf(!DATABASE_URL)("GET /materials — integration", () => {
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

  it("повертає 7 активних матеріалів зі схемою MaterialListResponseSchema", async () => {
    const res = await app.inject({ method: "GET", url: "/materials" });
    expect(res.statusCode).toBe(200);
    const parsed = MaterialListResponseSchema.safeParse(res.json());
    expect(parsed.success).toBe(true);
    if (!parsed.success) return;
    expect(parsed.data.items.length).toBe(7);
  });

  it("нержавійка (stainless_*) не має 10мм у thicknesses_mm (seed §4)", async () => {
    const res = await app.inject({ method: "GET", url: "/materials" });
    const body = res.json<{ items: Array<{ code: string; thicknesses_mm: number[] }> }>();
    const stainless = body.items.filter((m) => m.code.startsWith("stainless_"));
    expect(stainless.length).toBeGreaterThan(0);
    for (const m of stainless) {
      expect(m.thicknesses_mm).not.toContain(10);
    }
  });

  it("cold_rolled_steel містить 2.0мм (дефолтна товщина студії)", async () => {
    const res = await app.inject({ method: "GET", url: "/materials" });
    const body = res.json<{ items: Array<{ code: string; thicknesses_mm: number[] }> }>();
    const cold = body.items.find((m) => m.code === "cold_rolled_steel");
    expect(cold).toBeDefined();
    expect(cold?.thicknesses_mm).toContain(2);
  });

  it("thicknesses_mm у кожному матеріалі відсортовані ASC", async () => {
    const res = await app.inject({ method: "GET", url: "/materials" });
    const body = res.json<{ items: Array<{ thicknesses_mm: number[] }> }>();
    for (const m of body.items) {
      const sorted = [...m.thicknesses_mm].sort((a, b) => a - b);
      expect(m.thicknesses_mm).toEqual(sorted);
    }
  });
});
