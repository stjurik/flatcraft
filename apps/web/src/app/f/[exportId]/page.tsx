/**
 * Виробничий фідбек — мобільна форма (UA, default locale).
 *
 * Phase 3.4, ADR-032 §feedback / R-01 mitigation 4.
 * URL: /f/{exportId} — з QR-коду у PDF експортованого креслення.
 *
 * UX-тексти — `docs/promts/inputs/c4-feedback-copy.md` (Варіант 1 ★).
 * Мобільна-перша (360px viewport), без auth, 3 поля + submit + toast.
 */
import type { Metadata } from "next";

import { FeedbackForm } from "./feedback-form";

export const metadata: Metadata = {
  title: "Як вийшла деталь? · hart.crimea.ua",
  description: "Розкажи, як твоя деталь вийшла у металі. Це допомагає нам покращувати креслення.",
  alternates: {
    languages: {
      en: "/f/[exportId]/en",
    },
  },
  // Feedback-сторінка — приватна за посиланням з QR, не для індексації.
  robots: { index: false, follow: false },
};

interface Props {
  readonly params: Promise<{ exportId: string }>;
}

export default async function FeedbackPage({ params }: Props): Promise<React.ReactElement> {
  const { exportId } = await params;

  return (
    <main className="mx-auto flex min-h-screen max-w-md flex-col gap-6 px-4 py-8">
      <header className="flex flex-col gap-2">
        <h1 className="text-2xl font-bold tracking-tight">Як вийшла деталь?</h1>
        <p className="text-sm text-neutral-600 dark:text-neutral-400">
          Займе ~30 секунд. Твоя відповідь калібрує наступні креслення.
        </p>
        <a
          href={`/f/${exportId}/en`}
          className="text-xs text-blue-600 underline hover:text-blue-800 dark:text-blue-400"
        >
          Read in English →
        </a>
      </header>

      <FeedbackForm exportId={exportId} locale="uk" />
    </main>
  );
}
