/**
 * Fastify server factory.
 *
 * createServer(options?) повертає сконфігурований інстанс — без `listen()`,
 * щоб тести могли використовувати `app.inject()` без відкриття порту.
 * Реальний запуск (listen) — у main() нижче і у `start` npm-скрипті.
 */
import cors from "@fastify/cors";
import type { DatabaseClient } from "@flatcraft/db";
import Fastify, { type FastifyInstance, type FastifyServerOptions } from "fastify";
import {
  serializerCompiler,
  validatorCompiler,
  type ZodTypeProvider,
} from "fastify-type-provider-zod";

import { env } from "./env.js";
import { createLoggerOptions } from "./logger.js";
import { dbPlugin } from "./plugins/db.js";
import rateLimitPlugin from "./plugins/rate-limit.js";
import { buildExportRoutes } from "./routes/exports.js";
import type { JobStore } from "./lib/job-store.js";
import type { Telemetry } from "./lib/telemetry.js";
import { healthRoutes } from "./routes/health.js";
import { materialRoutes } from "./routes/materials.js";
import { productRoutes } from "./routes/products.js";
import { templateRoutes } from "./routes/templates.js";

export interface CreateServerOptions {
  readonly logger?: FastifyServerOptions["logger"];
  /** Override для тестів: інжектити готовий drizzle-клієнт (testcontainers). */
  readonly dbClient?: DatabaseClient;
  /** Override DATABASE_URL без зміни env. */
  readonly dbUrl?: string;
  /** Override job-store (тестам зручно інжектити власний). */
  readonly jobStore?: JobStore;
  /** Override телеметрії (unit-тести: NOOP/recording; дефолт — drizzle через app.db). */
  readonly telemetry?: Telemetry;
}

export async function createServer(options: CreateServerOptions = {}): Promise<FastifyInstance> {
  const app = Fastify({
    // Якщо тест передав logger:false — використовуємо його; інакше — pino з env.
    logger: options.logger ?? createLoggerOptions(env),
    // Безпечні дефолти: trust proxy лише у prod, де перед нами CF/Nginx.
    trustProxy: env.NODE_ENV === "production",
  }).withTypeProvider<ZodTypeProvider>();

  app.setValidatorCompiler(validatorCompiler);
  app.setSerializerCompiler(serializerCompiler);

  // CORS: web на localhost:3000 / APP_BASE_URL → api на :4000. Без цього
  // браузер блокує fetch до іншого origin. У prod APP_BASE_URL — реальний
  // домен.
  await app.register(cors, {
    origin: [env.APP_BASE_URL],
    methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
  });

  await app.register(dbPlugin, {
    ...(options.dbClient ? { client: options.dbClient } : {}),
    ...(options.dbUrl ? { url: options.dbUrl } : {}),
  });

  // Rate-limit (Phase X.1 A): глобальний 100/хв + per-route 30/год на /exports.
  // Реєструємо ДО маршрутів, щоб route-level `config.rateLimit` бачив плагін.
  await app.register(rateLimitPlugin);

  await app.register(healthRoutes);
  await app.register(templateRoutes);
  await app.register(productRoutes);
  await app.register(materialRoutes);
  await app.register(
    buildExportRoutes({
      ...(options.jobStore ? { store: options.jobStore } : {}),
      ...(options.telemetry ? { telemetry: options.telemetry } : {}),
    }),
  );

  return app;
}

// CLI entrypoint: `pnpm --filter @flatcraft/api dev` (tsx watch).
const isMain =
  import.meta.url === `file://${process.argv[1]}` ||
  process.argv[1]?.endsWith("/server.ts") === true ||
  process.argv[1]?.endsWith("/server.js") === true;

if (isMain) {
  const app = await createServer();
  try {
    await app.listen({ host: env.HOST, port: env.PORT });
  } catch (err) {
    app.log.error(err);
    process.exit(1);
  }
}
