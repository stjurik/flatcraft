/**
 * Seed для довідкових даних (матеріали, товщини, шаблони).
 * Idempotent: повторний запуск нічого не дублює (onConflictDoNothing).
 *
 * Що НЕ сідається тут:
 *   - Admin user → потрібен Argon2id, додамо у Phase 3 (auth).
 *   - Зразкові drafts/exports — лише після появи перших користувачів.
 *
 * Дизайн:
 *   - Експортовані SEED_MATERIALS / SEED_TEMPLATES / STANDARD_THICKNESSES_MM
 *     як чисті дані → легко юніт-тестувати, переvикористовувати у migrations
 *     та CI fixtures.
 *   - runSeed(client) — окрема функція, працює з будь-яким drizzle-інстансом
 *     (production, integration tests).
 */
import {
  CORNER_ANGLE_DEFAULT_PARAMETERS,
  ENCLOSED_SHELF_DEFAULT_PARAMETERS,
  L_BRACKET_DEFAULT_PARAMETERS,
  PERFORATED_PANEL_DEFAULT_PARAMETERS,
  PERFORATED_PANEL_SQUARE_DEFAULT_PARAMETERS,
  WALL_SHELF_DEFAULT_PARAMETERS,
  Z_BRACKET_DEFAULT_PARAMETERS,
} from "@flatcraft/types";

import { createClient, type DatabaseClient } from "./client.js";
import { materialThicknesses, materials, templates } from "./schema.js";
import { seedProducts } from "./seed-products.js";

// ─── Матеріали (doc/05 §4) ─────────────────────────────────────────────────
export interface MaterialSeed {
  readonly code: string;
  readonly nameUk: string;
  readonly nameEn: string;
  readonly densityKgM3: string; // numeric → string (drizzle convention)
  readonly category: "steel" | "stainless" | "aluminum" | "non_ferrous";
}

export const SEED_MATERIALS: ReadonlyArray<MaterialSeed> = [
  {
    code: "cold_rolled_steel",
    nameUk: "Сталь холоднокатана DC01",
    nameEn: "Cold-rolled steel DC01",
    densityKgM3: "7850.00",
    category: "steel",
  },
  {
    code: "hot_rolled_steel",
    nameUk: "Сталь гарячекатана S235JR",
    nameEn: "Hot-rolled steel S235JR",
    densityKgM3: "7850.00",
    category: "steel",
  },
  {
    code: "galvanized_steel",
    nameUk: "Сталь оцинкована DX51D+Z",
    nameEn: "Galvanized steel DX51D+Z",
    densityKgM3: "7850.00",
    category: "steel",
  },
  {
    code: "stainless_304",
    nameUk: "Нержавійка AISI 304",
    nameEn: "Stainless steel AISI 304",
    densityKgM3: "8000.00",
    category: "stainless",
  },
  {
    code: "stainless_430",
    nameUk: "Нержавійка AISI 430",
    nameEn: "Stainless steel AISI 430",
    densityKgM3: "7700.00",
    category: "stainless",
  },
  {
    code: "aluminum_5754",
    nameUk: "Алюміній 5754 H22",
    nameEn: "Aluminum 5754 H22",
    densityKgM3: "2660.00",
    category: "aluminum",
  },
  {
    code: "aluminum_amg3",
    nameUk: "Алюміній АМг3",
    nameEn: "Aluminum AMg3",
    densityKgM3: "2670.00",
    category: "aluminum",
  },
];

// ─── Товщини (стандартний прайс-лист) ──────────────────────────────────────
export const STANDARD_THICKNESSES_MM: readonly number[] = [
  1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0,
];

// За doc/05 §4: нержавійка у 10мм за прайсом ESI не йде.
export const STAINLESS_EXCLUDED_THICKNESS_MM = 10.0;

// ─── Шаблони (Zod-схеми параметрів — у packages/types/templates/*) ─────────
export interface TemplateSeed {
  readonly slug: string;
  readonly nameUk: string;
  readonly nameEn: string;
  readonly descriptionUk: string;
  readonly descriptionEn: string;
  /** Видимий у каталозі `/templates`. false для шаблонів без готового CAD-builder. */
  readonly isPublished: boolean;
  /** Стартові значення параметрів — підвантажуються у редактор при відкритті. */
  readonly defaultParameters: Readonly<Record<string, unknown>>;
  /**
   * Phase 2.16.b: preview-PNG (3D-snapshot) для каталога. Шлях
   * відносний до web `/public/`. null → fallback на inline SVG-thumb
   * (Phase 2.13).
   */
  readonly previewImageUrl: string | null;
}

export const SEED_TEMPLATES: ReadonlyArray<TemplateSeed> = [
  {
    slug: "l_bracket",
    nameUk: "L-кронштейн",
    nameEn: "L-bracket",
    descriptionUk: "Кутник з двох полиць під 90°.",
    descriptionEn: "Two-flange right-angle bracket.",
    // Phase 1.5 — CadQuery-builder готовий, шаблон публікуємо.
    isPublished: true,
    defaultParameters: L_BRACKET_DEFAULT_PARAMETERS,
    previewImageUrl: "/template-previews/l_bracket.png",
  },
  {
    slug: "z_bracket",
    nameUk: "Z-кронштейн",
    nameEn: "Z-bracket",
    descriptionUk: "Z-подібний кронштейн з трьома секціями і двома гибами.",
    descriptionEn: "Z-shaped bracket with three segments and two bends.",
    // Phase 2.10 — CadQuery-builder і CAD-pipeline готові.
    isPublished: true,
    defaultParameters: Z_BRACKET_DEFAULT_PARAMETERS,
    previewImageUrl: "/template-previews/z_bracket.png",
  },
  {
    slug: "corner_angle",
    nameUk: "Кутник",
    nameEn: "Corner angle",
    descriptionUk: "Підсилювальний кутник з grid отворів для меблів та конструкцій.",
    descriptionEn: "Reinforcement angle with hole grid for furniture and structures.",
    // Phase 2.10.b — CadQuery-builder і auto-grid hole pattern готові.
    isPublished: true,
    defaultParameters: CORNER_ANGLE_DEFAULT_PARAMETERS,
    previewImageUrl: "/template-previews/corner_angle.png",
  },
  {
    slug: "wall_shelf",
    nameUk: "Полиця настінна",
    nameEn: "Wall shelf",
    descriptionUk: "U-channel настінна полиця з mounting holes на back-стінці.",
    descriptionEn: "U-channel wall shelf with mounting holes on the back.",
    // Phase 2.10.c — CadQuery-builder + 1/2 bends + auto-grid mount holes.
    isPublished: true,
    defaultParameters: WALL_SHELF_DEFAULT_PARAMETERS,
    previewImageUrl: "/template-previews/wall_shelf.png",
  },
  {
    slug: "perforated_panel",
    nameUk: "Перфо-панель",
    nameEn: "Perforated panel",
    descriptionUk: "Плоский лист із сіткою отворів за заданим pitch (без гибів).",
    descriptionEn: "Flat sheet with a grid of holes at given pitch (no bends).",
    // Phase 2.10.d — Phase 2.10 повністю закрита.
    isPublished: true,
    defaultParameters: PERFORATED_PANEL_DEFAULT_PARAMETERS,
    previewImageUrl: "/template-previews/perforated_panel.png",
  },
  {
    slug: "perforated_panel_square",
    nameUk: "Перфо-панель (квадратні отвори)",
    nameEn: "Perforated panel (square holes)",
    descriptionUk:
      "Плоский лист із сіткою КВАДРАТНИХ отворів. Базовий шаблон для декоративних виробів (Phase 3.0, ADR-027 Рішення 6).",
    descriptionEn:
      "Flat sheet with a grid of SQUARE holes. Base template for decorative products (Phase 3.0).",
    // Phase 3.0 PR 5: base шаблон не публікується у каталозі — споживається
    // лише через products (PR 6 — декоративна перфо-панель).
    isPublished: false,
    defaultParameters: PERFORATED_PANEL_SQUARE_DEFAULT_PARAMETERS,
    previewImageUrl: null,
  },
  {
    slug: "enclosed_shelf",
    nameUk: "Закрита полиця (cross-розгортка)",
    nameEn: "Enclosed shelf (cross-unfold)",
    descriptionUk:
      "Базовий шаблон 4-сторонньої полиці (back + bottom + 2 квадратні бокові). Опційні features: side perforation, stiffening rib. Phase 3.0 PR 7 (ADR-027 Рішення 5).",
    descriptionEn:
      "Base 4-sided shelf template (back + bottom + 2 square sides). Optional features: side perforation, stiffening rib. Phase 3.0 PR 7.",
    // PR 7a: типи + Pydantic + seed. Builder/unfold/export — PR 7b/7c.
    // Не публікується у каталозі — споживається лише через products (PR 8 —
    // кастомна настінна полиця).
    isPublished: false,
    defaultParameters: ENCLOSED_SHELF_DEFAULT_PARAMETERS,
    previewImageUrl: null,
  },
];

// ─── Імплементація runSeed ─────────────────────────────────────────────────
export interface RunSeedOptions {
  readonly url?: string;
}

export async function runSeed(options: RunSeedOptions = {}): Promise<void> {
  const client = createClient(options.url);
  try {
    await seedMaterialsAndThicknesses(client);
    await seedTemplates(client);
    await seedProducts(client);
  } finally {
    await client.close();
  }
}

async function seedMaterialsAndThicknesses(client: DatabaseClient): Promise<void> {
  const { db } = client;

  // Drizzle insert вимагає мутабельний масив; spread знімає readonly.
  await db
    .insert(materials)
    .values([...SEED_MATERIALS])
    .onConflictDoNothing({ target: materials.code });

  // Підвантажуємо id-шники після insert (idempotent шлях — отримуємо всі).
  const dbMaterials = await db
    .select({ id: materials.id, code: materials.code, category: materials.category })
    .from(materials);

  const rows = dbMaterials.flatMap((m) =>
    STANDARD_THICKNESSES_MM.filter(
      (t) => !(m.category === "stainless" && t === STAINLESS_EXCLUDED_THICKNESS_MM),
    ).map((t) => ({
      materialId: m.id,
      thicknessMm: t.toFixed(2),
    })),
  );

  if (rows.length > 0) {
    await db.insert(materialThicknesses).values(rows).onConflictDoNothing();
  }
}

async function seedTemplates(client: DatabaseClient): Promise<void> {
  const { db } = client;

  // parametersSchema залишається {} — Zod-схеми поки в @flatcraft/types,
  // web вибирає за slug. defaultParameters — реальні preset з типів.
  for (const t of SEED_TEMPLATES) {
    // upsert (onConflictDoUpdate) — щоб переключення is_published / зміна
    // descriptions / defaultParameters у seed-коді відбивалися у БД при
    // повторному `pnpm db:seed`. onConflictDoNothing залишав би записи
    // у застарілому стані.
    await db
      .insert(templates)
      .values({
        slug: t.slug,
        nameUk: t.nameUk,
        nameEn: t.nameEn,
        descriptionUk: t.descriptionUk,
        descriptionEn: t.descriptionEn,
        parametersSchema: {},
        defaultParameters: t.defaultParameters,
        previewImageUrl: t.previewImageUrl,
        isPublished: t.isPublished,
      })
      .onConflictDoUpdate({
        target: templates.slug,
        set: {
          nameUk: t.nameUk,
          nameEn: t.nameEn,
          descriptionUk: t.descriptionUk,
          descriptionEn: t.descriptionEn,
          defaultParameters: t.defaultParameters,
          previewImageUrl: t.previewImageUrl,
          isPublished: t.isPublished,
        },
      });
  }
}

// CLI entrypoint
const isMain =
  import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith("/seed.ts") === true;
if (isMain) {
  runSeed()
    .then(() => {
      console.info("Seed completed.");
    })
    .catch((err: unknown) => {
      console.error("Seed failed:", err);
      process.exitCode = 1;
    });
}
