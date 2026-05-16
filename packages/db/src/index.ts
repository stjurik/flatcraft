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
