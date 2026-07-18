import type { Metadata, Viewport } from "next";
import { Inter, JetBrains_Mono } from "next/font/google";
import type { ReactNode } from "react";

import { AnalyticsScripts } from "../components/analytics-scripts";
import { HtmlLangSync } from "../components/html-lang-sync";
import { LocalizedFooter, SiteHeaderHomeLink } from "../components/site-chrome";
import { WebVitals } from "../components/web-vitals";
import { dictionaries } from "../i18n/dictionaries";
import "./globals.css";

/**
 * Self-hosted Google Fonts (next/font/google) — без runtime-CDN, без CLS.
 * Subset latin + cyrillic — українська + латинське ядро без зайвої ваги
 * (без латиничного-розширеного, грецького, в'єтнамського тощо).
 */
const inter = Inter({
  subsets: ["latin", "cyrillic"],
  display: "swap",
  variable: "--font-inter",
});

const jetbrainsMono = JetBrains_Mono({
  subsets: ["latin", "cyrillic"],
  display: "swap",
  variable: "--font-jetbrains-mono",
});

const SITE_URL = "https://hart.crimea.ua";
const dict = dictionaries.uk;

/**
 * Root-metadata — uk-базовий fallback. Кожна `/en/**` сторінка (ADR-037 §2)
 * експортує власний `metadata` з EN-текстом — Next.js мерджить page-level
 * поверх layout-level, тому окремого locale-branching тут не потрібно.
 */
export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: dict.common.siteTitle,
  description: dict.common.siteDescription,
  // OG image живе як `app/opengraph-image.tsx` (Next App Router convention).
  // Next автоматично резолвить URL і додає у `<meta property="og:image">`,
  // тому `openGraph.images` тут НЕ задаємо — інакше було б дублювання.
  openGraph: {
    type: "website",
    locale: dict.common.ogLocale,
    url: SITE_URL,
    siteName: "hart.crimea.ua",
    title: dict.common.siteTitle,
    description: dict.common.siteDescription,
  },
  twitter: {
    card: "summary_large_image",
    title: dict.common.siteTitle,
    description: dict.common.siteDescription,
  },
};

export const viewport: Viewport = {
  themeColor: "#f7f5f0",
  width: "device-width",
  initialScale: 1,
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="uk" className={`${inter.variable} ${jetbrainsMono.variable}`}>
      <body className="flex min-h-screen flex-col">
        <HtmlLangSync />
        <AnalyticsScripts />
        <WebVitals />
        <header
          data-testid="site-header"
          className="bg-bg-elevated border-border xs:px-4 sticky top-0 z-30 flex h-14 items-center justify-between border-b md:px-6"
        >
          <SiteHeaderHomeLink />
          {/* Праве місце — заповниться меню/auth-кнопками у Phase 3+. */}
          <div aria-hidden="true" />
        </header>
        <main className="flex flex-1 flex-col">{children}</main>
        <LocalizedFooter />
      </body>
    </html>
  );
}
