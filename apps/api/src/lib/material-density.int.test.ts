/**
 * Інтеграційний тест дефолтного джерела густини (issue #261) — проти
 * реальної Postgres + seed. Skip-нутий, якщо DATABASE_URL відсутній (як
 * `routes/materials.int.test.ts`).
 */
import { createClient, runMigrations, runSeed, schema, type DatabaseClient } from "@flatcraft/db";
import { eq } from "drizzle-orm";
import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { createMaterialDensityLookup } from "./material-density.js";

const DATABASE_URL = process.env["DATABASE_URL"];

describe.skipIf(!DATABASE_URL)("createMaterialDensityLookup — integration", () => {
  let client: DatabaseClient;
  let inactiveCode: string;

  beforeAll(async () => {
    if (!DATABASE_URL) throw new Error("DATABASE_URL required");
    await runMigrations({ url: DATABASE_URL });
    await runSeed({ url: DATABASE_URL });
    client = createClient(DATABASE_URL);

    // Унікальний code, щоб не зіткнутись з паралельними тестами/повторними
    // прогонами — видаляється в afterAll.
    inactiveCode = `test_inactive_${randomUUID().slice(0, 8)}`;
    await client.db.insert(schema.materials).values({
      code: inactiveCode,
      nameUk: "Тестовий неактивний матеріал",
      nameEn: "Test inactive material",
      densityKgM3: "1234.00",
      category: "steel",
      isActive: false,
    });
  }, 30_000);

  afterAll(async () => {
    if (client) {
      await client.db.delete(schema.materials).where(eq(schema.materials.code, inactiveCode));
      await client.close();
    }
  });

  it("активний матеріал із seed → його density_kg_m3", async () => {
    const lookup = createMaterialDensityLookup(client.db);
    const density = await lookup("cold_rolled_steel");
    expect(density).toBe(7850);
  });

  it("неактивний матеріал (is_active=false) → null", async () => {
    const lookup = createMaterialDensityLookup(client.db);
    const density = await lookup(inactiveCode);
    expect(density).toBeNull();
  });

  it("відсутній код → null", async () => {
    const lookup = createMaterialDensityLookup(client.db);
    const density = await lookup("unobtanium_does_not_exist");
    expect(density).toBeNull();
  });
});
