import { fileURLToPath } from "node:url";
import path from "node:path";

import { defineConfig } from "vitest/config";

const root = path.dirname(fileURLToPath(import.meta.url));
const workspaceRoot = path.resolve(root, "../../");

export default defineConfig({
  test: {
    // .tsx-компоненти (Scene) потребують R3F/jsdom для рендерингу; ми
    // тестуємо лише pure-builder geometry.test.ts → достатньо node.
    include: ["src/**/*.test.ts"],
  },
  resolve: {
    alias: {
      "@flatcraft/types": path.join(workspaceRoot, "packages/types/src/index.ts"),
    },
  },
});
