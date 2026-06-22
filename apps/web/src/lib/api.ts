/**
 * Тонкий API-клієнт для Fastify backend.
 *
 * - Server components викликають `API_BASE_URL` (server-side env).
 * - Client components (browser) — `NEXT_PUBLIC_API_BASE_URL` через
 *   `clientApiBaseUrl()`. Без NEXT_PUBLIC_ — браузер не побачить, бо
 *   Next.js не серіалізує не-PUBLIC env у клієнтський bundle.
 */
import {
  ExportJobAcceptedSchema,
  ExportJobEventSchema,
  ExportRequestSchema,
  MaterialListResponseSchema,
  ProductListResponseSchema,
  TemplateDetailSchema,
  TemplateListResponseSchema,
  type ExportJobAccepted,
  type ExportJobEvent,
  type ExportRequest,
  type MaterialChoice,
  type ProductSummary,
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

/**
 * Phase 3.0 PR 3: каталог-toggle. Server-side fetch перед рендером
 * `/templates?tab=products`. Якщо API повертає 404/500 — кидаємо ApiError,
 * сторінка показує банер «не вдалося завантажити» (як для templates).
 */
export async function fetchPublishedProducts(): Promise<ProductSummary[]> {
  const res = await fetch(`${SERVER_API_BASE_URL}/products`, {
    cache: "no-store",
    headers: { Accept: "application/json" },
  });
  if (!res.ok) {
    throw new ApiError(`Failed to fetch /products: ${res.status}`, res.status);
  }
  const json = await res.json();
  const parsed = ProductListResponseSchema.parse(json);
  return parsed.items;
}

export async function fetchMaterials(): Promise<MaterialChoice[]> {
  const res = await fetch(`${SERVER_API_BASE_URL}/materials`, {
    cache: "no-store",
    headers: { Accept: "application/json" },
  });
  if (!res.ok) {
    throw new ApiError(`Failed to fetch /materials: ${res.status}`, res.status);
  }
  return MaterialListResponseSchema.parse(await res.json()).items;
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
 * Створює async export-job (Phase 2.8). Повертає лише jobId; реальний
 * результат приходить через subscribeExportEvents().
 */
export async function createExport(request: ExportRequest): Promise<ExportJobAccepted> {
  const body = ExportRequestSchema.parse(request);
  const res = await fetch(`${clientApiBaseUrl()}/exports`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    // Hotfix 2.9.c (C): сервер віддає RFC 9457 problem details з дружнім
    // `detail` (напр. «Збільшіть радіус…»). Дістаємо його замість generic
    // «Failed to POST», щоб UI показав конкретну причину 422.
    throw new ApiError(await problemMessage(res), res.status);
  }
  return ExportJobAcceptedSchema.parse(await res.json());
}

/**
 * Витягує людиночитане повідомлення з RFC 9457 problem-details тіла.
 * Пріоритет: `detail` → перший `errors[].message` → generic зі статусом.
 * Безпечно ковтає не-JSON тіло (повертає generic).
 */
async function problemMessage(res: Response): Promise<string> {
  const generic = `Запит відхилено (${res.status}).`;
  try {
    const problem: unknown = await res.json();
    if (problem && typeof problem === "object") {
      const p = problem as { detail?: unknown; errors?: unknown };
      if (typeof p.detail === "string" && p.detail.length > 0) return p.detail;
      if (Array.isArray(p.errors)) {
        const first = p.errors.find(
          (e): e is { message: string } =>
            !!e && typeof (e as { message?: unknown }).message === "string",
        );
        if (first) return first.message;
      }
    }
    return generic;
  } catch {
    return generic;
  }
}

/**
 * Підписка на прогрес експорту через Server-Sent Events.
 * Повертає функцію `close()` — викликати на unmount або після final event.
 */
export function subscribeExportEvents(
  jobId: string,
  onEvent: (event: ExportJobEvent) => void,
  onError?: (err: Error) => void,
): () => void {
  const url = `${clientApiBaseUrl()}/exports/${encodeURIComponent(jobId)}/events`;
  const source = new EventSource(url);

  source.onmessage = (msg) => {
    try {
      const parsed = ExportJobEventSchema.parse(JSON.parse(msg.data as string));
      onEvent(parsed);
      if (parsed.status === "done" || parsed.status === "failed") {
        source.close();
      }
    } catch (err) {
      onError?.(err instanceof Error ? err : new Error(String(err)));
      source.close();
    }
  };

  source.onerror = () => {
    if (source.readyState === EventSource.CLOSED) return;
    onError?.(new Error("SSE connection failed"));
    source.close();
  };

  return () => source.close();
}
