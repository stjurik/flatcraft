import Link from "next/link";

import { dictionaries } from "../i18n/dictionaries";
import { DEFAULT_LOCALE, type Locale } from "../i18n/locale";

interface SoonContentProps {
  readonly locale?: Locale;
}

/**
 * Заглушка для placeholder-маршрутів (Discord, Telegram, /unlock — Phase
 * 2.12.b). ADR-037 §2 — спільний компонент для uk/en дзеркал.
 */
export function SoonContent({ locale = DEFAULT_LOCALE }: SoonContentProps = {}) {
  const dict = dictionaries[locale].soon;
  const homeHref = locale === "en" ? "/en" : "/";

  return (
    <main className="mx-auto flex min-h-[60vh] max-w-2xl flex-col items-start justify-center gap-4 px-4 py-12">
      <p className="text-fg-subtle text-xs uppercase tracking-wide">{dict.eyebrow}</p>
      <h1 className="font-display text-fg xs:text-4xl text-3xl font-semibold">{dict.title}</h1>
      <p className="text-fg-muted">
        {dict.body1}{" "}
        <a
          href="https://github.com/stjurik/flatcraft"
          target="_blank"
          rel="noopener noreferrer"
          className="text-primary hover:text-primary-hover underline"
        >
          {dict.githubLabel}
        </a>{" "}
        {dict.body2}
      </p>
      <Link
        href={homeHref}
        className="text-primary hover:text-primary-hover min-h-tap inline-flex items-center text-sm font-medium"
      >
        {dict.backHome}
      </Link>
    </main>
  );
}
