/**
 * Щотижневий digest → Discord webhook (ADR-032 / docs/11 §9).
 *
 * Тонкий раннер (ядро `buildDigest` тестоване окремо): SQL за 7 днів по `events`
 * → `buildDigest` → POST у Discord (`DIGEST_WEBHOOK_URL`; звичайний webhook-POST,
 * **НЕ** `discord:apply` — ADR-023 дозволяє). Без URL — dry-run (друк markdown).
 *
 * Запуск: `pnpm --filter @flatcraft/api digest`. Cron (неділя 18:00 Europe/Kyiv) —
 * wiring через Ansible, поза цим модулем.
 */
import { createClient, schema, type DatabaseClient } from "@flatcraft/db";
import { and, desc, eq, gte, sql } from "drizzle-orm";

import { buildDigest, chunkForDiscord, type DigestData, type DurationRow } from "../lib/digest.js";

type Db = DatabaseClient["db"];

const WEEK_MS = 7 * 24 * 60 * 60 * 1000;
const EXPORT_BUDGET_MS = 5000; // §9: PDF <5c (один export робить DXF+PDF разом)

function isoDate(d: Date): string {
  return d.toISOString().slice(0, 10);
}

async function p95(db: Db, eventType: string, since: Date): Promise<number | null> {
  const [row] = await db
    .select({
      p95: sql<
        number | null
      >`percentile_cont(0.95) within group (order by ${schema.events.durationMs})`,
    })
    .from(schema.events)
    .where(
      and(
        eq(schema.events.eventType, eventType),
        gte(schema.events.ts, since),
        sql`${schema.events.durationMs} is not null`,
      ),
    );
  return row?.p95 ?? null;
}

async function collectDigestData(db: Db, now: Date = new Date()): Promise<DigestData> {
  const since = new Date(now.getTime() - WEEK_MS);

  const validationErrors = await db
    .select({
      errorCode: schema.events.errorCode,
      count: sql<number>`(count(*))::int`,
      templates: sql<
        string[]
      >`array_remove(array_agg(distinct ${schema.events.templateSlug}), null)`,
    })
    .from(schema.events)
    .where(and(eq(schema.events.eventType, "validation_rejected"), gte(schema.events.ts, since)))
    .groupBy(schema.events.errorCode)
    .orderBy(desc(sql`count(*)`))
    .limit(5);

  const failedExports = await db
    .select({
      templateSlug: schema.events.templateSlug,
      errorCode: schema.events.errorCode,
      count: sql<number>`(count(*))::int`,
      exampleTs: sql<string>`min(${schema.events.ts})::text`,
    })
    .from(schema.events)
    .where(and(eq(schema.events.eventType, "export_failed"), gte(schema.events.ts, since)))
    .groupBy(schema.events.templateSlug, schema.events.errorCode)
    .orderBy(desc(sql`count(*)`));

  const durations: DurationRow[] = [
    {
      stage: "export (повний, DXF+PDF)",
      p95Ms: await p95(db, "export_completed", since),
      budgetMs: EXPORT_BUDGET_MS,
    },
    {
      stage: "cad (worker round-trip)",
      p95Ms: await p95(db, "cad_completed", since),
      budgetMs: EXPORT_BUDGET_MS,
    },
  ];

  const [vol] = await db
    .select({
      uniqueSessions: sql<number>`(count(distinct ${schema.events.sessionHash}) filter (where ${schema.events.eventType} = 'export_requested'))::int`,
      exportsDone: sql<number>`(count(*) filter (where ${schema.events.eventType} = 'export_completed'))::int`,
      exportsFailed: sql<number>`(count(*) filter (where ${schema.events.eventType} = 'export_failed'))::int`,
      validationRejections: sql<number>`(count(*) filter (where ${schema.events.eventType} = 'validation_rejected'))::int`,
    })
    .from(schema.events)
    .where(gte(schema.events.ts, since));

  return {
    periodStart: isoDate(since),
    periodEnd: isoDate(now),
    validationErrors: validationErrors.map((v) => ({
      errorCode: v.errorCode ?? "UNKNOWN",
      count: v.count,
      templates: v.templates ?? [],
    })),
    failedExports: failedExports.map((f) => ({
      templateSlug: f.templateSlug,
      errorCode: f.errorCode,
      count: f.count,
      exampleTs: f.exampleTs,
    })),
    durations,
    feedback: [], // Phase 3.4 (немає export_feedback)
    sentry: [], // плейсхолдер (нема Sentry-API-токена)
    volume: {
      uniqueSessions: vol?.uniqueSessions ?? 0,
      exportsDone: vol?.exportsDone ?? 0,
      exportsFailed: vol?.exportsFailed ?? 0,
      validationRejections: vol?.validationRejections ?? 0,
    },
  };
}

async function postToDiscord(webhookUrl: string, markdown: string): Promise<void> {
  for (const content of chunkForDiscord(markdown)) {
    const res = await fetch(webhookUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ content }),
    });
    if (!res.ok) {
      const detail = (await res.text().catch(() => "")).slice(0, 200);
      throw new Error(`Discord webhook ${res.status}: ${detail}`);
    }
  }
}

async function main(): Promise<void> {
  const databaseUrl = process.env["DATABASE_URL"];
  if (!databaseUrl) {
    console.error("DATABASE_URL обов'язковий для weekly-digest");
    process.exit(1);
  }
  const client = createClient(databaseUrl);
  try {
    const markdown = buildDigest(await collectDigestData(client.db));
    const webhook = process.env["DIGEST_WEBHOOK_URL"];
    if (!webhook) {
      console.info("[dry-run] DIGEST_WEBHOOK_URL не задано — markdown нижче:\n");
      console.info(markdown);
      return;
    }
    await postToDiscord(webhook, markdown);
    console.info("digest надіслано у Discord");
  } finally {
    await client.close();
  }
}

void main().catch((err: unknown) => {
  console.error(err);
  process.exit(1);
});
