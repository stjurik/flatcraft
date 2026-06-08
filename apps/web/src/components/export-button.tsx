"use client";

import type { ExportJobEvent, ExportRequest, ExportResponse } from "@flatcraft/types";
import { Button } from "@flatcraft/ui";
import { useEffect, useRef, useState } from "react";

import { ApiError, createExport, subscribeExportEvents } from "../lib/api";
import { PostExportDonateNudge } from "./post-export-donate-nudge";

type ExportState =
  | { readonly status: "idle" }
  | { readonly status: "queued"; readonly jobId: string; readonly progress: number }
  | { readonly status: "running"; readonly jobId: string; readonly progress: number }
  | { readonly status: "done"; readonly result: ExportResponse }
  | { readonly status: "error"; readonly message: string };

interface ExportButtonProps {
  /** Готовий ExportRequest payload — discriminated на template_slug. */
  readonly request: ExportRequest;
  readonly disabled?: boolean;
}

export function ExportButton({ request, disabled = false }: ExportButtonProps) {
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
      const accepted = await createExport(request);
      setState({ status: "queued", jobId: accepted.id, progress: 0 });
      closeRef.current = subscribeExportEvents(accepted.id, handleEvent, (err) =>
        setState({ status: "error", message: err.message }),
      );
    } catch (err) {
      // Hotfix 2.9.c (C): ApiError.message тепер несе дружній RFC 9457 `detail`
      // з сервера (напр. «Збільшіть радіус…»), а не generic «експорт не вдався».
      const message =
        err instanceof ApiError
          ? `API ${err.status}: ${err.message}`
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
      <Button
        type="button"
        data-testid="export-button"
        data-state={state.status}
        variant="default"
        size="lg"
        disabled={isDisabled}
        onClick={click}
      >
        {isBusy ? `Експорт… ${progress}%` : "Експортувати DXF + PDF"}
      </Button>

      {isBusy ? (
        <div
          data-testid="export-progress-bar"
          className="bg-surface-muted h-1.5 w-full overflow-hidden rounded-full"
        >
          <div
            data-testid="export-progress-bar-fill"
            data-progress={progress}
            className="bg-primary duration-base h-full transition-all ease-out"
            style={{ width: `${progress}%` }}
          />
        </div>
      ) : null}

      {state.status === "done" ? (
        <>
          <div className="flex flex-col gap-1 text-sm">
            <a
              data-testid="export-download-link"
              href={state.result.artifacts.dxf.url}
              target="_blank"
              rel="noopener noreferrer"
              className="text-primary hover:text-primary-hover underline"
            >
              Завантажити DXF ({Math.round(state.result.artifacts.dxf.bytes / 1024)} КБ)
            </a>
            <a
              data-testid="export-download-link-pdf"
              href={state.result.artifacts.pdf.url}
              target="_blank"
              rel="noopener noreferrer"
              className="text-primary hover:text-primary-hover underline"
            >
              Завантажити PDF ({Math.round(state.result.artifacts.pdf.bytes / 1024)} КБ)
            </a>
          </div>
          {/* Phase X.1 C: ненав'язливе ЗСУ-нагадування ПІД download-лінками. */}
          <PostExportDonateNudge />
        </>
      ) : null}

      {state.status === "error" ? (
        <p
          data-testid="export-error"
          className="border-danger/40 bg-danger-surface text-danger rounded-md border p-2 text-xs"
        >
          {state.message}
        </p>
      ) : null}
    </div>
  );
}
