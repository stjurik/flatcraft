import { fileURLToPath } from "node:url";
import path from "node:path";

import { defineConfig, type Plugin } from "vitest/config";

const root = path.dirname(fileURLToPath(import.meta.url));
const workspaceRoot = path.resolve(root, "../../");

/**
 * Inline-плагін: всередині `packages/*\/src` ремапить import з `.js`
 * на реальний `.ts` (verbatimModuleSyntax змушує писати .js у source).
 * Vite не робить це автоматично коли extension явно вказано.
 */
const stripWorkspaceJsExt = (): Plugin => ({
  name: "flatcraft-strip-js-ext",
  enforce: "pre",
  resolveId(source, importer) {
    if (!importer) return null;
    if (!importer.includes(`${path.sep}packages${path.sep}`)) return null;
    if (!source.startsWith(".") || !source.endsWith(".js")) return null;
    return this.resolve(source.replace(/\.js$/, ".ts"), importer, { skipSelf: true });
  },
});

// Vitest резолвить @flatcraft/types через main → dist (порожнє без build).
// Маппінг на src/index.ts дає той же шлях, що tsx у dev/seed.
export default defineConfig({
  plugins: [stripWorkspaceJsExt()],
  resolve: {
    alias: {
      "@flatcraft/types": path.join(workspaceRoot, "packages/types/src/index.ts"),
    },
  },
});
