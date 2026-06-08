"use client";

import {
  WallShelfParametersBaseSchema,
  WallShelfParametersSchema,
  type WallShelfParameters,
} from "@flatcraft/types";
import { AutoForm, zodIssuesToFieldErrors } from "@flatcraft/ui";
import { useMemo } from "react";

import { bendMatrixIssues } from "../lib/bend-matrix";

interface WallShelfEditorProps {
  readonly value: WallShelfParameters;
  readonly onChange: (next: WallShelfParameters) => void;
  /** Матеріал/товщина з Studio — потрібні для матричної валідації гибу. */
  readonly materialCode: string;
  readonly thicknessMm: number;
}

const IS_DEV = process.env.NEXT_PUBLIC_ENV === "dev";

// Hotfix 2.10.e: bends (напрями 1-2 гибів, дефолт 'down') у моделі, приховано від UI.
const FORM_SCHEMA = WallShelfParametersBaseSchema.omit({ bends: true });

export function WallShelfEditor({
  value,
  onChange,
  materialCode,
  thicknessMm,
}: WallShelfEditorProps) {
  const validation = useMemo(() => WallShelfParametersSchema.safeParse(value), [value]);
  const fieldErrors = useMemo(
    () => (validation.success ? {} : zodIssuesToFieldErrors(validation.error.issues)),
    [validation],
  );
  const zodErrors = useMemo(() => {
    if (validation.success) return [] as string[];
    return validation.error.issues.map((i) => `${i.path.join(".") || "form"}: ${i.message}`);
  }, [validation]);

  // Hotfix 2.9.c: матрична валідація (матеріал, товщина, радіус) — той самий
  // валідатор, що й серверний gate (ADR-022).
  const matrixIssues = useMemo(
    () =>
      bendMatrixIssues({
        template_slug: "wall_shelf",
        parameters: value,
        material_code: materialCode,
        thickness_mm: thicknessMm,
      }),
    [value, materialCode, thicknessMm],
  );

  const allErrors = useMemo(
    () => [...matrixIssues.map((e) => e.message ?? e.code), ...zodErrors],
    [matrixIssues, zodErrors],
  );

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
        schema={FORM_SCHEMA}
        value={value as unknown as Record<string, unknown>}
        onChange={(next) => onChange(next as unknown as WallShelfParameters)}
        errors={fieldErrors}
      />

      <p className="text-fg-muted text-xs" data-testid="shelf-summary">
        {lipNote} · {totalHoles} mounting holes Ø{value.mount_hole_diameter_mm} мм на back.
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
