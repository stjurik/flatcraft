/**
 * Щотижневий digest телеметрії (ADR-032 / docs/11 §9).
 *
 * `buildDigest` — **pure**: агреговані дані → markdown (формат docs/11 §9). Збір
 * даних (SQL) і доставка (Discord webhook) — тонкий шар у
 * `scripts/weekly-digest.ts`. `chunkForDiscord` ріже під ліміт повідомлення
 * Discord (2000 символів).
 */

export interface ValidationErrorRow {
  readonly errorCode: string;
  readonly count: number;
  readonly templates: readonly string[];
}

export interface FailedExportRow {
  readonly templateSlug: string | null;
  readonly errorCode: string | null;
  readonly count: number;
  readonly exampleTs: string;
}

export interface DurationRow {
  readonly stage: string;
  readonly p95Ms: number | null;
  readonly budgetMs: number;
}

export interface FeedbackRow {
  readonly exportId: string;
  readonly outcome: string;
  readonly deviationMm: number | null;
  readonly comment: string;
}

export interface SentryIssueRow {
  readonly title: string;
  readonly events: number;
  readonly firstSeen: string;
}

export interface DigestVolume {
  readonly uniqueSessions: number;
  readonly exportsDone: number;
  readonly exportsFailed: number;
  readonly validationRejections: number;
}

export interface DigestData {
  readonly periodStart: string;
  readonly periodEnd: string;
  readonly validationErrors: readonly ValidationErrorRow[];
  readonly failedExports: readonly FailedExportRow[];
  readonly durations: readonly DurationRow[];
  /** Порожньо до Phase 3.4 (немає `export_feedback`). */
  readonly feedback: readonly FeedbackRow[];
  /** Порожньо до інтеграції Sentry-API (плейсхолдер). */
  readonly sentry: readonly SentryIssueRow[];
  readonly volume: DigestVolume;
}

const EMPTY = "_(порожньо)_";
const DISCORD_LIMIT = 2000;

function mdTable(headers: readonly string[], rows: readonly (readonly string[])[]): string {
  const head = `| ${headers.join(" | ")} |`;
  const sep = `| ${headers.map(() => "---").join(" | ")} |`;
  const body = rows.map((r) => `| ${r.join(" | ")} |`).join("\n");
  return `${head}\n${sep}\n${body}`;
}

function fmtMs(ms: number | null): string {
  return ms === null ? "—" : `${(ms / 1000).toFixed(2)} c`;
}

export function buildDigest(data: DigestData): string {
  const lines: string[] = [
    `# hart · щотижневий digest (${data.periodStart} … ${data.periodEnd})`,
    "",
  ];

  lines.push("## 1. Top-5 validation errors (по constraint)");
  lines.push(
    data.validationErrors.length === 0
      ? EMPTY
      : mdTable(
          ["constraint (error_code)", "к-сть", "шаблон(и)"],
          data.validationErrors.map((v) => [
            v.errorCode,
            String(v.count),
            v.templates.join(", ") || "—",
          ]),
        ),
    "",
  );

  lines.push("## 2. Failed exports");
  lines.push(
    data.failedExports.length === 0
      ? EMPTY
      : mdTable(
          ["template", "error_code", "к-сть", "приклад ts"],
          data.failedExports.map((f) => [
            f.templateSlug ?? "—",
            f.errorCode ?? "—",
            String(f.count),
            f.exampleTs,
          ]),
        ),
    "",
  );

  lines.push("## 3. Тривалості (p95 vs бюджет §9)");
  lines.push(
    data.durations.length === 0
      ? EMPTY
      : mdTable(
          ["етап", "p95", "бюджет", "статус"],
          data.durations.map((d) => [
            d.stage,
            fmtMs(d.p95Ms),
            fmtMs(d.budgetMs),
            d.p95Ms === null ? "—" : d.p95Ms <= d.budgetMs ? "✅" : "⚠️",
          ]),
        ),
    "",
  );

  lines.push("## 4. Виробничий фідбек (Phase 3.4+)");
  lines.push(
    data.feedback.length === 0
      ? EMPTY
      : mdTable(
          ["export_id", "outcome", "deviation_mm", "коментар"],
          data.feedback.map((f) => [
            f.exportId,
            f.outcome,
            f.deviationMm === null ? "—" : String(f.deviationMm),
            f.comment || "—",
          ]),
        ),
    "",
  );

  lines.push("## 5. Sentry summary");
  lines.push(
    data.sentry.length === 0
      ? EMPTY
      : mdTable(
          ["issue", "events", "перший раз"],
          data.sentry.map((s) => [s.title, String(s.events), s.firstSeen]),
        ),
    "",
  );

  lines.push("## 6. Обсяг");
  const total = data.volume.exportsDone + data.volume.exportsFailed;
  lines.push(
    `унікальних сесій: ${data.volume.uniqueSessions} · експортів: ${total} ` +
      `(${data.volume.exportsDone} done / ${data.volume.exportsFailed} failed) · ` +
      `відхилень валідації: ${data.volume.validationRejections}`,
    "",
    "_Правило: кожен пункт → GitHub-issue або явно «accepted noise» (ADR-032)._",
  );

  return lines.join("\n");
}

/** Ріже markdown на шматки ≤ `limit` символів по межах рядків (ліміт Discord). */
export function chunkForDiscord(markdown: string, limit: number = DISCORD_LIMIT): string[] {
  if (markdown.length <= limit) return [markdown];
  const chunks: string[] = [];
  let current = "";
  const flush = (): void => {
    if (current) chunks.push(current);
    current = "";
  };
  for (const line of markdown.split("\n")) {
    if (line.length > limit) {
      // Рідкісний випадок: один рядок довший за ліміт — жорстко ріжемо.
      flush();
      for (let i = 0; i < line.length; i += limit) chunks.push(line.slice(i, i + limit));
      continue;
    }
    if (current.length + line.length + 1 > limit) flush();
    current = current ? `${current}\n${line}` : line;
  }
  flush();
  return chunks;
}
