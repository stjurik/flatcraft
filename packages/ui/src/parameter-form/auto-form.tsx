"use client";

import { useMemo } from "react";
import type { z } from "zod";

import { introspectSchema, type FieldDescriptor } from "./schema-inspector.js";

export interface AutoFormLabels {
  readonly [fieldName: string]: string;
}

export interface AutoFormProps<TValues extends Record<string, unknown>> {
  readonly schema: z.ZodObject<z.ZodRawShape>;
  readonly value: TValues;
  readonly onChange: (next: TValues) => void;
  /** Лейбли українською; ключ — name з Zod-схеми. Fallback — name. */
  readonly labels?: AutoFormLabels;
  /** Перевизначити рендер для конкретного поля (наприклад, holes-editor). */
  readonly renderField?: (descriptor: FieldDescriptor, value: unknown) => React.ReactNode | null;
}

/**
 * Generic auto-form: будує controlled-форму з Zod-схеми.
 *
 * - Підтримує NumberField (input type="number"), EnumField (select).
 * - LiteralField — read-only показ (значення фіксоване).
 * - UnsupportedField — renderField fallback або hint.
 *
 * Валідацію свідомо НЕ робимо тут — споживач передає валідне value або
 * показує помилки зовні. Це дозволяє Studio контейнеру (Phase 2.2c)
 * робити live-Zod-validation на агрегованому рівні.
 */
export function AutoForm<TValues extends Record<string, unknown>>({
  schema,
  value,
  onChange,
  labels,
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

interface NumberInputProps {
  readonly descriptor: Extract<FieldDescriptor, { kind: "number" }>;
  readonly label: string;
  readonly value: number;
  readonly onChange: (v: number) => void;
}

function NumberInput({ descriptor, label, value, onChange }: NumberInputProps) {
  const step = descriptor.step ?? (descriptor.isInt ? 1 : 0.5);
  return (
    <label className="flex flex-col gap-1 text-sm" htmlFor={`param-${descriptor.name}`}>
      <span className="text-zinc-400">{label}</span>
      <input
        id={`param-${descriptor.name}`}
        data-testid={`param-${descriptor.name}`}
        type="number"
        value={value}
        min={descriptor.min}
        max={descriptor.max}
        step={step}
        onChange={(e) => onChange(Number(e.target.value))}
        className="rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-zinc-100 focus:border-zinc-600 focus:outline-none"
      />
    </label>
  );
}

interface EnumSelectProps {
  readonly descriptor: Extract<FieldDescriptor, { kind: "enum" }>;
  readonly label: string;
  readonly value: number | string;
  readonly onChange: (v: number | string) => void;
}

function EnumSelect({ descriptor, label, value, onChange }: EnumSelectProps) {
  const numeric = typeof descriptor.options[0] === "number";
  return (
    <label className="flex flex-col gap-1 text-sm" htmlFor={`param-${descriptor.name}`}>
      <span className="text-zinc-400">{label}</span>
      <select
        id={`param-${descriptor.name}`}
        data-testid={`param-${descriptor.name}`}
        value={String(value)}
        onChange={(e) => onChange(numeric ? Number(e.target.value) : e.target.value)}
        className="rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-zinc-100 focus:border-zinc-600 focus:outline-none"
      >
        {descriptor.options.map((opt) => (
          <option key={String(opt)} value={String(opt)}>
            {String(opt)}
          </option>
        ))}
      </select>
    </label>
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
