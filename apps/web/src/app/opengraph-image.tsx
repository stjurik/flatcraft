/**
 * Open Graph image для `https://hart.crimea.ua` (Phase 2.16.a).
 *
 * Next.js App Router convention: цей файл автоматично доступний за маршрутом
 * `/opengraph-image` і підключається у `<meta property="og:image">` для всіх
 * сторінок (`layout.tsx` — root metadata). Окрема прокидка у
 * `metadata.openGraph.images` не потрібна.
 *
 * Рендер винесено у `../lib/og-render.tsx` (Satori/font-boilerplate спільний
 * з EN-дзеркалом `app/en/opengraph-image.tsx`, ADR-037 §2) — тут лишається
 * тільки uk-текст.
 */
import { dictionaries } from "../i18n/dictionaries";
import { OG_SIZE, renderOgImage } from "../lib/og-render";

export const alt = dictionaries.uk.og.alt;

export const size = OG_SIZE;

export const contentType = "image/png";

export default async function OGImage() {
  return renderOgImage({ headline: dictionaries.uk.og.headline, sub: dictionaries.uk.og.sub });
}
