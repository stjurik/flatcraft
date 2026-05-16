import { drizzle, type PostgresJsDatabase } from "drizzle-orm/postgres-js";
import postgres, { type Sql } from "postgres";

import * as schema from "./schema.js";

export interface DatabaseClient {
  readonly db: PostgresJsDatabase<typeof schema>;
  readonly sql: Sql;
  readonly close: () => Promise<void>;
}

export interface CreateClientOptions {
  /** Override pool size; postgres-js default = 10. */
  readonly max?: number;
}

export function createClient(url?: string, options: CreateClientOptions = {}): DatabaseClient {
  const connectionString = url ?? process.env["DATABASE_URL"];
  if (!connectionString) {
    throw new Error("DATABASE_URL is not set. Pass it explicitly or define it in the environment.");
  }

  const sql = postgres(connectionString, {
    max: options.max ?? 10,
    // postgres-js створює з'єднання лазі — useful для unit-тестів без БД.
  });
  const db = drizzle(sql, { schema });

  return {
    db,
    sql,
    close: async () => {
      await sql.end({ timeout: 5 });
    },
  };
}
