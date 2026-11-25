/**
 * Юніт-тест `createMaterialDensityLookup` (issue #261) — проти фіктивного
 * drizzle-ланцюжка (select→from→where→limit), без реальної Postgres
 * (інтеграційний варіант дефолтного джерела — `material-density.int.test.ts`).
 */
import { describe, expect, it, vi } from "vitest";

import { createMaterialDensityLookup, type MaterialDensityLookup } from "./material-density.js";

function fakeDb(
  rows: ReadonlyArray<{ densityKgM3: string | number }>,
): Parameters<typeof createMaterialDensityLookup>[0] {
  const limit = vi.fn().mockResolvedValue(rows);
  const where = vi.fn().mockReturnValue({ limit });
  const from = vi.fn().mockReturnValue({ where });
  const select = vi.fn().mockReturnValue({ from });
  return { select } as unknown as Parameters<typeof createMaterialDensityLookup>[0];
}

describe("createMaterialDensityLookup", () => {
  let lookup: MaterialDensityLookup;

  it("знайдений активний матеріал → число (numeric-рядок → Number)", async () => {
    lookup = createMaterialDensityLookup(fakeDb([{ densityKgM3: "7850.00" }]));
    expect(await lookup("cold_rolled_steel")).toBe(7850);
  });

  it("немає рядків (невідомий код чи is_active=false відфільтровано) → null", async () => {
    lookup = createMaterialDensityLookup(fakeDb([]));
    expect(await lookup("unobtanium")).toBeNull();
  });

  it("density_kg_m3 з нецілою частиною (алюміній 2660.50) конвертується точно", async () => {
    lookup = createMaterialDensityLookup(fakeDb([{ densityKgM3: "2660.50" }]));
    expect(await lookup("aluminum_5754")).toBe(2660.5);
  });
});
