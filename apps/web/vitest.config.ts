import { defineConfig } from "vitest/config";

export default defineConfig({
  // tsconfig.base.json має `jsx:"preserve"` (Next-tooling трансформує сам);
  // vitest же використовує esbuild напряму — без явного react-jsx падає
  // на «React is not defined» в test-файлах з JSX.
  esbuild: {
    jsx: "automatic",
  },
  test: {
    // Playwright e2e живуть у tests/e2e — їх запускає окрема цільова команда
    // `test:e2e` (playwright test). Без виключення vitest намагається їх
    // транспілювати як unit-suite і падає на test.describe.
    exclude: ["**/node_modules/**", "**/dist/**", "**/.next/**", "tests/e2e/**"],
  },
});
