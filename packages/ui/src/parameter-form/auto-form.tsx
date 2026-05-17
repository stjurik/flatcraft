"use client";

import { useMemo } from "react";
import type { z } from "zod";

import { introspectSchema, type FieldDescriptor } from "./schema-inspector.js";
import type { FieldErrors } from "./zod-errors.js";

export interface AutoFormLabels {
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
  /** Перевизначити рендер для конкретного поля (наприклад, holes-editor). */
  readonly renderField?: (descriptor: FieldDescriptor, value: unknown) => React.ReactNode | null;
}

const INPUT_BASE = "rounded-md border bg-zinc-950 px-3 py-2 text-zinc-100 focus:outline-none";
const INPUT_OK = "border-zinc-800 focus:border-zinc-600";
const INPUT_ERR = "border-red-700 focus:border-red-500";

/**
 * Generic auto-form: будує controlled-форму з Zod-схеми.
 *
 * Валідація — зовнішня (Studio контейнер передає `errors`). AutoForm
 * лише підсвічує поля з помилками (border-red + aria-invalid) і рендерить
 * inline-message під полем.
 */
export function AutoForm<TValues extends Record<string, unknown>>({
  schema,
  value,
  onChange,
  labels,
  errors,
  renderField,
}: AutoFormProps<TValues>) {
  const descriptors = useMemo(() => introspectSchema(schema), [schema]);

  const setField = (name: string, next: unknown) => {
    onChange({ ...value, [name]: next } as TValues);
  };

  return (
    <div data-testid="auto-form" className="grid grid-cols-1 gap-4 sm:grid-cols-2">
      {descriptors.map((d) => {
        const fieldValue = value[d.name];
        const fieldErrors = errors?.[d.name] ?? [];
        const override = renderField?.(d, fieldValue);
        if (override !== undefined) return <div key={d.name}>{override}</div>;

        const label = labels?.[d.name] ?? d.name;

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
            className="text-xs text-zinc-500"
          >
            {label}: {d.reason}
          </p>
        );
      })}
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
      className="flex flex-col gap-1 text-sm"
      htmlFor={`param-${name}`}
      data-testid={`field-${name}`}
      data-invalid={hasError ? "true" : "false"}
    >
      <span className={hasError ? "text-red-300" : "text-zinc-400"}>{label}</span>
      {children}
      {hasError ? (
        <ul
          id={`param-${name}-error`}
          data-testid={`field-error-${name}`}
          className="text-xs text-red-300"
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
        className={`${INPUT_BASE} ${hasError ? INPUT_ERR : INPUT_OK}`}
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
        className={`${INPUT_BASE} ${hasError ? INPUT_ERR : INPUT_OK}`}
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
    <div className="flex flex-col gap-1 text-sm" data-testid={`literal-${descriptor.name}`}>
      <span className="text-zinc-400">{label}</span>
      <span className="rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-zinc-500">
        {String(descriptor.value)}
      </span>
    </div>
  );
}
