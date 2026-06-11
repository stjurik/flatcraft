import { CATEGORIES } from "../config/categories.js";
import { CHANNELS } from "../config/channels.js";
import { ROLES } from "../config/roles.js";
import { validateConfigIntegrity } from "../config/types.js";
import { connect } from "../lib/client.js";
import { diffAll } from "../lib/diff.js";
import { fetchActualState } from "../lib/fetch-state.js";
import { formatOps } from "../lib/format-ops.js";

// Dry-run: показує, що зробив би apply. Жодного write.

async function main(): Promise<void> {
  const config = { roles: ROLES, categories: CATEGORIES, channels: CHANNELS };
  const integrityErrors = validateConfigIntegrity(config);
  if (integrityErrors.length > 0) {
    for (const err of integrityErrors) console.error(`CONFIG: ${err}`);
    process.exitCode = 1;
    return;
  }

  const { client, guild } = await connect();
  try {
    const state = await fetchActualState(guild);
    const ops = diffAll(state, config);
    console.info(formatOps(ops));
  } finally {
    await client.destroy();
  }
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
