"use client";

import { validateProfile } from "@flatcraft/cad-engine";
import { ZBracketParametersSchema, type ZBracketParameters } from "@flatcraft/types";
import { AutoForm, zodIssuesToFieldErrors, type FieldDescriptor } from "@flatcraft/ui";
import { useMemo } from "react";

import { bendMatrixIssues } from "../lib/bend-matrix";

interface ZBracketEditorProps {
  readonly value: ZBracketParameters;
  readonly onChange: (next: ZBracketParameters) => void;
  /** Матеріал/товщина з Studio — потрібні для матричної валідації гибу. */
  readonly materialCode: string;
  readonly thicknessMm: number;
}

const IS_DEV = process.env.NEXT_PUBLIC_ENV === "dev";

// Hotfix 2.10.e: bends (напрями 2 гибів, дефолт 'down') у моделі, приховано від UI.
const FORM_SCHEMA = ZBracketParametersSchema.omit({ bends: true });

function renderField(descriptor: FieldDescriptor, value: unknown): React.ReactNode | null {
  if (descriptor.name === "holes") {
    const count = Array.isArray(value) ? value.length : 0;
    return (
      <p data-testid={`auto-form-holes-placeholder`} className="text-fg-muted text-xs">
        Отвори ({count}) — редактор у Phase 2.7.
      </p>
    );
  }
  return undefined;
}

export function ZBracketEditor({
  value,
  onChange,
  materialCode,
  thicknessMm,
}: ZBracketEditorProps) {
  const validation = useMemo(() => ZBracketParametersSchema.safeParse(value), [value]);
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
        template_slug: "z_bracket",
        parameters: value,
        material_code: materialCode,
        thickness_mm: thicknessMm,
      }),
    [value, materialCode, thicknessMm],
  );

  // Hotfix 2.9.f (ADR-026): геометрична валідність профілю (полиці/offset).
  const profileIssues = useMemo(
    () => validateProfile({ templateSlug: "z_bracket", parameters: value, thicknessMm }),
    [value, thicknessMm],
  );

  const allErrors = useMemo(
    () => [
      ...profileIssues.map((i) => i.message),
      ...matrixIssues.map((e) => e.message ?? e.code),
      ...zodErrors,
    ],
    [profileIssues, matrixIssues, zodErrors],
  );

  return (
    <form
      data-testid="z-bracket-editor"
      className="flex flex-col gap-4"
      onSubmit={(e) => e.preventDefault()}
    >
      <AutoForm
        schema={FORM_SCHEMA}
        value={value as unknown as Record<string, unknown>}
        onChange={(next) => onChange(next as unknown as ZBracketParameters)}
        errors={fieldErrors}
        renderField={renderField}
      />

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
