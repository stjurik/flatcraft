/**
 * Телеметрія експортів (ADR-032 / docs/11_OBSERVABILITY.md).
 *
 * Пише події у таблицю `events` і персистить `exports` (замість in-memory
 * JobStore, який лишається лише pub/sub-шаром для SSE). **Best-effort:** жоден
 * метод НЕ кидає у гарячий шлях — телеметрія це сигнал, не критичний ресурс; збій
 * БД не має ламати експорт. Worker не має доступу до Postgres, тож усі події
 * (включно з `cad_*`) пише api.
 *
 * `NOOP_TELEMETRY` — для unit-тестів без БД (SSE-flow від телеметрії не залежить).
 */
import { schema, type DatabaseClient } from "@flatcraft/db";
import { toEventRow, type EventPayload } from "@flatcraft/types";
import { eq } from "drizzle-orm";
import type { FastifyBaseLogger } from "fastify";

type Db = DatabaseClient["db"];

export interface ExportInsert {
  readonly id: string;
  readonly templateSlug: string;
  readonly sessionHash: string | null;
  readonly formats: readonly string[];
}

export interface ExportCompletion {
  readonly status: "done" | "failed";
  readonly r2Keys?: Record<string, string> | null;
  readonly errorMessage?: string | null;
}

export interface Telemetry {
  writeEvent(payload: EventPayload): Promise<void>;
  insertExport(row: ExportInsert): Promise<void>;
  completeExport(id: string, patch: ExportCompletion): Promise<void>;
}

/** No-op телеметрія — unit-тести без БД. */
export const NOOP_TELEMETRY: Telemetry = {
  async writeEvent() {},
  async insertExport() {},
  async completeExport() {},
};

export function createTelemetry(db: Db, log?: FastifyBaseLogger): Telemetry {
  const swallow = (op: string, err: unknown): void => {
    // Best-effort: телеметрія не ламає експорт (ADR-032).
    log?.warn({ err, op }, "telemetry write failed (best-effort, ignored)");
  };

  return {
    async writeEvent(payload) {
      try {
        const row = toEventRow(payload); // валідує + assertNoPii (ADR-032 п.6)
        await db.insert(schema.events).values({
          eventType: row.event_type,
          templateSlug: row.template_slug,
          process: row.process,
          params: row.params,
          errorCode: row.error_code,
          durationMs: row.duration_ms,
          sessionHash: row.session_hash,
        });
      } catch (err) {
        swallow("writeEvent", err);
      }
    },

    async insertExport(row) {
      try {
        await db.insert(schema.exports).values({
          id: row.id,
          templateSlug: row.templateSlug,
          sessionHash: row.sessionHash,
          formats: [...row.formats],
          status: "queued",
        });
      } catch (err) {
        swallow("insertExport", err);
      }
    },

    async completeExport(id, patch) {
      try {
        await db
          .update(schema.exports)
          .set({
            status: patch.status,
            r2Keys: patch.r2Keys ?? null,
            errorMessage: patch.errorMessage ?? null,
            completedAt: new Date(),
          })
          .where(eq(schema.exports.id, id));
      } catch (err) {
        swallow("completeExport", err);
      }
    },
  };
}
