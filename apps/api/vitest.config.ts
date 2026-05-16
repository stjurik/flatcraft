import { fileURLToPath } from "node:url";
import path from "node:path";

import { defineConfig } from "vitest/config";

const root = path.dirname(fileURLToPath(import.meta.url));
const workspaceRoot = path.resolve(root, "../../");

// Vitest не використовує tsconfig paths за замовчуванням. Без цих aliases
// `import { ... } from "@flatcraft/types"` резолвиться у packages/types/dist
// (порожнє до окремого build) → undefined exports → Fastify падає на
// "Cannot read properties of undefined (reading 'isFluentSchema')".
// Маппінг на src/index.ts дає ті ж шляхи, що tsx у dev, без build-кроку.
export default defineConfig({
  resolve: {
    alias: {
      "@flatcraft/types": path.join(workspaceRoot, "packages/types/src/index.ts"),
      "@flatcraft/db": path.join(workspaceRoot, "packages/db/src/index.ts"),
    },
  },
});
