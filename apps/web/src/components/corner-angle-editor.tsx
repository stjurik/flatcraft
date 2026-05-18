"use client";

import { CornerAngleParametersSchema, type CornerAngleParameters } from "@flatcraft/types";
import { AutoForm, zodIssuesToFieldErrors, type AutoFormLabels } from "@flatcraft/ui";
import { useMemo } from "react";

interface CornerAngleEditorProps {
  readonly value: CornerAngleParameters;
  readonly onChange: (next: CornerAngleParameters) => void;
}

const LABELS: AutoFormLabels = {
  legA_mm: "Полиця A (вертикальна), мм",
  legB_mm: "Полиця B (горизонтальна), мм",
  bend_radius_mm: "Внутрішній радіус гиба, мм",
  bend_angle_deg: "Кут гиба, °",
  width_mm: "Ширина (довжина гиба), мм",
  hole_diameter_mm: "Діаметр отворів, мм",
  hole_rows: "Рядів отворів (вздовж ширини)",
  hole_cols: "Колонок отворів (вздовж полиці)",
  hole_margin_mm: "Відступ від країв, мм",
};

export function CornerAngleEditor({ value, onChange }: CornerAngleEditorProps) {
  const validation = useMemo(() => CornerAngleParametersSchema.safeParse(value), [value]);
  const fieldErrors = useMemo(
    () => (validation.success ? {} : zodIssuesToFieldErrors(validation.error.issues)),
    [validation],
  );
  const allErrors = useMemo(() => {
    if (validation.success) return [] as string[];
    return validation.error.issues.map((i) => `${i.path.join(".") || "form"}: ${i.message}`);
  }, [validation]);

  const totalHoles = 2 * value.hole_rows * value.hole_cols;

  return (
    <form
      data-testid="corner-angle-editor"
      className="flex flex-col gap-4"
      onSubmit={(e) => e.preventDefault()}
    >
      <AutoForm
        schema={CornerAngleParametersSchema}
        value={value as unknown as Record<string, unknown>}
        onChange={(next) => onChange(next as unknown as CornerAngleParameters)}
        labels={LABELS}
        errors={fieldErrors}
      />

      <p className="text-xs text-zinc-500" data-testid="hole-grid-summary">
        Grid: {value.hole_rows}×{value.hole_cols} на полицю · всього {totalHoles} отворів Ø
        {value.hole_diameter_mm} мм.
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
