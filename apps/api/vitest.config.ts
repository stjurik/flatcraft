import { fileURLToPath } from "node:url";
import path from "node:path";

import { defineConfig, type Plugin } from "vitest/config";

const root = path.dirname(fileURLToPath(import.meta.url));
const workspaceRoot = path.resolve(root, "../../");

/**
 * Inline-плагін: всередині `packages/*\/src` ремапить import з `.js`
 * на реальний `.ts`. Це потрібно, бо tsconfig.base має `verbatimModuleSyntax: true`,
 * через що ts-файли пишуть один до одного з `.js` extension; Vite-resolver
 * за замовчуванням НЕ підмінює .js → .ts якщо extension явно вказано.
 */
const stripWorkspaceJsExt = (): Plugin => ({
  name: "flatcraft-strip-js-ext",
  enforce: "pre",
  resolveId(source, importer) {
    if (!importer) return null;
    if (!importer.includes(`${path.sep}packages${path.sep}`)) return null;
    if (!source.startsWith(".") || !source.endsWith(".js")) return null;
    // Замінюємо `.js` на `.ts` (бо це reference на TS-файл, скомпільований
    // як .js у dist; у src/ він живе як .ts).
    return this.resolve(source.replace(/\.js$/, ".ts"), importer, { skipSelf: true });
  },
});

// Vitest не використовує tsconfig paths за замовчуванням. Без цих aliases
// `import { ... } from "@flatcraft/types"` резолвиться у packages/types/dist
// (порожнє до окремого build) → undefined exports → Fastify падає на
// "Cannot read properties of undefined (reading 'isFluentSchema')".
// Маппінг на src/index.ts дає ті ж шляхи, що tsx у dev, без build-кроку.
export default defineConfig({
  plugins: [stripWorkspaceJsExt()],
  resolve: {
    alias: {
      "@flatcraft/types": path.join(workspaceRoot, "packages/types/src/index.ts"),
      "@flatcraft/db": path.join(workspaceRoot, "packages/db/src/index.ts"),
    },
  },
});
