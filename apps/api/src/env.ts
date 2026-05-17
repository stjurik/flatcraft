/**
 * Валідація environment-змінних на старті процесу.
 * Кидає на найпершому виклику, якщо щось не так — застосунок не стартує
 * з частково-сконфігурованим станом (CLAUDE.md §8: валідація лише через Zod).
 */
import { z } from "zod";

const LOG_LEVELS = ["fatal", "error", "warn", "info", "debug", "trace"] as const;

const EnvSchema = z.object({
  NODE_ENV: z.enum(["development", "production", "test"]).default("development"),
  HOST: z.string().min(1).default("0.0.0.0"),
  PORT: z.coerce.number().int().positive().max(65535).default(4000),
  LOG_LEVEL: z.enum(LOG_LEVELS).optional(),
  APP_BASE_URL: z.string().url().default("http://localhost:3000"),
  CAD_WORKER_URL: z.string().url().default("http://localhost:5000"),
});

export type Env = z.infer<typeof EnvSchema> & { LOG_LEVEL: (typeof LOG_LEVELS)[number] };

export function parseEnv(source: Record<string, string | undefined>): Env {
  const parsed = EnvSchema.parse(source);
  // LOG_LEVEL дефолтиться залежно від NODE_ENV — у dev verbose, у prod коротко.
  const logLevel = parsed.LOG_LEVEL ?? (parsed.NODE_ENV === "production" ? "info" : "debug");
  return { ...parsed, LOG_LEVEL: logLevel };
}

export const env: Env = parseEnv(process.env);
