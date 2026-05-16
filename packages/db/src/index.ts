/**
 * @flatcraft/db — Drizzle ORM schema, клієнт, міграції, seed.
 *
 * Точка входу: `createClient` для застосунків + реекспорт схеми.
 * Документація моделі — docs/05_DATA_MODEL.md.
 */

export const DB_PACKAGE_VERSION = "0.0.0" as const;

export { createClient } from "./client.js";
export type { CreateClientOptions, DatabaseClient } from "./client.js";
export * as schema from "./schema.js";
export { runMigrations, type RunMigrationsOptions } from "./migrate.js";
export {
  runSeed,
  SEED_MATERIALS,
  SEED_TEMPLATES,
  STAINLESS_EXCLUDED_THICKNESS_MM,
  STANDARD_THICKNESSES_MM,
  type MaterialSeed,
  type RunSeedOptions,
  type TemplateSeed,
} from "./seed.js";
