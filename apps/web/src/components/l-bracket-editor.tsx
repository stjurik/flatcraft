"use client";

import { LBracketParametersSchema, type LBracketParameters } from "@flatcraft/types";
import { useMemo, useState } from "react";

interface LBracketEditorProps {
  readonly initialParameters: LBracketParameters;
}

const ALLOWED_RADII = [1, 2.5, 4, 5] as const;

interface NumberFieldProps {
  readonly label: string;
  readonly id: keyof LBracketParameters;
  readonly value: number;
  readonly min: number;
  readonly max: number;
  readonly step: number;
  readonly onChange: (v: number) => void;
}

function NumberField({ label, id, value, min, max, step, onChange }: NumberFieldProps) {
  return (
    <label className="flex flex-col gap-1 text-sm" htmlFor={`param-${id}`}>
      <span className="text-zinc-400">{label}</span>
      <input
        id={`param-${id}`}
        data-testid={`param-${id}`}
        type="number"
        value={value}
        min={min}
        max={max}
        step={step}
        onChange={(e) => onChange(Number(e.target.value))}
        className="rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-zinc-100 focus:border-zinc-600 focus:outline-none"
      />
    </label>
  );
}

export function LBracketEditor({ initialParameters }: LBracketEditorProps) {
  const [params, setParams] = useState<LBracketParameters>(initialParameters);

  // Live-валідація: рендеримо помилки Zod (Phase 2.5 розширить — підсвічення
  // конкретних полів + tooltip-и; зараз — компактний список).
  const validation = useMemo(() => LBracketParametersSchema.safeParse(params), [params]);

  const errors: string[] = validation.success
    ? []
    : validation.error.issues.map((i) => `${i.path.join(".") || "form"}: ${i.message}`);

  const set = <K extends keyof LBracketParameters>(key: K, value: LBracketParameters[K]) =>
    setParams((prev) => ({ ...prev, [key]: value }));

  return (
    <form
      data-testid="l-bracket-editor"
      className="flex flex-col gap-4"
      onSubmit={(e) => e.preventDefault()}
    >
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <NumberField
          label="Висота полиці A, мм"
          id="legA_mm"
          value={params.legA_mm}
          min={20}
          max={500}
          step={1}
          onChange={(v) => set("legA_mm", v)}
        />
        <NumberField
          label="Глибина полиці B, мм"
          id="legB_mm"
          value={params.legB_mm}
          min={20}
          max={500}
          step={1}
          onChange={(v) => set("legB_mm", v)}
        />
        <NumberField
          label="Ширина (довжина гиба), мм"
          id="width_mm"
          value={params.width_mm}
          min={20}
          max={3000}
          step={1}
          onChange={(v) => set("width_mm", v)}
        />

        <label className="flex flex-col gap-1 text-sm" htmlFor="param-bend_radius_mm">
          <span className="text-zinc-400">Внутрішній радіус гиба, мм</span>
          <select
            id="param-bend_radius_mm"
            data-testid="param-bend_radius_mm"
            value={params.bend_radius_mm}
            onChange={(e) =>
              set("bend_radius_mm", Number(e.target.value) as LBracketParameters["bend_radius_mm"])
            }
            className="rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-zinc-100 focus:border-zinc-600 focus:outline-none"
          >
            {ALLOWED_RADII.map((r) => (
              <option key={r} value={r}>
                {r}
              </option>
            ))}
          </select>
        </label>
      </div>

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
          {JSON.stringify(params, null, 2)}
        </pre>
      </details>
    </form>
  );
}
