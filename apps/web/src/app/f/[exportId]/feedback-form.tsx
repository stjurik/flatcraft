"use client";

/**
 * Client-side мобільна форма фідбеку. Тексти — UA/EN pinned за `docs/promts/inputs/c4-feedback-copy.md`.
 * State machine: idle → submitting → success | error.
 */
import { useState } from "react";

const OUTCOMES = ["made", "deviations", "failed"] as const;
type Outcome = (typeof OUTCOMES)[number];
type Locale = "uk" | "en";

interface Props {
  readonly exportId: string;
  readonly locale: Locale;
}

interface Copy {
  outcomeLabel: string;
  outcomeOptions: Record<Outcome, string>;
  deviationLabel: string;
  deviationPlaceholder: string;
  commentLabel: string;
  commentPlaceholderRequired: string;
  commentPlaceholderOptional: string;
  submit: string;
  submitting: string;
  success: string;
  error: string;
}

const COPY: Record<Locale, Copy> = {
  uk: {
    outcomeLabel: "Деталь вийшла?",
    outcomeOptions: {
      made: "✅ Так, все ок",
      deviations: "⚠️ З відхиленнями",
      failed: "❌ Не вийшла",
    },
    deviationLabel: "Розмір десь не збігся? Напиши, де і на скільки мм",
    deviationPlaceholder: "наприклад: полиця +0.3 мм",
    commentLabel: "Що сказати нам?",
    commentPlaceholderRequired: "обов'язково — якщо не вийшла",
    commentPlaceholderOptional: "необов'язково",
    submit: "Надіслати",
    submitting: "Надсилаю…",
    success: "Дякуємо! Це допомагає нам покращувати креслення.",
    error: "Не вдалося надіслати. Спробуй ще раз або напиши нам у Discord.",
  },
  en: {
    outcomeLabel: "Did the part come out?",
    outcomeOptions: {
      made: "✅ Yes, all good",
      deviations: "⚠️ With deviations",
      failed: "❌ Didn't come out",
    },
    deviationLabel: "Any size mismatch? Tell us where and how many mm",
    deviationPlaceholder: "e.g. shelf +0.3 mm",
    commentLabel: "What would you tell us?",
    commentPlaceholderRequired: "required if it didn't come out",
    commentPlaceholderOptional: "optional",
    submit: "Send",
    submitting: "Sending…",
    success: "Thanks! This helps us improve the drawings.",
    error: "Couldn't send. Try again or ping us on Discord.",
  },
};

type State = "idle" | "submitting" | "success" | "error";

const API_BASE = process.env.NEXT_PUBLIC_API_BASE_URL ?? "";

export function FeedbackForm({ exportId, locale }: Props): React.ReactElement {
  const [state, setState] = useState<State>("idle");
  const [outcome, setOutcome] = useState<Outcome | null>(null);
  const [deviation, setDeviation] = useState("");
  const [comment, setComment] = useState("");

  const copy = COPY[locale];
  const requireComment = outcome === "failed";
  const commentPlaceholder = requireComment
    ? copy.commentPlaceholderRequired
    : copy.commentPlaceholderOptional;

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>): Promise<void> {
    e.preventDefault();
    if (state === "submitting" || !outcome) return;

    setState("submitting");
    try {
      const response = await fetch(`${API_BASE}/feedback/${exportId}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          outcome,
          deviation_description: deviation.trim() || undefined,
          comment: comment.trim() || undefined,
          locale,
        }),
      });

      if (!response.ok) {
        setState("error");
        return;
      }
      setState("success");
    } catch {
      setState("error");
    }
  }

  if (state === "success") {
    return (
      <div
        role="status"
        aria-live="polite"
        className="rounded-lg border border-green-500 bg-green-50 p-4 text-green-900 dark:border-green-400 dark:bg-green-950 dark:text-green-100"
      >
        {copy.success}
      </div>
    );
  }

  return (
    <form onSubmit={handleSubmit} className="flex flex-col gap-6">
      <fieldset className="flex flex-col gap-3">
        <legend className="mb-1 text-base font-medium">{copy.outcomeLabel}</legend>
        <div className="flex flex-col gap-2">
          {OUTCOMES.map((value) => (
            <label
              key={value}
              className="has-checked:border-blue-600 has-checked:bg-blue-50 dark:has-checked:border-blue-400 dark:has-checked:bg-blue-950 flex min-h-[44px] cursor-pointer items-center gap-3 rounded-lg border border-neutral-300 px-4 py-3 hover:bg-neutral-50 dark:border-neutral-700 dark:hover:bg-neutral-900"
            >
              <input
                type="radio"
                name="outcome"
                value={value}
                checked={outcome === value}
                onChange={() => setOutcome(value)}
                required
                className="h-4 w-4"
              />
              <span className="text-base">{copy.outcomeOptions[value]}</span>
            </label>
          ))}
        </div>
      </fieldset>

      <label className="flex flex-col gap-2">
        <span className="text-base font-medium">{copy.deviationLabel}</span>
        <input
          type="text"
          value={deviation}
          onChange={(e) => setDeviation(e.target.value)}
          placeholder={copy.deviationPlaceholder}
          maxLength={500}
          className="min-h-[44px] rounded-lg border border-neutral-300 px-3 py-2 text-base focus:border-blue-600 focus:outline-none focus:ring-1 focus:ring-blue-600 dark:border-neutral-700"
        />
      </label>

      <label className="flex flex-col gap-2">
        <span className="text-base font-medium">
          {copy.commentLabel}{" "}
          <span className="text-xs text-neutral-500">({commentPlaceholder})</span>
        </span>
        <textarea
          value={comment}
          onChange={(e) => setComment(e.target.value)}
          rows={3}
          maxLength={1000}
          required={requireComment}
          className="min-h-[80px] rounded-lg border border-neutral-300 px-3 py-2 text-base focus:border-blue-600 focus:outline-none focus:ring-1 focus:ring-blue-600 dark:border-neutral-700"
        />
      </label>

      {state === "error" && (
        <div
          role="alert"
          className="rounded-lg border border-red-500 bg-red-50 p-3 text-sm text-red-900 dark:border-red-400 dark:bg-red-950 dark:text-red-100"
        >
          {copy.error}
        </div>
      )}

      <button
        type="submit"
        disabled={state === "submitting" || !outcome}
        className="flex min-h-[48px] items-center justify-center rounded-lg bg-blue-600 px-6 text-base font-medium text-white shadow hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-50"
      >
        {state === "submitting" ? copy.submitting : copy.submit}
      </button>
    </form>
  );
}
