"use client";

import { Footer, Logo } from "@flatcraft/ui";
import Link from "next/link";
import { usePathname } from "next/navigation";

import { dictionaries } from "../i18n/dictionaries";
import { localeFromPathname } from "../i18n/routes";
import { SiteLinks } from "./site-links";

/**
 * Header home-link, локалізований (ADR-037). Client — локаль читається з
 * pathname через `usePathname()`, root layout сам лишається Server
 * Component і не знає про поточний маршрут.
 */
export function SiteHeaderHomeLink() {
  const pathname = usePathname();
  const locale = localeFromPathname(pathname);
  const dict = dictionaries[locale];
  const homeHref = locale === "en" ? "/en" : "/";

  return (
    <Link
      href={homeHref}
      aria-label={dict.common.homeAriaLabel}
      className="inline-flex items-center"
    >
      <Logo size="md" />
    </Link>
  );
}

/** Footer, локалізований (ADR-037) — tagline/donate-лейбл/SiteLinks за поточним locale. */
export function LocalizedFooter() {
  const pathname = usePathname();
  const locale = localeFromPathname(pathname);
  const dict = dictionaries[locale];

  return (
    <Footer
      tagline={dict.common.footerTagline}
      donateLabel={dict.common.footerDonate}
      linksSlot={<SiteLinks locale={locale} />}
    />
  );
}
