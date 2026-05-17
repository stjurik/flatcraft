/**
 * Тонкий API-клієнт для Fastify backend.
 *
 * - Server components викликають `API_BASE_URL` (server-side env).
 * - Client components (browser) — `NEXT_PUBLIC_API_BASE_URL` через
 *   `clientApiBaseUrl()`. Без NEXT_PUBLIC_ — браузер не побачить, бо
 *   Next.js не серіалізує не-PUBLIC env у клієнтський bundle.
 */
import {
  ExportRequestSchema,
  ExportResponseSchema,
  TemplateDetailSchema,
  TemplateListResponseSchema,
  type ExportRequest,
  type ExportResponse,
  type TemplateDetail,
  type TemplateSummary,
} from "@flatcraft/types";

const SERVER_API_BASE_URL = process.env["API_BASE_URL"] ?? "http://localhost:4000";

function clientApiBaseUrl(): string {
  // У client-component process.env обмежений; вибираємо NEXT_PUBLIC_ змінну.
  return process.env["NEXT_PUBLIC_API_BASE_URL"] ?? "http://localhost:4000";
}

export class ApiError extends Error {
  constructor(
    message: string,
    public readonly status: number,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

export async function fetchPublishedTemplates(): Promise<TemplateSummary[]> {
  const res = await fetch(`${SERVER_API_BASE_URL}/templates`, {
    cache: "no-store",
    headers: { Accept: "application/json" },
  });
  if (!res.ok) {
    throw new ApiError(`Failed to fetch /templates: ${res.status}`, res.status);
  }
  const json = await res.json();
  const parsed = TemplateListResponseSchema.parse(json);
  return parsed.items;
}

export async function fetchTemplate(slug: string): Promise<TemplateDetail | null> {
  const res = await fetch(`${SERVER_API_BASE_URL}/templates/${encodeURIComponent(slug)}`, {
    cache: "no-store",
    headers: { Accept: "application/json" },
  });
  if (res.status === 404) return null;
  if (!res.ok) {
    throw new ApiError(`Failed to fetch /templates/${slug}: ${res.status}`, res.status);
  }
  return TemplateDetailSchema.parse(await res.json());
}

/**
 * Створює експорт (sync flow Phase 2.7). Викликається з client component —
 * браузер шле POST до Fastify, який forward'ить на Python cad-worker.
 */
export async function createExport(request: ExportRequest): Promise<ExportResponse> {
  // Парсимо локально — додатковий захист від несподіванок з UI-сторони.
  const body = ExportRequestSchema.parse(request);
  const res = await fetch(`${clientApiBaseUrl()}/exports`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    throw new ApiError(`Failed to POST /exports: ${res.status}`, res.status);
  }
  return ExportResponseSchema.parse(await res.json());
}
