import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { connect } from "../lib/client.js";
import { fetchActualState } from "../lib/fetch-state.js";
import { renderSnapshotMarkdown } from "../lib/markdown.js";

// Read-only: pull live state → docs/discord-config/{snapshot.json, README.md}.
// Запускається і локально, і weekly GH Action'ом (drift detection).

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const OUT_DIR = join(REPO_ROOT, "docs", "discord-config");

async function main(): Promise<void> {
  const { client, guild } = await connect();
  try {
    const state = await fetchActualState(guild);

    mkdirSync(OUT_DIR, { recursive: true });
    writeFileSync(join(OUT_DIR, "snapshot.json"), `${JSON.stringify(state, null, 2)}\n`);
    writeFileSync(
      join(OUT_DIR, "README.md"),
      renderSnapshotMarkdown(state, { guildName: guild.name }),
    );

    console.info(
      `Snapshot: ${state.roles.length} ролей, ${state.categories.length} категорій, ` +
        `${state.channels.length} каналів → docs/discord-config/`,
    );
  } finally {
    await client.destroy();
  }
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
