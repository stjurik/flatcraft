import { NextResponse, type NextRequest } from "next/server";

import { LOCALE_COOKIE } from "./i18n/locale";
import { toEnPath } from "./i18n/routes";

/**
 * Auto-detect мови на перший візит (ADR-037 §3). Функціональна cookie
 * (не аналітична, не трекінг) — узгоджено з `/privacy` §2.
 *
 * `matcher` НАВМИСНО вузький — лише 6 дзеркалених Etap A-шляхів
 * (`i18n/routes.ts` MIRRORED_UK_PATH_PREFIXES), не весь сайт. Це обмежує
 * blast radius: `/privacy`, `/terms`, `/f/[exportId]`, `/styleguide` тощо
 * middleware не чіпає.
 *
 * КРИТИЧНО для CI: Playwright headless Chromium без явного `use.locale`
 * шле Accept-Language системи раннера (типово en-US на GH Actions) — тому
 * `playwright.config.ts` фіксує `locale: "uk-UA"` для контексту тестів,
 * інакше цей middleware зламав би всі наявні uk e2e.
 */
export function middleware(request: NextRequest): NextResponse {
  if (request.cookies.get(LOCALE_COOKIE)) {
    return NextResponse.next();
  }

  const acceptLanguage = request.headers.get("accept-language") ?? "";
  const primaryTag = acceptLanguage.split(",")[0]?.trim().toLowerCase() ?? "";
  const prefersEnglish = primaryTag.startsWith("en");

  const response = prefersEnglish
    ? NextResponse.redirect(new URL(toEnPath(request.nextUrl.pathname), request.url))
    : NextResponse.next();

  response.cookies.set(LOCALE_COOKIE, prefersEnglish ? "en" : "uk", {
    maxAge: 60 * 60 * 24 * 365,
    sameSite: "lax",
    path: "/",
  });

  return response;
}

export const config = {
  matcher: ["/", "/about", "/soon", "/templates", "/templates/:slug", "/products/:slug"],
};
