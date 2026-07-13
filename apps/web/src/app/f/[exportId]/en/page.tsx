/**
 * Manufacturing feedback — mobile form (EN).
 * See UA variant at `/f/[exportId]` for reasoning + full docs.
 */
import type { Metadata } from "next";

import { FeedbackForm } from "../feedback-form";

export const metadata: Metadata = {
  title: "How did the part come out? · hart.crimea.ua",
  description: "Tell us how your part came out in metal. This helps us improve the drawings.",
  alternates: {
    languages: {
      uk: "/f/[exportId]",
    },
  },
  robots: { index: false, follow: false },
};

interface Props {
  readonly params: Promise<{ exportId: string }>;
}

export default async function FeedbackPageEn({ params }: Props): Promise<React.ReactElement> {
  const { exportId } = await params;

  return (
    <main className="mx-auto flex min-h-screen max-w-md flex-col gap-6 px-4 py-8">
      <header className="flex flex-col gap-2">
        <h1 className="text-2xl font-bold tracking-tight">How did the part come out?</h1>
        <p className="text-sm text-neutral-600 dark:text-neutral-400">
          Takes ~30 seconds. Your answer calibrates the next drawings.
        </p>
        <a
          href={`/f/${exportId}`}
          className="text-xs text-blue-600 underline hover:text-blue-800 dark:text-blue-400"
        >
          Читати українською →
        </a>
      </header>

      <FeedbackForm exportId={exportId} locale="en" />
    </main>
  );
}
