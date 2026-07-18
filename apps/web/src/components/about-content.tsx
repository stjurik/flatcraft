import { Gift, Github, Heart, type LucideIcon } from "@flatcraft/ui";

import { dictionaries } from "../i18n/dictionaries";
import { DEFAULT_LOCALE, type Locale } from "../i18n/locale";
import { TemplateThumb } from "./template-thumb";

const GITHUB_ISSUES_URL = "https://github.com/stjurik/flatcraft/issues";
const MONOBANK_JAR_URL = "https://send.monobank.ua/jar/A1u3M7VqQz";
const UNITED24_URL = "https://u24.gov.ua/";
const FEEDBACK_EMAIL = "feedback@hart.crimea.ua";
const DISCORD_URL = "https://discord.gg/Zx88FAFtkS";

interface AboutContentProps {
  readonly locale?: Locale;
}

/**
 * `/about` (ADR-037 §2) — спільний presentational-компонент для uk/en
 * дзеркал. uk-текст byte-identical до попереднього hardcoded варіанту.
 */
export function AboutContent({ locale = DEFAULT_LOCALE }: AboutContentProps = {}) {
  const dict = dictionaries[locale].about;
  const icons: readonly LucideIcon[] = [Gift, Heart, Github];

  return (
    <main className="bg-bg">
      <div className="mx-auto flex max-w-5xl flex-col gap-16 px-4 py-12 sm:py-16">
        {/* Hero */}
        <section data-testid="about-hero" className="flex flex-col gap-4">
          <p className="text-fg-subtle text-xs font-semibold uppercase tracking-wide">
            {dict.badge}
          </p>
          <h1 className="font-display text-fg text-3xl font-semibold sm:text-4xl">
            {dict.heroTitle}
          </h1>
          <p className="text-fg-muted max-w-2xl text-lg">{dict.heroSubtitle}</p>
        </section>

        {/* Section 1 — Що це таке */}
        <section
          data-testid="about-what"
          className="grid grid-cols-1 items-center gap-8 md:grid-cols-2"
        >
          <div className="flex flex-col gap-4">
            <h2 className="font-display text-fg text-2xl font-semibold">{dict.whatTitle}</h2>
            <p className="text-fg-muted">{dict.whatP1}</p>
            <p className="text-fg-muted">{dict.whatP2}</p>
            <p className="text-fg-muted">{dict.whatP3}</p>
          </div>
          <div className="text-fg-muted bg-surface-sunken border-border mx-auto aspect-[4/3] w-full max-w-sm rounded-md border p-6">
            <TemplateThumb slug="l_bracket" />
          </div>
        </section>

        {/* Section 2 — Безкоштовно. Чому? */}
        <section data-testid="about-free" className="flex flex-col gap-6">
          <h2 className="font-display text-fg text-2xl font-semibold">{dict.freeTitle}</h2>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
            {dict.freeCards.map(({ title, body }, idx) => {
              const Icon = icons[idx] ?? Gift;
              return (
                <div
                  key={title}
                  className="border-border bg-bg-elevated flex flex-col gap-3 rounded-md border p-5"
                >
                  <Icon className="text-primary h-6 w-6" aria-hidden="true" />
                  <h3 className="text-fg font-semibold">{title}</h3>
                  <p className="text-fg-muted text-sm">{body}</p>
                </div>
              );
            })}
          </div>
        </section>

        {/* Section 3 — Підтримати ЗСУ */}
        <section
          data-testid="about-zsu"
          className="border-border bg-surface-sunken flex flex-col gap-5 rounded-md border p-6 sm:p-8"
        >
          <h2 className="font-display text-fg text-2xl font-semibold">{dict.zsuTitle}</h2>
          <div className="flex flex-col gap-3 sm:flex-row">
            <a
              data-testid="about-donate-monobank"
              href={MONOBANK_JAR_URL}
              target="_blank"
              rel="noopener noreferrer"
              className="bg-zsu-bg text-zsu-fg hover:bg-zsu-bg-hover min-h-tap inline-flex items-center justify-center gap-2 rounded-md px-6 py-3 text-base font-medium"
            >
              <Heart className="h-5 w-5" aria-hidden="true" />
              {dict.zsuMonobankLabel}
            </a>
            <a
              data-testid="about-donate-united24"
              href={UNITED24_URL}
              target="_blank"
              rel="noopener noreferrer"
              className="border-border-strong text-fg hover:bg-surface-muted min-h-tap inline-flex items-center justify-center gap-2 rounded-md border px-6 py-3 text-base font-medium"
            >
              {dict.zsuUnited24Label}
            </a>
          </div>
          <p className="text-fg-subtle text-sm">{dict.zsuNote}</p>
        </section>

        {/* Section 4 — Зворотний зв'язок */}
        <section data-testid="about-feedback" className="flex flex-col gap-4">
          <h2 className="font-display text-fg text-2xl font-semibold">{dict.feedbackTitle}</h2>
          <p className="text-fg-muted">{dict.feedbackBody}</p>
          <ul className="flex flex-col gap-2">
            <li>
              <a
                data-testid="about-feedback-email"
                href={`mailto:${FEEDBACK_EMAIL}`}
                className="text-primary hover:text-primary-hover min-h-tap inline-flex items-center text-sm font-medium"
              >
                {FEEDBACK_EMAIL}
              </a>
            </li>
            <li>
              <a
                data-testid="about-feedback-github"
                href={GITHUB_ISSUES_URL}
                target="_blank"
                rel="noopener noreferrer"
                className="text-primary hover:text-primary-hover min-h-tap inline-flex items-center text-sm font-medium"
              >
                {dict.feedbackGithubLabel}
              </a>
            </li>
            <li>
              <a
                data-testid="about-feedback-discord"
                href={DISCORD_URL}
                target="_blank"
                rel="noopener noreferrer"
                className="text-primary hover:text-primary-hover min-h-tap inline-flex items-center text-sm font-medium"
              >
                {dict.feedbackDiscordLabel}
              </a>
            </li>
          </ul>
        </section>
      </div>
    </main>
  );
}
