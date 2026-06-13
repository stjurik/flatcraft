import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { Client, GatewayIntentBits, type Guild } from "discord.js";

const PACKAGE_DIR = join(dirname(fileURLToPath(import.meta.url)), "..");

/**
 * Мінімальний .env-loader (KEY=VALUE, # коментарі) — без dotenv-залежності.
 * process.env має пріоритет (CI передає secrets через env, без .env-файлу).
 */
export function loadDotenv(dir: string = PACKAGE_DIR): void {
  const envPath = join(dir, ".env");
  if (!existsSync(envPath)) return;
  for (const line of readFileSync(envPath, "utf8").split("\n")) {
    const trimmed = line.trim();
    if (trimmed === "" || trimmed.startsWith("#")) continue;
    const eq = trimmed.indexOf("=");
    if (eq === -1) continue;
    const key = trimmed.slice(0, eq).trim();
    const value = trimmed.slice(eq + 1).trim();
    if (process.env[key] === undefined) process.env[key] = value;
  }
}

function requireEnv(name: string): string {
  const value = process.env[name];
  if (value === undefined || value === "") {
    throw new Error(
      `Нема env var ${name}. Заповніть infra/discord/.env (див. MANUAL_SETUP.md) ` +
        `або передайте через середовище (CI: GH Secrets).`,
    );
  }
  return value;
}

export interface Connection {
  client: Client;
  guild: Guild;
}

/**
 * Login + fetch guild. Intent лише Guilds: ролі/канали/overwrites його
 * достатньо, а privileged Server Members Intent (окремий toggle у Dev
 * Portal) НЕ потрібен — без нього login не падає з "disallowed intents".
 */
export async function connect(): Promise<Connection> {
  loadDotenv();
  const token = requireEnv("DISCORD_BOT_TOKEN");
  const guildId = requireEnv("DISCORD_GUILD_ID");

  const client = new Client({ intents: [GatewayIntentBits.Guilds] });
  await client.login(token);

  try {
    // force: true → REST-fetch повного guild. Без цього одразу після login()
    // повертається частковий guild із gateway-кешу, де `features` ще undefined
    // (apply preflight на `guild.features.includes` падав). REST гарантує повноту.
    const guild = await client.guilds.fetch({ guild: guildId, force: true });
    return { client, guild };
  } catch (error) {
    await client.destroy();
    throw new Error(
      `Не вдалось отримати guild ${guildId}: бот доданий у сервер? ` +
        `(MANUAL_SETUP.md, крок 3). Оригінальна помилка: ${String(error)}`,
    );
  }
}
