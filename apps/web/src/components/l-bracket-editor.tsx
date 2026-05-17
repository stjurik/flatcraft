"use client";

import { LBracketParametersSchema, type LBracketParameters } from "@flatcraft/types";
import { AutoForm, type AutoFormLabels, type FieldDescriptor } from "@flatcraft/ui";
import { useMemo } from "react";

interface LBracketEditorProps {
  readonly value: LBracketParameters;
  readonly onChange: (next: LBracketParameters) => void;
}

const LABELS: AutoFormLabels = {
  legA_mm: "Висота полиці A, мм",
  legB_mm: "Глибина полиці B, мм",
  bend_radius_mm: "Внутрішній радіус гиба, мм",
  bend_angle_deg: "Кут гиба, °",
  width_mm: "Ширина (довжина гиба), мм",
  holes: "Отвори",
};

/**
 * Holes (z.array(...)) поки рендериться окремим editor'ом — Phase 2.5.
 * Поки приховуємо як info-rebra: "0 отворів — додамо у наступній фазі".
 */
function renderField(descriptor: FieldDescriptor, value: unknown): React.ReactNode | null {
  if (descriptor.name === "holes") {
    const count = Array.isArray(value) ? value.length : 0;
    return (
      <p data-testid={`auto-form-holes-placeholder`} className="text-xs text-zinc-500">
        Отвори ({count}) — редактор у Phase 2.5.
      </p>
    );
  }
  return undefined;
}

export function LBracketEditor({ value, onChange }: LBracketEditorProps) {
  // Live-валідація проти оригінальної схеми (AutoForm не валідує — це
  // контракт: він рендерить, перевіряє Studio контейнер).
  const validation = useMemo(() => LBracketParametersSchema.safeParse(value), [value]);

  const errors: string[] = validation.success
    ? []
    : validation.error.issues.map((i) => `${i.path.join(".") || "form"}: ${i.message}`);

  return (
    <form
      data-testid="l-bracket-editor"
      className="flex flex-col gap-4"
      onSubmit={(e) => e.preventDefault()}
    >
      <AutoForm
        schema={LBracketParametersSchema}
        value={value as unknown as Record<string, unknown>}
        onChange={(next) => onChange(next as unknown as LBracketParameters)}
        labels={LABELS}
        renderField={renderField}
      />

      <p className="text-xs text-zinc-500" data-testid="bend-angle-info">
        Кут гиба — 90° (MVP). Інші кути додамо post-launch.
      </p>

      {errors.length > 0 ? (
        <ul
          data-testid="validation-errors"
          className="rounded-lg border border-red-900/50 bg-red-950/30 p-3 text-sm text-red-300"
        >
          {errors.map((msg) => (
            <li key={msg}>{msg}</li>
          ))}
        </ul>
      ) : (
        <p
          data-testid="validation-ok"
          className="rounded-lg border border-emerald-900/50 bg-emerald-950/30 p-3 text-sm text-emerald-300"
        >
          Параметри валідні. Експорт DXF/PDF — Phase 2.7.
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
