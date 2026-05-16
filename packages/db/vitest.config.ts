import { fileURLToPath } from "node:url";
import path from "node:path";

import { defineConfig } from "vitest/config";

const root = path.dirname(fileURLToPath(import.meta.url));
const workspaceRoot = path.resolve(root, "../../");

// Vitest резолвить @flatcraft/types через main → dist (порожнє без build).
// Маппінг на src/index.ts дає той же шлях, що tsx у dev/seed.
export default defineConfig({
  resolve: {
    alias: {
      "@flatcraft/types": path.join(workspaceRoot, "packages/types/src/index.ts"),
    },
  },
});
