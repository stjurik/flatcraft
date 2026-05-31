import Link from "next/link";

export const metadata = {
  title: "Скоро з'явиться · hart",
};

/**
 * Заглушка для placeholder-маршрутів (Discord, Telegram, /about, /unlock,
 * /privacy, /terms, /cookies — Phase 2.12.b). Реальні сторінки прийдуть
 * у Phase 3+ (auth/donations) і Phase 5 (legal docs).
 */
export default function SoonPage() {
  return (
    <main className="mx-auto flex min-h-[60vh] max-w-2xl flex-col items-start justify-center gap-4 px-4 py-12">
      <p className="text-fg-subtle text-xs uppercase tracking-wide">Скоро з'явиться</p>
      <h1 className="font-display text-fg xs:text-4xl text-3xl font-semibold">
        Запланована сторінка
      </h1>
      <p className="text-fg-muted">
        Ця секція ще не активна. Слідкуйте за оновленнями у нашому{" "}
        <a
          href="https://github.com/stjurik/flatcraft"
          target="_blank"
          rel="noopener noreferrer"
          className="text-primary hover:text-primary-hover underline"
        >
          GitHub
        </a>{" "}
        — там видно, що зараз у розробці.
      </p>
      <Link
        href="/"
        className="text-primary hover:text-primary-hover min-h-tap inline-flex items-center text-sm font-medium"
      >
        ← На головну
      </Link>
    </main>
  );
}
