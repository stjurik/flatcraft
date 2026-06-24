"use client";

import { validatePerforation } from "@flatcraft/cad-engine";
import { PerforatedPanelParametersSchema, type PerforatedPanelParameters } from "@flatcraft/types";
import { AutoForm, zodIssuesToFieldErrors } from "@flatcraft/ui";
import { useMemo } from "react";

interface PerforatedPanelEditorProps {
  readonly value: PerforatedPanelParameters;
  readonly onChange: (next: PerforatedPanelParameters) => void;
}

const IS_DEV = process.env.NEXT_PUBLIC_ENV === "dev";

/** Centered grid обчислення — мусить збігатися з Python `unfold_perforated_panel`. */
function computeGrid(p: PerforatedPanelParameters): { cols: number; rows: number; total: number } {
  const availX = p.length_mm - 2 * p.margin_mm;
  const availY = p.width_mm - 2 * p.margin_mm;
  if (availX < 0 || availY < 0) return { cols: 0, rows: 0, total: 0 };
  const cols = Math.max(1, Math.floor(availX / p.pitch_x_mm) + 1);
  const rows = Math.max(1, Math.floor(availY / p.pitch_y_mm) + 1);
  return { cols, rows, total: cols * rows };
}

export function PerforatedPanelEditor({ value, onChange }: PerforatedPanelEditorProps) {
  const validation = useMemo(() => PerforatedPanelParametersSchema.safeParse(value), [value]);
  const fieldErrors = useMemo(
    () => (validation.success ? {} : zodIssuesToFieldErrors(validation.error.issues)),
    [validation],
  );
  const zodErrors = useMemo(() => {
    if (validation.success) return [] as string[];
    return validation.error.issues.map((i) => `${i.path.join(".") || "form"}: ${i.message}`);
  }, [validation]);
  // Grid-геометрія: крок має перевищувати діаметр отвору, інакше отвори
  // зливаються (той самий валідатор, що й серверний gate).
  const perforationIssues = useMemo(
    () => validatePerforation({ templateSlug: "perforated_panel", parameters: value }),
    [value],
  );
  const allErrors = useMemo(
    () => [...perforationIssues.map((i) => i.message), ...zodErrors],
    [perforationIssues, zodErrors],
  );

  const grid = useMemo(() => computeGrid(value), [value]);

  return (
    <form
      data-testid="perforated-panel-editor"
      className="flex flex-col gap-4"
      onSubmit={(e) => e.preventDefault()}
    >
      <AutoForm
        schema={PerforatedPanelParametersSchema}
        value={value as unknown as Record<string, unknown>}
        onChange={(next) => onChange(next as unknown as PerforatedPanelParameters)}
        errors={fieldErrors}
      />

      <p className="text-fg-muted text-xs" data-testid="grid-summary">
        Grid: {grid.cols}×{grid.rows} = {grid.total} отворів Ø{value.hole_diameter_mm} мм (centered,
        pitch_x={value.pitch_x_mm} pitch_y={value.pitch_y_mm}).
      </p>

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
