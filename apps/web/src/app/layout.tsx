import type { Metadata, Viewport } from "next";
import type { ReactNode } from "react";

import "./globals.css";

export const metadata: Metadata = {
  title: "flatcraft",
  description: "Безкоштовний параметричний CAD для виробів з листового металу — DXF, PDF, STEP.",
};

export const viewport: Viewport = {
  themeColor: "#0a0a0a",
  width: "device-width",
  initialScale: 1,
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="uk">
      <body className="min-h-screen">{children}</body>
    </html>
  );
}
