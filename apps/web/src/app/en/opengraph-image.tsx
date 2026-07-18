/**
 * EN-дзеркало `/opengraph-image` (ADR-037 §2). Спільний рендер —
 * `../../lib/og-render.tsx`; див. `app/opengraph-image.tsx` для дизайну.
 */
import { dictionaries } from "../../i18n/dictionaries";
import { OG_SIZE, renderOgImage } from "../../lib/og-render";

export const alt = dictionaries.en.og.alt;

export const size = OG_SIZE;

export const contentType = "image/png";

export default async function OGImageEn() {
  return renderOgImage({ headline: dictionaries.en.og.headline, sub: dictionaries.en.og.sub });
}
