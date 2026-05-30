import { defineConfig, devices } from "@playwright/test";

const WEB_PORT = 3000;
const API_PORT = 4000;

export default defineConfig({
  testDir: "./tests/e2e",
  fullyParallel: true,
  forbidOnly: !!process.env["CI"],
  retries: process.env["CI"] ? 2 : 0,
  reporter: process.env["CI"] ? "github" : "list",
  use: {
    baseURL: `http://localhost:${WEB_PORT}`,
    trace: "on-first-retry",
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],
  // Підіймаємо обидва сервери: API (Fastify, dev mode — tsx watch) і web
  // (prod-build для детермінованих dynamic-chunks). DATABASE_URL передаємо
  // через env у webServer.env — локально працює з docker compose.
  webServer: [
    {
      command: "pnpm --filter @flatcraft/api dev",
      url: `http://localhost:${API_PORT}/health`,
      reuseExistingServer: !process.env["CI"],
      timeout: 60_000,
      env: {
        DATABASE_URL:
          process.env["DATABASE_URL"] ??
          "postgresql://flatcraft:flatcraft_dev_only_change_me@localhost:5432/flatcraft",
      },
    },
    {
      // Prod-build детерміновано вантажить bundle одразу — dev-сервер компілює
      // dynamic-chunks on-demand, що ламає першу e2e-перевірку Canvas.
      command: "pnpm build && pnpm start",
      url: `http://localhost:${WEB_PORT}`,
      reuseExistingServer: !process.env["CI"],
      // Cold next-build з шрифтами (next/font fetch) і dynamic-chunks
      // часом тягнеться 2–3 хв; 4 хв — комфортна стеля.
      timeout: 240_000,
      env: {
        API_BASE_URL: `http://localhost:${API_PORT}`,
        // /styleguide доступна лише у dev-buildі (Phase 2.11).
        NEXT_PUBLIC_ENV: "dev",
      },
    },
  ],
});
