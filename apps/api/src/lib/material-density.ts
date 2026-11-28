/**
 * Густина матеріалу з бази (issue #261): джерело маси в PDF, замість
 * фіксованого 7850 (сталь) для будь-якого матеріалу у cad-worker.
 *
 * Дефолт — одна таблиця істини `materials` (`packages/db/src/schema.ts`,
 * колонка `density_kg_m3`), фільтр `is_active = true`; `null` — матеріалу
 * немає чи він неактивний (`buildExportRoutes` мапить це у 422
 * `MATERIAL_NOT_FOUND`). Override для тестів — так само, як `telemetry`
 * (`CreateServerOptions.telemetry`).
 */
import type { DatabaseClient } from "@flatcraft/db";
import { schema } from "@flatcraft/db";
import { and, eq } from "drizzle-orm";

type Db = DatabaseClient["db"];

export type MaterialDensityLookup = (code: string) => Promise<number | null>;

export function createMaterialDensityLookup(db: Db): MaterialDensityLookup {
  return async (code) => {
    const rows = await db
      .select({ densityKgM3: schema.materials.densityKgM3 })
      .from(schema.materials)
      .where(and(eq(schema.materials.code, code), eq(schema.materials.isActive, true)))
      .limit(1);
    const row = rows[0];
    if (!row) return null;
    return Number(row.densityKgM3);
  };
}
