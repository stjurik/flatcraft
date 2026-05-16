/**
 * Fastify plugin: декорує `app.db` — drizzle-інстанс із @flatcraft/db.
 *
 * Один пул per process; закривається у `onClose`. Якщо `existingDb`
 * передано (інтеграційні тести з testcontainers) — використовуємо його,
 * не створюючи новий пул.
 */
import { createClient, type DatabaseClient } from "@flatcraft/db";
import fp from "fastify-plugin";

declare module "fastify" {
  interface FastifyInstance {
    db: DatabaseClient["db"];
  }
}

export interface DbPluginOptions {
  readonly url?: string;
  /** Override для тестів: передати готовий клієнт замість створення нового. */
  readonly client?: DatabaseClient;
}

export const dbPlugin = fp<DbPluginOptions>(
  async (app, opts) => {
    const client = opts.client ?? createClient(opts.url);
    app.decorate("db", client.db);

    app.addHook("onClose", async () => {
      if (!opts.client) {
        // Тільки якщо ми створили клієнт самі — ми ж його і закриваємо.
        await client.close();
      }
    });
  },
  { name: "db" },
);
