"use client";

import { validateProfile } from "@flatcraft/cad-engine";
import { LBracketParametersSchema, type LBracketParameters } from "@flatcraft/types";
import { AutoForm, zodIssuesToFieldErrors, type FieldDescriptor } from "@flatcraft/ui";
import { useMemo } from "react";

import { bendMatrixIssues } from "../lib/bend-matrix";

interface LBracketEditorProps {
  readonly value: LBracketParameters;
  readonly onChange: (next: LBracketParameters) => void;
  /** Матеріал/товщина з Studio — потрібні для матричної валідації гибу. */
  readonly materialCode: string;
  readonly thicknessMm: number;
}

const IS_DEV = process.env.NEXT_PUBLIC_ENV === "dev";

// Hotfix 2.10.e: bend_direction — частина моделі (дефолт 'down'), але редактор
// його не показує (no UI/UX зміни). Omit лишає поле у state (AutoForm.setField
// робить {...value}), тож напрям доходить до export незмінним.
const FORM_SCHEMA = LBracketParametersSchema.omit({ bend_direction: true });

/**
 * Holes (z.array(...)) поки рендериться окремим editor'ом — Phase 2.7.
 * Поки приховуємо як info-rebra: "0 отворів — додамо у наступній фазі".
 */
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

export function LBracketEditor({
  value,
  onChange,
  materialCode,
  thicknessMm,
}: LBracketEditorProps) {
  // Live-валідація: безперервно парс'имо у Studio, AutoForm підсвічує
  // конкретні поля + summary рендериться знизу як list.
  const validation = useMemo(() => LBracketParametersSchema.safeParse(value), [value]);

  const fieldErrors = useMemo(
    () => (validation.success ? {} : zodIssuesToFieldErrors(validation.error.issues)),
    [validation],
  );

  const zodErrors = useMemo(() => {
    if (validation.success) return [] as string[];
    return validation.error.issues.map((i) => `${i.path.join(".") || "form"}: ${i.message}`);
  }, [validation]);

  // Hotfix 2.9.c: матрична валідація (матеріал, товщина, радіус) проти
  // bend-machine spec — той самий валідатор, що й серверний gate (ADR-022).
  const matrixIssues = useMemo(
    () =>
      bendMatrixIssues({
        template_slug: "l_bracket",
        parameters: value,
        material_code: materialCode,
        thickness_mm: thicknessMm,
      }),
    [value, materialCode, thicknessMm],
  );

  // Hotfix 2.9.f (ADR-026): геометрична валідність профілю (плече >= товщина+радіус).
  const profileIssues = useMemo(
    () => validateProfile({ templateSlug: "l_bracket", parameters: value, thicknessMm }),
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
      data-testid="l-bracket-editor"
      className="flex flex-col gap-4"
      onSubmit={(e) => e.preventDefault()}
    >
      <AutoForm
        schema={FORM_SCHEMA}
        value={value as unknown as Record<string, unknown>}
        onChange={(next) => onChange(next as unknown as LBracketParameters)}
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
