/**
 * Migration runner — застосовує всі src/migrations/*.sql до Postgres,
 * вказаного у DATABASE_URL. Викликається:
 *   - CLI:  pnpm --filter @flatcraft/db migrate
 *   - CI:   у GitHub Actions перед integration-тестами
 *   - Prod: у entrypoint контейнера api перед запуском сервера
 */
import { fileURLToPath } from "node:url";
import path from "node:path";

import { drizzle } from "drizzle-orm/postgres-js";
import { migrate } from "drizzle-orm/postgres-js/migrator";
import postgres from "postgres";

const MIGRATIONS_FOLDER = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "migrations");

export interface RunMigrationsOptions {
  readonly url?: string;
  readonly migrationsFolder?: string;
}

export async function runMigrations(options: RunMigrationsOptions = {}): Promise<void> {
  const url = options.url ?? process.env["DATABASE_URL"];
  if (!url) {
    throw new Error("DATABASE_URL is not set. Pass options.url or define it in the environment.");
  }

  const folder = options.migrationsFolder ?? MIGRATIONS_FOLDER;
  // postgres-js рекомендує max: 1 для міграцій, щоб не блокуватись на pool.
  const sql = postgres(url, { max: 1 });
  try {
    await migrate(drizzle(sql), { migrationsFolder: folder });
  } finally {
    await sql.end({ timeout: 5 });
  }
}

// CLI entrypoint: `tsx src/migrate.ts` (через pnpm migrate).
const isMain =
  import.meta.url === `file://${process.argv[1]}` ||
  process.argv[1]?.endsWith("/migrate.ts") === true;
if (isMain) {
  runMigrations()
    .then(() => {
      console.info("Migrations applied successfully.");
    })
    .catch((err: unknown) => {
      console.error("Migration failed:", err);
      process.exitCode = 1;
    });
}
