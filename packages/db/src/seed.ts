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
import { createClient, type DatabaseClient } from "./client.js";
import { materialThicknesses, materials, templates } from "./schema.js";

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

// ─── Шаблони (placeholder, реальні Zod-схеми у packages/types) ─────────────
export interface TemplateSeed {
  readonly slug: string;
  readonly nameUk: string;
  readonly nameEn: string;
  readonly descriptionUk: string;
  readonly descriptionEn: string;
}

export const SEED_TEMPLATES: ReadonlyArray<TemplateSeed> = [
  {
    slug: "l_bracket",
    nameUk: "L-кронштейн",
    nameEn: "L-bracket",
    descriptionUk: "Кутник з двох полиць під 90°.",
    descriptionEn: "Two-flange right-angle bracket.",
  },
  {
    slug: "z_bracket",
    nameUk: "Z-кронштейн",
    nameEn: "Z-bracket",
    descriptionUk: "Z-подібний кронштейн з трьома секціями.",
    descriptionEn: "Z-shaped bracket with three segments.",
  },
  {
    slug: "corner_angle",
    nameUk: "Кутник",
    nameEn: "Corner angle",
    descriptionUk: "Підсилювальний кутник для меблів та конструкцій.",
    descriptionEn: "Reinforcement angle for furniture and structures.",
  },
  {
    slug: "wall_shelf",
    nameUk: "Полиця настінна",
    nameEn: "Wall shelf",
    descriptionUk: "Полиця з гнутих кронштейнів для кріплення до стіни.",
    descriptionEn: "Shelf with bent brackets for wall mounting.",
  },
  {
    slug: "perforated_panel",
    nameUk: "Перфо-панель",
    nameEn: "Perforated panel",
    descriptionUk: "Лист із сіткою отворів за заданим кроком.",
    descriptionEn: "Sheet with a grid of holes at a given pitch.",
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

  // parameters_schema / default_parameters заповнимо при імплементації шаблонів
  // (Phase 1.5 — L-кронштейн, Phase 2.10 — решта). До того ж — пусті JSONB.
  for (const t of SEED_TEMPLATES) {
    await db
      .insert(templates)
      .values({
        slug: t.slug,
        nameUk: t.nameUk,
        nameEn: t.nameEn,
        descriptionUk: t.descriptionUk,
        descriptionEn: t.descriptionEn,
        parametersSchema: {},
        defaultParameters: {},
      })
      .onConflictDoNothing({ target: templates.slug });
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
