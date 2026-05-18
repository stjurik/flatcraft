"use client";

import { ZBracketParametersSchema, type ZBracketParameters } from "@flatcraft/types";
import {
  AutoForm,
  zodIssuesToFieldErrors,
  type AutoFormLabels,
  type FieldDescriptor,
} from "@flatcraft/ui";
import { useMemo } from "react";

interface ZBracketEditorProps {
  readonly value: ZBracketParameters;
  readonly onChange: (next: ZBracketParameters) => void;
}

const LABELS: AutoFormLabels = {
  top_flange_mm: "Верхня полиця, мм",
  bottom_flange_mm: "Нижня полиця, мм",
  offset_mm: "Offset (вертикальна секція), мм",
  bend_radius_mm: "Внутрішній радіус гиба, мм",
  bend_angle_deg: "Кут гиба, °",
  width_mm: "Ширина (довжина гиба), мм",
  holes: "Отвори",
};

function renderField(descriptor: FieldDescriptor, value: unknown): React.ReactNode | null {
  if (descriptor.name === "holes") {
    const count = Array.isArray(value) ? value.length : 0;
    return (
      <p data-testid={`auto-form-holes-placeholder`} className="text-xs text-zinc-500">
        Отвори ({count}) — редактор у Phase 2.7.
      </p>
    );
  }
  return undefined;
}

export function ZBracketEditor({ value, onChange }: ZBracketEditorProps) {
  const validation = useMemo(() => ZBracketParametersSchema.safeParse(value), [value]);
  const fieldErrors = useMemo(
    () => (validation.success ? {} : zodIssuesToFieldErrors(validation.error.issues)),
    [validation],
  );
  const allErrors = useMemo(() => {
    if (validation.success) return [] as string[];
    return validation.error.issues.map((i) => `${i.path.join(".") || "form"}: ${i.message}`);
  }, [validation]);

  return (
    <form
      data-testid="z-bracket-editor"
      className="flex flex-col gap-4"
      onSubmit={(e) => e.preventDefault()}
    >
      <AutoForm
        schema={ZBracketParametersSchema}
        value={value as unknown as Record<string, unknown>}
        onChange={(next) => onChange(next as unknown as ZBracketParameters)}
        labels={LABELS}
        errors={fieldErrors}
        renderField={renderField}
      />

      <p className="text-xs text-zinc-500" data-testid="bend-angle-info">
        Z-кронштейн має 2 гиби по 90°. Інші кути — post-launch.
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
