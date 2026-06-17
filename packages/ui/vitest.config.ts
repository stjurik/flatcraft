import { fileURLToPath } from "node:url";
import path from "node:path";

import { defineConfig } from "vitest/config";

const root = path.dirname(fileURLToPath(import.meta.url));
const workspaceRoot = path.resolve(root, "../../");

export default defineConfig({
  // R3FErrorBoundary.test.tsx містить JSX — esbuild потребує automatic-runtime
  // (інакше класичний transform шукає глобальний React).
  esbuild: {
    jsx: "automatic",
  },
  test: {
    // Heavy R3F Scene-компоненти лишаються без тесту (потребують jsdom/WebGL);
    // тестуємо pure-builder (geometry.test.ts) + R3FErrorBoundary через
    // static/instance-методи без DOM (r3f-error-boundary.test.tsx).
    include: ["src/**/*.test.ts", "src/**/*.test.tsx"],
  },
  resolve: {
    alias: {
      "@flatcraft/types": path.join(workspaceRoot, "packages/types/src/index.ts"),
    },
  },
});
