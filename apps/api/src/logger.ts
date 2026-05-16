/**
 * Pino-logger конфіг. CLAUDE.md §8 вимагає: жодних PII у логах
 * (email, password, auth headers, cookies).
 *
 * `createLoggerOptions` — pure-функція, повертає LoggerOptions для Fastify;
 * це дає легке юніт-тестування без instantiation pino.
 */
import type { LoggerOptions } from "pino";

import type { Env } from "./env.js";

const REDACT_PATHS: readonly string[] = [
  // Заголовки авторизації
  "req.headers.authorization",
  "req.headers.cookie",
  "req.headers['set-cookie']",
  "res.headers['set-cookie']",
  // Body / params / query — типові PII-ключі
  "req.body.email",
  "req.body.password",
  "req.body.passwordHash",
  "req.body.refreshToken",
  "req.query.email",
  // Загальні wildcards — на випадок вкладених DTO
  "*.password",
  "*.passwordHash",
  "*.refreshToken",
  "*.refresh_token",
];

export function createLoggerOptions(env: Pick<Env, "NODE_ENV" | "LOG_LEVEL">): LoggerOptions {
  const base: LoggerOptions = {
    level: env.LOG_LEVEL,
    redact: {
      paths: [...REDACT_PATHS],
      remove: true,
    },
  };

  if (env.NODE_ENV === "development") {
    return {
      ...base,
      transport: {
        target: "pino-pretty",
        options: {
          colorize: true,
          translateTime: "SYS:HH:MM:ss.l",
          ignore: "pid,hostname",
        },
      },
    };
  }

  return base;
}
