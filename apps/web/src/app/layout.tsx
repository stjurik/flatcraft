import { Footer, Logo } from "@flatcraft/ui";
import type { Metadata, Viewport } from "next";
import { Inter, JetBrains_Mono } from "next/font/google";
import Link from "next/link";
import type { ReactNode } from "react";

import { SiteLinks } from "../components/site-links";
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

export const metadata: Metadata = {
  title: "hart.crimea.ua — параметричний CAD для листового металу",
  description:
    "Креслення листового металу за 60 секунд. Без CAD-навичок. " +
    "10 експортів/міс безкоштовно. Соціальний проєкт на підтримку ЗСУ.",
  // TODO(Phase 2.16): додати /og-default.png (1200×630 з логотипом +
  // headline) і прокинути сюди як openGraph.images. Поки не блокуємо
  // лендінг — соцмережі показують default-preview без image.
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
        <header
          data-testid="site-header"
          className="bg-bg-elevated border-border xs:px-4 sticky top-0 z-30 flex h-14 items-center justify-between border-b md:px-6"
        >
          <Link href="/" aria-label="Перейти на головну" className="inline-flex items-center">
            <Logo size="md" />
          </Link>
          {/* Праве місце — заповниться меню/auth-кнопками у Phase 3+. */}
          <div aria-hidden="true" />
        </header>
        <main className="flex flex-1 flex-col">{children}</main>
        <Footer linksSlot={<SiteLinks />} />
      </body>
    </html>
  );
}
