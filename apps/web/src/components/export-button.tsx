"use client";

import type { LBracketParameters } from "@flatcraft/types";
import { useState } from "react";

import { ApiError, createExport } from "../lib/api";

type ExportState =
  | { readonly status: "idle" }
  | { readonly status: "loading" }
  | { readonly status: "success"; readonly url: string; readonly bytes: number }
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

  const click = async () => {
    setState({ status: "loading" });
    try {
      const res = await createExport({
        template_slug: templateSlug,
        parameters,
        thickness_mm: thicknessMm,
      });
      setState({ status: "success", url: res.dxf_url, bytes: res.bytes });
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

  const isBusy = state.status === "loading";
  const isDisabled = disabled || isBusy;

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
        {isBusy ? "Експорт…" : "Експортувати DXF"}
      </button>

      {state.status === "success" ? (
        <a
          data-testid="export-download-link"
          href={state.url}
          target="_blank"
          rel="noopener noreferrer"
          className="text-sm text-emerald-300 underline hover:text-emerald-200"
        >
          Завантажити DXF ({Math.round(state.bytes / 1024)} КБ)
        </a>
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
