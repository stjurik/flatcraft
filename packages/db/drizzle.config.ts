import { defineConfig } from "drizzle-kit";

export default defineConfig({
  schema: "./src/schema.ts",
  out: "./src/migrations",
  dialect: "postgresql",
  dbCredentials: {
    url: process.env.DATABASE_URL ?? "postgresql://flatcraft:flatcraft_dev_only_change_me@localhost:5432/flatcraft",
  },
  strict: true,
  verbose: true,
});
