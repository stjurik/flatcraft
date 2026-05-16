/**
 * Тонкий API-клієнт для Fastify backend.
 *
 * Викликається переважно з server components — тому базовий URL береться
 * з `API_BASE_URL` (server-side env), не з NEXT_PUBLIC_*.
 */
import { TemplateListResponseSchema, type TemplateSummary } from "@flatcraft/types";

const API_BASE_URL = process.env["API_BASE_URL"] ?? "http://localhost:4000";

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
  const res = await fetch(`${API_BASE_URL}/templates`, {
    // Кожне завантаження сторінки — свіжий запит. Кешем буде Cloudflare/CDN.
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
