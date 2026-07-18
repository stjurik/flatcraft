import Link from "next/link";

import { dictionaries } from "../i18n/dictionaries";
import type { Locale } from "../i18n/locale";
import { LocaleSwitcher } from "./locale-switcher";

interface LinkItem {
  readonly label: string;
  readonly href: string;
  readonly external?: boolean;
}

interface ColumnDef {
  readonly title: string;
  readonly items: ReadonlyArray<LinkItem>;
}

const GITHUB_URL = "https://github.com/stjurik/flatcraft";
const DISCORD_URL = "https://discord.gg/Zx88FAFtkS";

interface SiteLinksProps {
  readonly locale: Locale;
}

/**
 * App-local site-links: контент-залежний (маршрути цього застосунку,
 * а не reusable UI primitive). Споживається у layout.tsx як `linksSlot`
 * футера. Tap-target ≥44px — через мінімальний padding по вертикалі.
 *
 * `locale` перемикає лейбли/маршрути на EN-дзеркала (ADR-037 §2); лінки на
 * "GitHub"/"Discord"/"Telegram"/"Privacy"/"Terms"/"Cookies" лишаються тими
 * самими англомовними словами в обох локалях (уже нейтральні на uk-сайті).
 */
export function SiteLinks({ locale }: SiteLinksProps) {
  const dict = dictionaries[locale];
  const sl = dict.common.siteLinks;
  const prefix = locale === "en" ? "/en" : "";

  const columns: ReadonlyArray<ColumnDef> = [
    {
      title: sl.productTitle,
      items: [
        { label: sl.templates, href: `${prefix}/templates` },
        { label: sl.about, href: `${prefix}/about` },
        { label: sl.unlock, href: `${prefix}/soon` },
      ],
    },
    {
      title: sl.communityTitle,
      items: [
        { label: sl.github, href: GITHUB_URL, external: true },
        { label: sl.discord, href: DISCORD_URL, external: true },
        { label: sl.telegram, href: `${prefix}/soon` },
      ],
    },
    {
      title: sl.legalTitle,
      items: [
        { label: sl.privacy, href: locale === "en" ? "/privacy/en" : "/privacy" },
        { label: sl.terms, href: locale === "en" ? "/terms/en" : "/terms" },
        { label: sl.cookies, href: locale === "en" ? "/privacy/en#cookies" : "/privacy#cookies" },
      ],
    },
  ];

  return (
    <div className="flex flex-col gap-4">
      <nav
        data-testid="site-links"
        aria-label={sl.sitemapAria}
        className="grid grid-cols-1 gap-6 sm:grid-cols-3 sm:gap-8"
      >
        {columns.map((col) => (
          <div key={col.title} className="flex flex-col gap-2">
            <h2 className="text-fg text-sm font-semibold uppercase tracking-wide">{col.title}</h2>
            <ul className="flex flex-col gap-1">
              {col.items.map((item) => (
                <li key={`${col.title}-${item.label}`}>
                  {item.external ? (
                    <a
                      href={item.href}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-fg-muted hover:text-fg min-h-tap inline-flex items-center text-sm"
                    >
                      {item.label}
                    </a>
                  ) : (
                    <Link
                      href={item.href}
                      className="text-fg-muted hover:text-fg min-h-tap inline-flex items-center text-sm"
                    >
                      {item.label}
                    </Link>
                  )}
                </li>
              ))}
            </ul>
          </div>
        ))}
      </nav>
      <div className="flex items-center justify-between gap-4">
        {/* Cookie-нотис (WP3 legal-мінімум): Umami cookie-less → banner непотрібен. */}
        <p data-testid="site-cookie-note" className="text-fg-subtle text-xs">
          {dict.common.cookieNote}
        </p>
        <LocaleSwitcher />
      </div>
    </div>
  );
}
