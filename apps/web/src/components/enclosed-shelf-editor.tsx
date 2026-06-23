"use client";

import { EnclosedShelfParametersSchema, type EnclosedShelfParameters } from "@flatcraft/types";
import { AutoForm, zodIssuesToFieldErrors } from "@flatcraft/ui";
import { useMemo } from "react";

import { bendMatrixIssues } from "../lib/bend-matrix";

interface EnclosedShelfEditorProps {
  readonly value: EnclosedShelfParameters;
  readonly onChange: (next: EnclosedShelfParameters) => void;
  /** Матеріал/товщина з Studio — потрібні для матричної валідації гибу. */
  readonly materialCode: string;
  readonly thicknessMm: number;
  /** Phase 3.0 PR 4: visible_fields для product-mode. */
  readonly visibleFields?: readonly string[];
}

const IS_DEV = process.env.NEXT_PUBLIC_ENV === "dev";

// PR 7d: showing лише основні розміри + параметри гибу. `bends` (масив напрямів),
// `side_perforation` (nested object) і `stiffening_rib` (nested object) — за
// межами generic AutoForm; конфігурація у наступних phase-ах. Default state з
// ENCLOSED_SHELF_DEFAULT_PARAMETERS гарантує: side_perforation=null,
// stiffening_rib=null, bends=[up,up,up,up].
const FORM_SCHEMA = EnclosedShelfParametersSchema.omit({
  bends: true,
  side_perforation: true,
  stiffening_rib: true,
});

export function EnclosedShelfEditor({
  value,
  onChange,
  materialCode,
  thicknessMm,
  visibleFields,
}: EnclosedShelfEditorProps) {
  const validation = useMemo(() => EnclosedShelfParametersSchema.safeParse(value), [value]);
  const fieldErrors = useMemo(
    () => (validation.success ? {} : zodIssuesToFieldErrors(validation.error.issues)),
    [validation],
  );
  const zodErrors = useMemo(() => {
    if (validation.success) return [] as string[];
    return validation.error.issues.map((i) => `${i.path.join(".") || "form"}: ${i.message}`);
  }, [validation]);

  const matrixIssues = useMemo(
    () =>
      bendMatrixIssues({
        template_slug: "enclosed_shelf",
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

  const bendCount = value.stiffening_rib ? 4 : 3;
  const summary = value.side_perforation
    ? `${bendCount} гиби UP · перфорація боковин ${value.side_perforation.hole_size_mm}мм`
    : `${bendCount} гиби UP · без перфорації`;

  return (
    <form
      data-testid="enclosed-shelf-editor"
      className="flex flex-col gap-4"
      onSubmit={(e) => e.preventDefault()}
    >
      <AutoForm
        schema={FORM_SCHEMA}
        value={value as unknown as Record<string, unknown>}
        onChange={(next) => onChange({ ...value, ...next } as unknown as EnclosedShelfParameters)}
        errors={fieldErrors}
        {...(visibleFields ? { visibleFields } : {})}
      />

      <p className="text-fg-muted text-xs" data-testid="enclosed-shelf-summary">
        {summary}
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
