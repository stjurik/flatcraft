/**
 * Fastify server factory.
 *
 * createServer(options?) повертає сконфігурований інстанс — без `listen()`,
 * щоб тести могли використовувати `app.inject()` без відкриття порту.
 * Реальний запуск (listen) — у main() нижче і у `start` npm-скрипті.
 */
import Fastify, { type FastifyInstance, type FastifyServerOptions } from "fastify";
import {
  serializerCompiler,
  validatorCompiler,
  type ZodTypeProvider,
} from "fastify-type-provider-zod";

import { env } from "./env.js";
import { createLoggerOptions } from "./logger.js";
import { healthRoutes } from "./routes/health.js";

export type CreateServerOptions = Pick<FastifyServerOptions, "logger">;

export async function createServer(options: CreateServerOptions = {}): Promise<FastifyInstance> {
  const app = Fastify({
    // Якщо тест передав logger:false — використовуємо його; інакше — pino з env.
    logger: options.logger ?? createLoggerOptions(env),
    // Безпечні дефолти: trust proxy лише у prod, де перед нами CF/Nginx.
    trustProxy: env.NODE_ENV === "production",
  }).withTypeProvider<ZodTypeProvider>();

  app.setValidatorCompiler(validatorCompiler);
  app.setSerializerCompiler(serializerCompiler);

  await app.register(healthRoutes);

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
