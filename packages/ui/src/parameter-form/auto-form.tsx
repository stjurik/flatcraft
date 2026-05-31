"use client";

import { useMemo } from "react";
import type { z } from "zod";

import { introspectSchema, type FieldDescriptor } from "./schema-inspector.js";
import type { FieldErrors } from "./zod-errors.js";

export interface AutoFormLabels {
  readonly [fieldName: string]: string;
}

export interface AutoFormGroups {
  /** Назва групи для поля (override до Zod `.describe()`). */
  readonly [fieldName: string]: string;
}

export interface AutoFormProps<TValues extends Record<string, unknown>> {
  readonly schema: z.ZodObject<z.ZodRawShape>;
  readonly value: TValues;
  readonly onChange: (next: TValues) => void;
  /** Лейбли українською; ключ — name з Zod-схеми. Fallback — name. */
  readonly labels?: AutoFormLabels;
  /** Помилки на полях; ключ — name. Поля з помилками виділяються червоним. */
  readonly errors?: FieldErrors;
  /** Override для рендеру конкретного поля (наприклад, holes-editor). */
  readonly renderField?: (descriptor: FieldDescriptor, value: unknown) => React.ReactNode | null;
  /**
   * Override назв груп per-field (fallback якщо у Zod `.describe()` group
   * не вказано). Поля без group попадають у дефолтну «Загальне».
   */
  readonly groups?: AutoFormGroups;
  /** Як називати дефолтну групу для незгрупованих полів. Default — «Загальне». */
  readonly defaultGroupLabel?: string;
}

// Phase 2.11 tokens — лише warm-industrial, без zinc/red hardcoded.
const INPUT_BASE =
  "min-h-tap w-full rounded-sm border border-border bg-surface-sunken px-3 py-2 text-sm text-fg " +
  "placeholder:text-fg-subtle " +
  "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:border-border-strong " +
  "disabled:cursor-not-allowed disabled:bg-surface-muted disabled:text-fg-subtle " +
  "transition-colors duration-fast ease-out";
const INPUT_INVALID = "border-danger ring-2 ring-danger/20";

const FIELDSET_CLASS = "mb-6 rounded-md border border-border bg-bg-elevated p-4 space-y-3";
const LEGEND_CLASS = "px-2 text-base font-semibold text-fg";

/**
 * Generic auto-form: будує controlled-форму з Zod-схеми. Phase 2.12
 * рендерить поля згрупованими у `<fieldset>` за метаданими з Zod
 * `.describe("group:G|label:L")` (див. ADR-017). Дефолтна група
 * «Загальне» — внизу.
 *
 * Валідація — зовнішня (Studio контейнер передає `errors`). AutoForm
 * лише підсвічує поля з помилками (border-danger + aria-invalid) і рендерить
 * inline-message під полем.
 */
export function AutoForm<TValues extends Record<string, unknown>>({
  schema,
  value,
  onChange,
  labels,
  errors,
  renderField,
  groups,
  defaultGroupLabel = "Загальне",
}: AutoFormProps<TValues>) {
  const descriptors = useMemo(() => introspectSchema(schema), [schema]);

  const setField = (name: string, next: unknown) => {
    onChange({ ...value, [name]: next } as TValues);
  };

  // Групуємо у Map зі стабільним порядком появи першого поля кожної групи;
  // дефолтна група завжди йде останньою, незалежно від моменту появи.
  const grouped = useMemo(() => {
    const map = new Map<string, FieldDescriptor[]>();
    for (const d of descriptors) {
      const groupName = groups?.[d.name] ?? d.group ?? defaultGroupLabel;
      const bucket = map.get(groupName);
      if (bucket) bucket.push(d);
      else map.set(groupName, [d]);
    }
    // Перенесемо defaultGroupLabel у кінець, якщо існує.
    if (map.has(defaultGroupLabel) && map.size > 1) {
      const tail = map.get(defaultGroupLabel)!;
      map.delete(defaultGroupLabel);
      map.set(defaultGroupLabel, tail);
    }
    return map;
  }, [descriptors, groups, defaultGroupLabel]);

  return (
    <div data-testid="auto-form" className="flex flex-col">
      {Array.from(grouped.entries()).map(([groupName, fields]) => (
        <fieldset
          key={groupName}
          data-testid={`auto-form-group-${groupName}`}
          className={FIELDSET_CLASS}
        >
          <legend className={LEGEND_CLASS}>{groupName}</legend>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            {fields.map((d) => {
              const fieldValue = value[d.name];
              const fieldErrors = errors?.[d.name] ?? [];
              const override = renderField?.(d, fieldValue);
              if (override !== undefined) {
                return (
                  <div key={d.name} className="sm:col-span-2">
                    {override}
                  </div>
                );
              }
              const label = labels?.[d.name] ?? d.label ?? d.name;
              if (d.kind === "number") {
                return (
                  <NumberInput
                    key={d.name}
                    descriptor={d}
                    label={label}
                    value={typeof fieldValue === "number" ? fieldValue : 0}
                    onChange={(v) => setField(d.name, v)}
                    errors={fieldErrors}
                  />
                );
              }
              if (d.kind === "enum") {
                return (
                  <EnumSelect
                    key={d.name}
                    descriptor={d}
                    label={label}
                    value={fieldValue as number | string}
                    onChange={(v) => setField(d.name, v)}
                    errors={fieldErrors}
                  />
                );
              }
              if (d.kind === "literal") {
                return <LiteralDisplay key={d.name} descriptor={d} label={label} />;
              }
              return (
                <p
                  key={d.name}
                  data-testid={`auto-form-unsupported-${d.name}`}
                  className="text-fg-muted text-xs"
                >
                  {label}: {d.reason}
                </p>
              );
            })}
          </div>
        </fieldset>
      ))}
    </div>
  );
}

interface FieldShellProps {
  readonly name: string;
  readonly label: string;
  readonly errors: ReadonlyArray<string>;
  readonly children: React.ReactNode;
}

function FieldShell({ name, label, errors, children }: FieldShellProps) {
  const hasError = errors.length > 0;
  return (
    <label
      className="flex flex-col gap-1.5 text-sm"
      htmlFor={`param-${name}`}
      data-testid={`field-${name}`}
      data-invalid={hasError ? "true" : "false"}
    >
      <span className="text-fg font-medium">{label}</span>
      {children}
      {hasError ? (
        <ul
          id={`param-${name}-error`}
          data-testid={`field-error-${name}`}
          className="text-danger text-xs"
        >
          {errors.map((msg) => (
            <li key={msg}>{msg}</li>
          ))}
        </ul>
      ) : null}
    </label>
  );
}

interface NumberInputProps {
  readonly descriptor: Extract<FieldDescriptor, { kind: "number" }>;
  readonly label: string;
  readonly value: number;
  readonly onChange: (v: number) => void;
  readonly errors: ReadonlyArray<string>;
}

function NumberInput({ descriptor, label, value, onChange, errors }: NumberInputProps) {
  const step = descriptor.step ?? (descriptor.isInt ? 1 : 0.5);
  const id = `param-${descriptor.name}`;
  const hasError = errors.length > 0;
  return (
    <FieldShell name={descriptor.name} label={label} errors={errors}>
      <input
        id={id}
        data-testid={id}
        type="number"
        value={value}
        min={descriptor.min}
        max={descriptor.max}
        step={step}
        aria-invalid={hasError}
        aria-describedby={hasError ? `${id}-error` : undefined}
        onChange={(e) => onChange(Number(e.target.value))}
        className={`${INPUT_BASE} ${hasError ? INPUT_INVALID : ""}`}
      />
    </FieldShell>
  );
}

interface EnumSelectProps {
  readonly descriptor: Extract<FieldDescriptor, { kind: "enum" }>;
  readonly label: string;
  readonly value: number | string;
  readonly onChange: (v: number | string) => void;
  readonly errors: ReadonlyArray<string>;
}

function EnumSelect({ descriptor, label, value, onChange, errors }: EnumSelectProps) {
  const numeric = typeof descriptor.options[0] === "number";
  const id = `param-${descriptor.name}`;
  const hasError = errors.length > 0;
  return (
    <FieldShell name={descriptor.name} label={label} errors={errors}>
      <select
        id={id}
        data-testid={id}
        value={String(value)}
        aria-invalid={hasError}
        aria-describedby={hasError ? `${id}-error` : undefined}
        onChange={(e) => onChange(numeric ? Number(e.target.value) : e.target.value)}
        className={`${INPUT_BASE} ${hasError ? INPUT_INVALID : ""}`}
      >
        {descriptor.options.map((opt) => (
          <option key={String(opt)} value={String(opt)}>
            {String(opt)}
          </option>
        ))}
      </select>
    </FieldShell>
  );
}

interface LiteralDisplayProps {
  readonly descriptor: Extract<FieldDescriptor, { kind: "literal" }>;
  readonly label: string;
}

function LiteralDisplay({ descriptor, label }: LiteralDisplayProps) {
  return (
    <div className="flex flex-col gap-1.5 text-sm" data-testid={`literal-${descriptor.name}`}>
      <span className="text-fg font-medium">{label}</span>
      <span className="min-h-tap border-border bg-surface-muted text-fg-subtle rounded-sm border px-3 py-2">
        {String(descriptor.value)}
      </span>
    </div>
  );
}
