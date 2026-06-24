"use client";

import { validatePerforation } from "@flatcraft/cad-engine";
import {
  PerforatedPanelSquareParametersSchema,
  type PerforatedPanelSquareParameters,
} from "@flatcraft/types";
import { AutoForm, zodIssuesToFieldErrors } from "@flatcraft/ui";
import { useMemo } from "react";

interface PerforatedPanelSquareEditorProps {
  readonly value: PerforatedPanelSquareParameters;
  readonly onChange: (next: PerforatedPanelSquareParameters) => void;
  /** Phase 3.0 PR 4: visible_fields для product-mode. */
  readonly visibleFields?: readonly string[];
}

const IS_DEV = process.env.NEXT_PUBLIC_ENV === "dev";

function computeGrid(p: PerforatedPanelSquareParameters): {
  cols: number;
  rows: number;
  total: number;
} {
  const availX = p.length_mm - 2 * p.margin_mm;
  const availY = p.width_mm - 2 * p.margin_mm;
  if (availX < 0 || availY < 0) return { cols: 0, rows: 0, total: 0 };
  const cols = Math.max(1, Math.floor(availX / p.pitch_x_mm) + 1);
  const rows = Math.max(1, Math.floor(availY / p.pitch_y_mm) + 1);
  return { cols, rows, total: cols * rows };
}

export function PerforatedPanelSquareEditor({
  value,
  onChange,
  visibleFields,
}: PerforatedPanelSquareEditorProps) {
  const validation = useMemo(() => PerforatedPanelSquareParametersSchema.safeParse(value), [value]);
  const fieldErrors = useMemo(
    () => (validation.success ? {} : zodIssuesToFieldErrors(validation.error.issues)),
    [validation],
  );
  const zodErrors = useMemo(() => {
    if (validation.success) return [] as string[];
    return validation.error.issues.map((i) => `${i.path.join(".") || "form"}: ${i.message}`);
  }, [validation]);
  // Grid-геометрія: крок має перевищувати сторону отвору, інакше отвори
  // зливаються (той самий валідатор, що й серверний gate).
  const perforationIssues = useMemo(
    () => validatePerforation({ templateSlug: "perforated_panel_square", parameters: value }),
    [value],
  );
  const allErrors = useMemo(
    () => [...perforationIssues.map((i) => i.message), ...zodErrors],
    [perforationIssues, zodErrors],
  );
  const grid = useMemo(() => computeGrid(value), [value]);

  return (
    <form
      data-testid="perforated-panel-square-editor"
      className="flex flex-col gap-4"
      onSubmit={(e) => e.preventDefault()}
    >
      <AutoForm
        schema={PerforatedPanelSquareParametersSchema}
        value={value as unknown as Record<string, unknown>}
        onChange={(next) => onChange(next as unknown as PerforatedPanelSquareParameters)}
        errors={fieldErrors}
        {...(visibleFields ? { visibleFields } : {})}
      />

      <div
        data-testid="grid-summary-square"
        className="border-border bg-surface-muted rounded-md border p-3 text-sm"
      >
        <p className="text-fg">
          Сітка: <strong>{grid.cols}</strong> × <strong>{grid.rows}</strong> = квадратні отвори{" "}
          <strong>{grid.total}</strong> □ {value.hole_size_mm}мм
        </p>
      </div>

      {allErrors.length > 0 ? (
        <ul
          data-testid="validation-errors"
          className="border-danger/40 bg-danger-surface text-danger rounded-md border p-3 text-sm"
        >
          {allErrors.map((msg) => (
            <li key={msg}>{msg}</li>
          ))}
        </ul>
      ) : (
        <p
          data-testid="validation-ok"
          className="border-success/40 bg-success-surface text-success rounded-md border p-3 text-sm"
        >
          Параметри валідні. Натискайте «Експортувати».
        </p>
      )}

      {IS_DEV ? (
        <details className="text-fg-subtle text-xs">
          <summary className="cursor-pointer">Параметри (JSON · dev only)</summary>
          <pre
            data-testid="params-preview"
            className="border-border bg-surface-muted text-fg mt-2 overflow-x-auto rounded-sm border p-3"
          >
            {JSON.stringify(value, null, 2)}
          </pre>
        </details>
      ) : null}
    </form>
  );
}
