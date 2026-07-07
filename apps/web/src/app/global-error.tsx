"use client";

import * as Sentry from "@sentry/nextjs";
import { useEffect } from "react";

/**
 * Глобальний error-boundary root-layout'у (Next App Router). Репортить
 * необроблені render-помилки у Sentry (ADR-032; закриває R-02 — краш R3F на
 * реальних пристроях, зараз неперевірюваний). R3F-специфічний backstop —
 * `R3FErrorBoundary` (ADR-026); цей — остання лінія на рівні всього застосунку.
 */
export default function GlobalError({ error }: { error: Error & { digest?: string } }) {
  useEffect(() => {
    Sentry.captureException(error);
  }, [error]);

  return (
    <html lang="uk">
      <body style={{ fontFamily: "system-ui, sans-serif", padding: "2rem", textAlign: "center" }}>
        <h1 style={{ fontSize: "1.25rem" }}>Щось пішло не так</h1>
        <p>Спробуйте оновити сторінку. Ми вже отримали звіт про помилку.</p>
      </body>
    </html>
  );
}
