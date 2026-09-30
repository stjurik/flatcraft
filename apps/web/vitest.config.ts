import { fileURLToPath } from "node:url";

import { defineConfig } from "vitest/config";

export default defineConfig({
  // tsconfig.base.json має `jsx:"preserve"` (Next-tooling трансформує сам);
  // vitest же використовує esbuild напряму — без явного react-jsx падає
  // на «React is not defined» в test-файлах з JSX.
  esbuild: {
    jsx: "automatic",
  },
  resolve: {
    // Масив, а не об'єкт: спрацьовує ПЕРШИЙ збіг, а рядок "@flatcraft/ui"
    // збігається і з "@flatcraft/ui/parameter-form" — тож вужчий запис іде першим.
    alias: [
      // Issue #96: справжня форма (без R3F) — для тесту складу форми
      // (registry-template-editor-fields.test.tsx). Із src, не з dist —
      // з тієї ж причини, що й стаб нижче.
      {
        find: "@flatcraft/ui/parameter-form",
        replacement: fileURLToPath(
          new URL("../../packages/ui/src/parameter-form/index.ts", import.meta.url),
        ),
      },
      // Hotfix 2.9.c: барель @flatcraft/ui тягне R3F 3d-viewport і резолвиться з
      // dist (крихко щодо порядку turbo-build). Лише editor-wrapper тести його
      // вживають — і тільки AutoForm/zodIssuesToFieldErrors. Стаб робить web
      // unit-suite незалежною від dist. Деталі — у src/test/flatcraft-ui-stub.tsx.
      {
        find: "@flatcraft/ui",
        replacement: fileURLToPath(new URL("./src/test/flatcraft-ui-stub.tsx", import.meta.url)),
      },
    ],
  },
  test: {
    // Playwright e2e живуть у tests/e2e — їх запускає окрема цільова команда
    // `test:e2e` (playwright test). Без виключення vitest намагається їх
    // транспілювати як unit-suite і падає на test.describe.
    exclude: ["**/node_modules/**", "**/dist/**", "**/.next/**", "tests/e2e/**"],
  },
});
