/**
 * Телеметрія подій платформи (ADR-032 / docs/11_OBSERVABILITY.md).
 *
 * Єдине джерело істини для payload'ів таблиці `events`, спільне для api (писар)
 * і майбутнього worker-репортингу. append-only, **БЕЗ PII** (інваріант ADR-032
 * п.6): жодного email/IP — лише геометрія виробу (`params`), тип події,
 * тривалість і непереслідуваний `session_hash` (добовий salt рахує api).
 *
 * `EventPayloadSchema` (discriminated union) — типобезпечний вхід; `toEventRow`
 * проєктує його у плоский рядок таблиці й дорогою прогонить `assertNoPii`.
 */
import { z } from "zod";

export const EVENT_TYPES = [
  "export_requested",
  "validation_rejected",
  "export_completed",
  "export_failed",
  "cad_started",
  "cad_completed",
  "web_vital",
  "feedback_submitted",
] as const;

export const EventTypeSchema = z.enum(EVENT_TYPES);
export type EventType = z.infer<typeof EventTypeSchema>;

/** Виробничий процес (майбутній process-layer, docs/14 §3). MVP — константа. */
export const DEFAULT_PROCESS = "sheet_metal";

/**
 * Ключі, яких `params` НЕ сміє містити (GDPR, ADR-032 п.6). Enforcement —
 * `assertNoPii` (writer) + no-PII тести. Розширювати за потреби.
 */
export const PII_FORBIDDEN_KEYS = [
  "email",
  "ip",
  "ip_address",
  "ipaddress",
  "password",
  "password_hash",
  "authorization",
  "cookie",
  "refresh_token",
  "phone",
  "display_name",
] as const;

/** Знімок параметрів виробу — довільний JSON геометрії (перевіряється на no-PII). */
const GeometryParamsSchema = z.record(z.unknown());

const baseShape = {
  template_slug: z.string().nullable(),
  process: z.string().default(DEFAULT_PROCESS),
  session_hash: z.string().nullable(),
};

export const EventPayloadSchema = z.discriminatedUnion("event_type", [
  z.object({
    event_type: z.literal("export_requested"),
    params: GeometryParamsSchema,
    ...baseShape,
  }),
  z.object({
    event_type: z.literal("validation_rejected"),
    params: GeometryParamsSchema,
    error_code: z.string(),
    ...baseShape,
  }),
  z.object({
    event_type: z.literal("export_completed"),
    duration_ms: z.number().int().nonnegative(),
    ...baseShape,
  }),
  z.object({
    event_type: z.literal("export_failed"),
    error_code: z.string(),
    duration_ms: z.number().int().nonnegative().nullable(),
    ...baseShape,
  }),
  z.object({
    event_type: z.literal("cad_started"),
    ...baseShape,
  }),
  z.object({
    event_type: z.literal("cad_completed"),
    duration_ms: z.number().int().nonnegative(),
    ...baseShape,
  }),
  z.object({
    event_type: z.literal("web_vital"),
    params: z.object({
      metric: z.enum(["FCP", "TTI", "mesh_update"]),
      value_ms: z.number().nonnegative(),
    }),
    ...baseShape,
  }),
  // Виробничий фідбек з /f/{export_id} (Phase 3.4, R-01 mitigation 4).
  // params містить agregat (outcome + чи є deviation) — БЕЗ вмісту коментаря
  // і БЕЗ export_id (це деталі, які живуть у `export_feedback` таблиці).
  // Мета події — digest бачить розподіл outcome і deviation-rate по шаблонах.
  z.object({
    event_type: z.literal("feedback_submitted"),
    params: z.object({
      outcome: z.enum(["made", "deviations", "failed"]),
      has_deviation_description: z.boolean(),
      has_comment: z.boolean(),
      locale: z.enum(["uk", "en"]),
    }),
    ...baseShape,
  }),
]);
export type EventPayload = z.infer<typeof EventPayloadSchema>;

/** Плоский рядок таблиці `events` (проєкція payload'а у колонки). */
export interface EventRow {
  event_type: EventType;
  template_slug: string | null;
  process: string;
  params: Record<string, unknown> | null;
  error_code: string | null;
  duration_ms: number | null;
  session_hash: string | null;
}

/**
 * Кидає, якщо у `params` (рекурсивно) є заборонений PII-ключ. Остання лінія
 * оборони інваріанта «no-PII у телеметрії» (ADR-032 п.6) — паритет pino-redact.
 */
export function assertNoPii(params: Record<string, unknown> | null | undefined): void {
  if (!params) return;
  const forbidden = new Set<string>(PII_FORBIDDEN_KEYS);
  const walk = (value: unknown): void => {
    if (Array.isArray(value)) {
      value.forEach(walk);
      return;
    }
    if (value && typeof value === "object") {
      for (const [key, nested] of Object.entries(value)) {
        if (forbidden.has(key.toLowerCase())) {
          throw new Error(`PII-ключ заборонений у event.params: "${key}" (ADR-032 п.6)`);
        }
        walk(nested);
      }
    }
  };
  walk(params);
}

/** Проєктує валідований payload у плоский рядок `events` (+ no-PII guard). */
export function toEventRow(payload: EventPayload): EventRow {
  const parsed = EventPayloadSchema.parse(payload);
  const rec = parsed as Record<string, unknown>;
  const params = (rec["params"] as Record<string, unknown> | undefined) ?? null;
  assertNoPii(params);
  return {
    event_type: parsed.event_type,
    template_slug: parsed.template_slug,
    process: parsed.process,
    params,
    error_code: (rec["error_code"] as string | undefined) ?? null,
    duration_ms: (rec["duration_ms"] as number | null | undefined) ?? null,
    session_hash: parsed.session_hash,
  };
}
