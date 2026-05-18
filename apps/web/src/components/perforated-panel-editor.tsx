"use client";

import { PerforatedPanelParametersSchema, type PerforatedPanelParameters } from "@flatcraft/types";
import { AutoForm, zodIssuesToFieldErrors, type AutoFormLabels } from "@flatcraft/ui";
import { useMemo } from "react";

interface PerforatedPanelEditorProps {
  readonly value: PerforatedPanelParameters;
  readonly onChange: (next: PerforatedPanelParameters) => void;
}

const LABELS: AutoFormLabels = {
  length_mm: "Довжина листа, мм",
  width_mm: "Ширина листа, мм",
  hole_diameter_mm: "Діаметр отворів, мм",
  pitch_x_mm: "Pitch X (крок вздовж довжини), мм",
  pitch_y_mm: "Pitch Y (крок вздовж ширини), мм",
  margin_mm: "Відступ від країв, мм",
};

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
  const allErrors = useMemo(() => {
    if (validation.success) return [] as string[];
    return validation.error.issues.map((i) => `${i.path.join(".") || "form"}: ${i.message}`);
  }, [validation]);

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
        labels={LABELS}
        errors={fieldErrors}
      />

      <p className="text-xs text-zinc-500" data-testid="grid-summary">
        Grid: {grid.cols}×{grid.rows} = {grid.total} отворів Ø{value.hole_diameter_mm} мм (centered,
        pitch_x={value.pitch_x_mm} pitch_y={value.pitch_y_mm}).
      </p>

      {allErrors.length > 0 ? (
        <ul
          data-testid="validation-errors"
          className="rounded-lg border border-red-900/50 bg-red-950/30 p-3 text-sm text-red-300"
        >
          {allErrors.map((msg) => (
            <li key={msg}>{msg}</li>
          ))}
        </ul>
      ) : (
        <p
          data-testid="validation-ok"
          className="rounded-lg border border-emerald-900/50 bg-emerald-950/30 p-3 text-sm text-emerald-300"
        >
          Параметри валідні. Експорт DXF/PDF — кнопка нижче.
        </p>
      )}

      <details className="text-xs text-zinc-500">
        <summary className="cursor-pointer">Параметри (JSON)</summary>
        <pre
          data-testid="params-preview"
          className="mt-2 overflow-x-auto rounded-md border border-zinc-800 bg-zinc-950 p-3 text-zinc-300"
        >
          {JSON.stringify(value, null, 2)}
        </pre>
      </details>
    </form>
  );
}
