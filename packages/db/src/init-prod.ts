/**
 * Prod DB init — застосувати міграції, потім seed. Викликається api-entrypoint'ом
 * (infra/docker/api-entrypoint.sh) перед стартом сервера.
 *
 * Чому окремий explicit-скрипт, а не isMain-гілка в migrate.ts / seed.ts:
 * `pnpm deploy` лінкує @flatcraft/db симлінком у .pnpm, через що
 * `import.meta.url` (realpath) ≠ `file://${argv[1]}`, і isMain мовчки = false —
 * скрипти запускаються, але нічого не роблять. Тут викликаємо експортовані
 * функції напряму, без вгадування entrypoint'а.
 */
import { runMigrations } from "./migrate.js";
import { runSeed } from "./seed.js";

async function main(): Promise<void> {
  await runMigrations();
  console.info("[init-prod] migrations applied.");
  await runSeed();
  console.info("[init-prod] seed completed.");
}

main().catch((err: unknown) => {
  console.error("[init-prod] DB init failed:", err);
  process.exit(1);
});
