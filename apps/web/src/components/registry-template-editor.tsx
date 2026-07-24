"use client";

import type { TemplateDefinition } from "@flatcraft/templates";
import { AutoForm, SegmentedControl, zodIssuesToFieldErrors } from "@flatcraft/ui";
import { useMemo } from "react";
import type { z } from "zod";

import { bendMatrixIssues } from "../lib/bend-matrix";

const IS_DEV = process.env.NEXT_PUBLIC_ENV === "dev";

interface RegistryTemplateEditorProps<Params extends Record<string, unknown>> {
  readonly def: TemplateDefinition<Params>;
  readonly value: Params;
  readonly onChange: (next: Params) => void;
  readonly thicknessMm: number;
  /**
   * Потрібен лише для `def.capabilities.includes("bends")` (матричний банер,
   * паритет з наявними `*-editor.tsx` типу `corner-angle-editor.tsx` —
   * Hotfix 2.9.c). Undefined (прямі unit-тести без `TemplateStudio`) →
   * матрична валідація тихо пропускається — той самий наслідок, що й раніше
   * для perforated_panel (не входить у `bend-matrix-validation.spec.ts`
   * `TEMPLATES_WITH_BENDS`, задокументовано незмінно).
   */
  readonly materialCode?: string;
  /** Product-mode allowlist (ADR-027 Рішення 4) — undefined у part-mode. */
  readonly visibleFields?: readonly string[];
}

/**
 * Generic editor (Run 7 Master Registry Track, Етап 2) — керується
 * `TemplateDefinition` замість per-slug `*-editor.tsx`. Реплікує наявний
 * паттерн (`perforated-panel-editor.tsx` та ін.): Zod-помилки на полях +
 * `def.validators`-банер + `extraControls` (SegmentedControl над формою,
 * summary — під нею) + AutoForm для решти полів.
 *
 * `def.validators`-issues тепер показуються у банері для ВСІХ шаблонів
 * уніфіковано (раніше `perforated-panel-editor.tsx` показував лише
 * perforation-issues, profile-issues — тихо блокували export-кнопку через
 * `TemplateStudio`) — задокументоване покращення при генерифікації, не
 * regressed поведінка (жоден e2e не перевіряв відсутність цих повідомлень).
 */
export function RegistryTemplateEditor<Params extends Record<string, unknown>>({
  def,
  value,
  onChange,
  thicknessMm,
  materialCode,
  visibleFields,
}: RegistryTemplateEditorProps<Params>) {
  const testId = `${toKebab(def.slug)}-editor`;
  // ADR-033 §2 ALT-C дозволяє refined-схеми (ZodEffects) у реєстрі; AutoForm
  // вимагає ZodObject. Для наявних (Етап 2) shape'ів це завжди plain ZodObject
  // — рефайнед-схема (wall_shelf) обробляється в її власній міграційній PR.
  const schema = def.schema as unknown as z.ZodObject<z.ZodRawShape>;

  const validation = useMemo(() => schema.safeParse(value), [schema, value]);
  const fieldErrors = useMemo(
    () => (validation.success ? {} : zodIssuesToFieldErrors(validation.error.issues)),
    [validation],
  );
  const zodErrorStrings = useMemo(() => {
    if (validation.success) return [] as string[];
    return validation.error.issues.map((i) => `${i.path.join(".") || "form"}: ${i.message}`);
  }, [validation]);

  const defIssues = useMemo(
    () => def.validators.flatMap((validator) => validator(value, thicknessMm)),
    [def.validators, value, thicknessMm],
  );

  const matrixIssues = useMemo(() => {
    if (!materialCode || !def.capabilities.includes("bends")) return [];
    return bendMatrixIssues({
      template_slug: def.slug,
      parameters: value,
      material_code: materialCode,
      thickness_mm: thicknessMm,
      // Params — generic; ExportRequest очікує union конкретних per-slug
      // типів. Каст безпечний — `def.slug` і `value` йдуть з одного
      // TemplateDefinition-запису (той самий паттерн, що й TemplateStudio).
    } as unknown as Parameters<typeof bendMatrixIssues>[0]);
  }, [materialCode, def.capabilities, def.slug, value, thicknessMm]);

  const allErrors = useMemo(
    () => [
      ...matrixIssues.map((issue) => issue.message ?? issue.code),
      ...defIssues.map((issue) => issue.message ?? issue.code),
      ...zodErrorStrings,
    ],
    [matrixIssues, defIssues, zodErrorStrings],
  );

  const extraControls = def.ui.extraControls ?? [];
  const segmentedFields = useMemo(
    () => new Set(extraControls.filter((c) => c.kind === "segmented").map((c) => c.field)),
    [extraControls],
  );
  // part-mode: усі поля схеми, крім тих, якими керують segmented-контроли.
  // product-mode: allowlist продукту (segmented-контроли рендеряться завжди,
  // незалежно від visibleFields — паритет з наявним perforated-panel-editor).
  const effectiveVisibleFields = useMemo(
    () => visibleFields ?? Object.keys(schema.shape).filter((f) => !segmentedFields.has(f)),
    [visibleFields, schema, segmentedFields],
  );

  return (
    <form data-testid={testId} className="flex flex-col gap-4" onSubmit={(e) => e.preventDefault()}>
      {extraControls
        .filter((c) => c.kind === "segmented")
        .map((c) => (
          <div key={c.field} className="flex flex-col gap-2">
            <span className="text-fg text-sm font-medium">{c.label}</span>
            <SegmentedControl
              value={String(value[c.field])}
              onValueChange={(next) => onChange({ ...value, [c.field]: next })}
              options={c.options}
              ariaLabel={c.label}
              testId={c.testId}
            />
          </div>
        ))}

      <AutoForm
        schema={schema}
        value={value}
        onChange={onChange}
        errors={fieldErrors}
        visibleFields={effectiveVisibleFields}
      />

      {extraControls
        .filter((c) => c.kind === "summary")
        .map((c) => (
          <p key={c.testId} className="text-fg-muted text-xs" data-testid={c.testId}>
            {c.render(value)}
          </p>
        ))}

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

function toKebab(slug: string): string {
  return slug.replaceAll("_", "-");
}
