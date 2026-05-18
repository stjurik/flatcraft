"use client";

import type { ExportJobEvent, ExportResponse, LBracketParameters } from "@flatcraft/types";
import { useEffect, useRef, useState } from "react";

import { ApiError, createExport, subscribeExportEvents } from "../lib/api";

type ExportState =
  | { readonly status: "idle" }
  | { readonly status: "queued"; readonly jobId: string; readonly progress: number }
  | { readonly status: "running"; readonly jobId: string; readonly progress: number }
  | { readonly status: "done"; readonly result: ExportResponse }
  | { readonly status: "error"; readonly message: string };

interface ExportButtonProps {
  readonly templateSlug: "l_bracket";
  readonly parameters: LBracketParameters;
  readonly thicknessMm: number;
  readonly disabled?: boolean;
}

export function ExportButton({
  templateSlug,
  parameters,
  thicknessMm,
  disabled = false,
}: ExportButtonProps) {
  const [state, setState] = useState<ExportState>({ status: "idle" });
  const closeRef = useRef<(() => void) | null>(null);

  // Прибираємо open SSE на unmount, щоб не текти listeners при routing.
  useEffect(() => () => closeRef.current?.(), []);

  const handleEvent = (ev: ExportJobEvent) => {
    if (ev.status === "done" && ev.result) {
      setState({ status: "done", result: ev.result });
    } else if (ev.status === "failed") {
      setState({ status: "error", message: ev.error ?? "Експорт не вдався" });
    } else {
      setState({
        status: ev.status === "running" ? "running" : "queued",
        jobId: ev.id,
        progress: ev.progress,
      });
    }
  };

  const click = async () => {
    closeRef.current?.();
    setState({ status: "queued", jobId: "", progress: 0 });
    try {
      const accepted = await createExport({
        template_slug: templateSlug,
        parameters,
        thickness_mm: thicknessMm,
      });
      setState({ status: "queued", jobId: accepted.id, progress: 0 });
      closeRef.current = subscribeExportEvents(accepted.id, handleEvent, (err) =>
        setState({ status: "error", message: err.message }),
      );
    } catch (err) {
      const message =
        err instanceof ApiError
          ? `API ${err.status}: експорт не вдався`
          : err instanceof Error
            ? err.message
            : "Невідома помилка";
      setState({ status: "error", message });
    }
  };

  const isBusy = state.status === "queued" || state.status === "running";
  const isDisabled = disabled || isBusy;
  const progress = state.status === "queued" || state.status === "running" ? state.progress : 0;

  return (
    <div data-testid="export-button-section" className="flex flex-col gap-2">
      <button
        type="button"
        data-testid="export-button"
        data-state={state.status}
        disabled={isDisabled}
        onClick={click}
        className={`rounded-md px-4 py-2 text-sm font-medium transition ${
          isDisabled
            ? "cursor-not-allowed bg-zinc-900 text-zinc-600"
            : "bg-emerald-700 text-white hover:bg-emerald-600"
        }`}
      >
        {isBusy ? `Експорт… ${progress}%` : "Експортувати DXF"}
      </button>

      {isBusy ? (
        <div
          data-testid="export-progress-bar"
          className="h-1.5 w-full overflow-hidden rounded-full bg-zinc-800"
        >
          <div
            data-testid="export-progress-bar-fill"
            data-progress={progress}
            className="h-full bg-emerald-500 transition-all"
            style={{ width: `${progress}%` }}
          />
        </div>
      ) : null}

      {state.status === "done" ? (
        <div className="flex flex-col gap-1 text-sm">
          <a
            data-testid="export-download-link"
            href={state.result.artifacts.dxf.url}
            target="_blank"
            rel="noopener noreferrer"
            className="text-emerald-300 underline hover:text-emerald-200"
          >
            Завантажити DXF ({Math.round(state.result.artifacts.dxf.bytes / 1024)} КБ)
          </a>
          <a
            data-testid="export-download-link-pdf"
            href={state.result.artifacts.pdf.url}
            target="_blank"
            rel="noopener noreferrer"
            className="text-emerald-300 underline hover:text-emerald-200"
          >
            Завантажити PDF ({Math.round(state.result.artifacts.pdf.bytes / 1024)} КБ)
          </a>
        </div>
      ) : null}

      {state.status === "error" ? (
        <p
          data-testid="export-error"
          className="rounded-md border border-red-900/50 bg-red-950/30 p-2 text-xs text-red-300"
        >
          {state.message}
        </p>
      ) : null}
    </div>
  );
}
