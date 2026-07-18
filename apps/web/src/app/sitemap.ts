import type { MetadataRoute } from "next";

import { toEnPath } from "../i18n/routes";
import { fetchPublishedProducts, fetchPublishedTemplates } from "../lib/api";
import { SITE_URL } from "../lib/site-url";

/**
 * `app/sitemap.ts` (Next.js App Router convention) — ADR-037 §7 follow-up.
 * Кожна локалізована пара (uk-шлях + `/en/*`-дзеркало) дає ДВА sitemap-записи
 * (по одному на URL), обидва з однаковим реципрокним `alternates.languages`
 * — так Google бачить hreflang-зв'язок з боку sitemap, а не лише з
 * `<link>`-тегів сторінки (доповнення, не заміна).
 *
 * `/f/[exportId]` навмисно ВІДСУТНІЙ — приватна noindex-сторінка
 * (QR-посилання з PDF, ADR-032 §feedback), не публічний контент.
 */
function absoluteUrl(path: string): string {
  return `${SITE_URL}${path}`;
}

function localizedPair(ukPath: string, enPath: string, priority: number): MetadataRoute.Sitemap {
  const languages = { uk: absoluteUrl(ukPath), en: absoluteUrl(enPath) };
  const shared = {
    changeFrequency: "monthly" as const,
    priority,
    alternates: { languages },
  };
  return [
    { url: absoluteUrl(ukPath), ...shared },
    { url: absoluteUrl(enPath), ...shared },
  ];
}

function mirroredPair(ukPath: string, priority: number): MetadataRoute.Sitemap {
  return localizedPair(ukPath, toEnPath(ukPath), priority);
}

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const [templates, products] = await Promise.all([
    fetchPublishedTemplates().catch(() => []),
    fetchPublishedProducts().catch(() => []),
  ]);

  return [
    ...mirroredPair("/", 1.0),
    ...mirroredPair("/templates", 0.8),
    ...mirroredPair("/about", 0.5),
    ...mirroredPair("/soon", 0.3),
    ...templates.flatMap((t) => mirroredPair(`/templates/${t.slug}`, 0.6)),
    ...products.flatMap((p) => mirroredPair(`/products/${p.slug}`, 0.6)),
    ...localizedPair("/privacy", "/privacy/en", 0.2),
    ...localizedPair("/terms", "/terms/en", 0.2),
  ];
}
