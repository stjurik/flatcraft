"use client";

import { usePathname } from "next/navigation";
import { useEffect } from "react";

import { localeFromPathname } from "../i18n/routes";

/**
 * `<html lang>` синхронізується з поточним locale (ADR-037). Root layout
 * єдиний для всього застосунку (Next.js App Router дозволяє лише один
 * `<html>`), тому `lang` не може бути виведений статично на рівні
 * layout.tsx — коригуємо client-side при навігації.
 */
export function HtmlLangSync() {
  const pathname = usePathname();
  const locale = localeFromPathname(pathname);

  useEffect(() => {
    document.documentElement.lang = locale;
  }, [locale]);

  return null;
}
