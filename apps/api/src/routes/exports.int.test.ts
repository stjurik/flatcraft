/**
 * Інтеграційний тест персисту телеметрії (ADR-032, Phase 3.3 PR 2) — проти
 * реальної Postgres. Гейт `DATABASE_URL` (локально docker compose, CI postgres
 * service), як інші *.int.test.ts.
 *
 * ⚠️ ПОТРЕБУЄ МІГРАЦІЇ: `events` + нові колонки `exports` існують лише після
 * `pnpm --filter @flatcraft/db generate` + apply (створює yurii вручну, CLAUDE.md
 * §6). До міграції `runMigrations` не створить `events` → тест RED. Це свідома
 * стоп-точка PR 2.
 *
 * cad-worker fetch замоканий — тестуємо саме шлях api→Postgres (persist exports +
 * append events), не воркер.
 */
import { createClient, runMigrations, schema, type DatabaseClient } from "@flatcraft/db";
import { eq } from "drizzle-orm";
import type { FastifyInstance } from "fastify";
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";

import { JobStore } from "../lib/job-store.js";
import { createServer } from "../server.js";

const DATABASE_URL = process.env["DATABASE_URL"];

const VALID_REQUEST = {
  template_slug: "l_bracket" as const,
  parameters: {
    legA_mm: 60,
    legB_mm: 60,
    bend_radius_mm: 2.5,
    bend_angle_deg: 90,
    width_mm: 100,
    holes: [],
  },
  material_code: "cold_rolled_steel",
  thickness_mm: 2,
};

const UPSTREAM_OK_BODY = {
  artifacts: {
    dxf: {
      url: "https://flatcraft.s3.amazonaws.com/key.dxf?X=1",
      bytes: 16384,
      expires_at: "2026-07-05T00:00:00.000Z",
      s3_key: "exports/2026/07/05/abc_l_bracket.dxf",
    },
    pdf: {
      url: "https://flatcraft.s3.amazonaws.com/key.pdf?X=1",
      bytes: 8192,
      expires_at: "2026-07-05T00:00:00.000Z",
      s3_key: "exports/2026/07/05/abc_l_bracket.pdf",
    },
  },
};

async function waitFor<T>(fn: () => Promise<T | null>, timeoutMs = 5000): Promise<T> {
  const start = Date.now();
  for (;;) {
    const value = await fn();
    if (value) return value;
    if (Date.now() - start > timeoutMs) throw new Error("waitFor timeout");
    await new Promise((r) => setTimeout(r, 50));
  }
}

describe.skipIf(!DATABASE_URL)("exports персист телеметрії — integration (ADR-032)", () => {
  let app: FastifyInstance;
  let client: DatabaseClient;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let fetchSpy: any;

  beforeAll(async () => {
    if (!DATABASE_URL) throw new Error("DATABASE_URL required");
    await runMigrations({ url: DATABASE_URL });
    client = createClient(DATABASE_URL);
    // Без telemetry-override → реальна drizzle-телеметрія через app.db.
    app = await createServer({
      logger: false,
      dbClient: client,
      jobStore: new JobStore({ retentionMs: 60_000 }),
    });
  }, 30_000);

  afterAll(async () => {
    await app?.close();
    await client?.close();
  });

  beforeEach(() => {
    fetchSpy = vi.spyOn(globalThis, "fetch");
  });

  afterEach(async () => {
    fetchSpy.mockRestore();
    // events/exports не мають seed-рядків → безпечно чистимо між тестами.
    if (client) {
      await client.db.delete(schema.events);
      await client.db.delete(schema.exports);
    }
  });

  it("успішний експорт → exports(done) + 4 події events, без PII", async () => {
    fetchSpy.mockResolvedValue(
      new Response(JSON.stringify(UPSTREAM_OK_BODY), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );

    const res = await app.inject({ method: "POST", url: "/exports", payload: VALID_REQUEST });
    expect(res.statusCode).toBe(202);
    const { id } = res.json<{ id: string }>();

    // export_completed — остання подія runJob'а; дочекаймося її.
    await waitFor(async () => {
      const rows = await client.db
        .select()
        .from(schema.events)
        .where(eq(schema.events.eventType, "export_completed"));
      return rows.length > 0 ? rows : null;
    });

    const exportRows = await client.db.select().from(schema.exports);
    expect(exportRows).toHaveLength(1);
    expect(exportRows[0]).toMatchObject({
      id,
      templateSlug: "l_bracket",
      process: "sheet_metal",
      status: "done",
    });
    expect(exportRows[0]?.userId).toBeNull(); // soft-launch: без auth
    expect(exportRows[0]?.r2Keys).toMatchObject({
      dxf: expect.stringContaining(".dxf"),
      pdf: expect.stringContaining(".pdf"),
    });

    const eventRows = await client.db.select().from(schema.events);
    const types = eventRows.map((r) => r.eventType).sort();
    expect(types).toEqual(["cad_completed", "cad_started", "export_completed", "export_requested"]);
    // duration_ms заповнено для cad_completed/export_completed.
    const completed = eventRows.find((r) => r.eventType === "export_completed");
    expect(typeof completed?.durationMs).toBe("number");

    // No-PII інваріант: жодна колонка рядка не несе email/IP.
    for (const row of eventRows) {
      const serialized = JSON.stringify(row);
      expect(serialized).not.toMatch(/email|"ip"|password/i);
    }
  });

  it("невалідний радіус → validation_rejected, жодного рядка exports", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/exports",
      payload: {
        template_slug: "z_bracket",
        parameters: {
          top_flange_mm: 60,
          bottom_flange_mm: 60,
          offset_mm: 40,
          bend_radius_mm: 2.5,
          bend_angle_deg: 90,
          width_mm: 100,
          holes: [],
        },
        material_code: "cold_rolled_steel",
        thickness_mm: 5,
      },
    });
    expect(res.statusCode).toBe(422);
    expect(fetchSpy).not.toHaveBeenCalled();

    const eventRows = await client.db.select().from(schema.events);
    expect(eventRows).toHaveLength(1);
    expect(eventRows[0]).toMatchObject({
      eventType: "validation_rejected",
      templateSlug: "z_bracket",
      errorCode: "RADIUS_NOT_ALLOWED",
    });
    const exportRows = await client.db.select().from(schema.exports);
    expect(exportRows).toHaveLength(0);
  });
});
