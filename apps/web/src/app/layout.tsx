import type { Metadata, Viewport } from "next";
import { Inter, JetBrains_Mono } from "next/font/google";
import type { ReactNode } from "react";

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
    "Параметричний CAD для виробів з листового металу: DXF, PDF, STEP. " +
    "Безкоштовно, без CAD-навичок. Соціальний проєкт на підтримку ЗСУ.",
};

export const viewport: Viewport = {
  themeColor: "#f7f5f0",
  width: "device-width",
  initialScale: 1,
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="uk" className={`${inter.variable} ${jetbrainsMono.variable}`}>
      <body className="min-h-screen">{children}</body>
    </html>
  );
}
