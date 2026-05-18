"use client";

import {
  WallShelfParametersBaseSchema,
  WallShelfParametersSchema,
  type WallShelfParameters,
} from "@flatcraft/types";
import { AutoForm, zodIssuesToFieldErrors, type AutoFormLabels } from "@flatcraft/ui";
import { useMemo } from "react";

interface WallShelfEditorProps {
  readonly value: WallShelfParameters;
  readonly onChange: (next: WallShelfParameters) => void;
}

const LABELS: AutoFormLabels = {
  back_height_mm: "Висота back (стінка), мм",
  shelf_depth_mm: "Глибина полиці, мм",
  front_lip_mm: "Висота front lip (0 = без lip), мм",
  bend_radius_mm: "Внутрішній радіус гиба, мм",
  bend_angle_deg: "Кут гиба, °",
  width_mm: "Довжина полиці (= гибу), мм",
  mount_hole_diameter_mm: "Діаметр mounting holes, мм",
  mount_hole_rows: "Рядів отворів (вздовж ширини)",
  mount_hole_cols: "Колонок отворів (по back)",
  mount_hole_margin_mm: "Відступ від країв back, мм",
};

export function WallShelfEditor({ value, onChange }: WallShelfEditorProps) {
  const validation = useMemo(() => WallShelfParametersSchema.safeParse(value), [value]);
  const fieldErrors = useMemo(
    () => (validation.success ? {} : zodIssuesToFieldErrors(validation.error.issues)),
    [validation],
  );
  const allErrors = useMemo(() => {
    if (validation.success) return [] as string[];
    return validation.error.issues.map((i) => `${i.path.join(".") || "form"}: ${i.message}`);
  }, [validation]);

  const totalHoles = value.mount_hole_rows * value.mount_hole_cols;
  const lipNote =
    value.front_lip_mm === 0
      ? "1 гиб (без front lip)"
      : `2 гиби (front lip ${value.front_lip_mm} мм)`;

  return (
    <form
      data-testid="wall-shelf-editor"
      className="flex flex-col gap-4"
      onSubmit={(e) => e.preventDefault()}
    >
      <AutoForm
        schema={WallShelfParametersBaseSchema}
        value={value as unknown as Record<string, unknown>}
        onChange={(next) => onChange(next as unknown as WallShelfParameters)}
        labels={LABELS}
        errors={fieldErrors}
      />

      <p className="text-xs text-zinc-500" data-testid="shelf-summary">
        {lipNote} · {totalHoles} mounting holes Ø{value.mount_hole_diameter_mm} мм на back.
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
