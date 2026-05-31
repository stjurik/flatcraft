/**
 * Каталог матеріалів з доступними товщинами.
 *
 *   GET /materials  → 200 { items: [{ code, name_uk, name_en, category, thicknesses_mm }] }
 *
 * JOIN materials ↔ material_thicknesses, лише `is_active = true` з обох
 * сторін; thicknesses_mm сортується за зростанням. Споживач — `<MaterialSection>`
 * у студії (Phase 2.12).
 */
import { MaterialListResponseSchema, type MaterialCategory } from "@flatcraft/types";
import { schema } from "@flatcraft/db";
import { and, asc, eq } from "drizzle-orm";
import type { FastifyPluginAsyncZod } from "fastify-type-provider-zod";

const ALLOWED_CATEGORIES: ReadonlySet<MaterialCategory> = new Set([
  "steel",
  "stainless",
  "aluminum",
  "non_ferrous",
]);

function isMaterialCategory(value: string): value is MaterialCategory {
  return ALLOWED_CATEGORIES.has(value as MaterialCategory);
}

export const materialRoutes: FastifyPluginAsyncZod = async (app) => {
  app.get(
    "/materials",
    {
      schema: {
        description: "Каталог активних матеріалів з доступними товщинами.",
        tags: ["materials"],
        response: { 200: MaterialListResponseSchema },
      },
    },
    async () => {
      const rows = await app.db
        .select({
          code: schema.materials.code,
          nameUk: schema.materials.nameUk,
          nameEn: schema.materials.nameEn,
          category: schema.materials.category,
          thicknessMm: schema.materialThicknesses.thicknessMm,
        })
        .from(schema.materials)
        .innerJoin(
          schema.materialThicknesses,
          eq(schema.materialThicknesses.materialId, schema.materials.id),
        )
        .where(
          and(eq(schema.materials.isActive, true), eq(schema.materialThicknesses.isActive, true)),
        )
        .orderBy(asc(schema.materials.code), asc(schema.materialThicknesses.thicknessMm));

      // Згрупуємо у Map зі збереженням порядку (ASC code + ASC thickness).
      const byCode = new Map<
        string,
        {
          code: string;
          name_uk: string;
          name_en: string;
          category: MaterialCategory;
          thicknesses_mm: number[];
        }
      >();
      for (const r of rows) {
        if (!isMaterialCategory(r.category)) {
          // Бракована категорія у БД — пропускаємо рядок, але не валимо запит.
          app.log.warn({ code: r.code, category: r.category }, "unexpected material category");
          continue;
        }
        const existing = byCode.get(r.code);
        const thickness = Number(r.thicknessMm);
        if (existing) {
          existing.thicknesses_mm.push(thickness);
        } else {
          byCode.set(r.code, {
            code: r.code,
            name_uk: r.nameUk,
            name_en: r.nameEn,
            category: r.category,
            thicknesses_mm: [thickness],
          });
        }
      }
      return { items: Array.from(byCode.values()) };
    },
  );
};
