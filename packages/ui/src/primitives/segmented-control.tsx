import { cva } from "class-variance-authority";

import { cn } from "../lib/cn.js";

/**
 * SegmentedControl — controlled toggle для 2-4 опцій (наприклад,
 * каталог-toggle «Вироби | Деталі», Phase 3.0 ADR-027 Рішення 2).
 *
 * Дизайн: горизонтальний контейнер з border-strong, кожен item — кнопка
 * з min-h-tap (WCAG 2.5.5 ≥44×44). Активний item має `bg-primary`
 * tone'у та aria-pressed=true для screen-readers.
 *
 * НЕ ВЕДЕ роутингу — це чистий controlled primitive. Маршрутизація
 * (URL query param) — у консумерах.
 */

export interface SegmentedControlOption<TValue extends string = string> {
  readonly value: TValue;
  readonly label: string;
  /** Лейбл для screen-reader (якщо `label` коротка піктограма-текст). */
  readonly ariaLabel?: string;
  /** Опційна іконка (lucide-react) ліворуч від label'у. */
  readonly icon?: React.ReactNode;
}

export interface SegmentedControlProps<TValue extends string = string> {
  readonly value: TValue;
  readonly onValueChange: (value: TValue) => void;
  readonly options: ReadonlyArray<SegmentedControlOption<TValue>>;
  /** Лейбл групи для accessibility (aria-label на контейнер). */
  readonly ariaLabel: string;
  readonly className?: string;
  readonly testId?: string;
}

const item = cva(
  [
    "inline-flex items-center justify-center gap-2 whitespace-nowrap",
    "min-h-tap min-w-tap px-4 py-2 rounded-sm",
    "text-sm font-semibold transition-colors duration-fast ease-out",
    "focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2",
    "focus-visible:outline-ring/60",
    "disabled:pointer-events-none disabled:opacity-50",
  ],
  {
    variants: {
      active: {
        true: "bg-primary text-primary-foreground hover:bg-primary-hover",
        false: "text-fg hover:bg-surface-muted",
      },
    },
    defaultVariants: { active: false },
  },
);

export function SegmentedControl<TValue extends string = string>({
  value,
  onValueChange,
  options,
  ariaLabel,
  className,
  testId,
}: SegmentedControlProps<TValue>) {
  return (
    <div
      role="group"
      aria-label={ariaLabel}
      data-testid={testId}
      className={cn(
        "border-border-strong bg-bg inline-flex items-center gap-1 rounded-md border p-1",
        className,
      )}
    >
      {options.map((opt) => {
        const isActive = opt.value === value;
        return (
          <button
            key={opt.value}
            type="button"
            aria-pressed={isActive}
            aria-label={opt.ariaLabel ?? opt.label}
            data-active={isActive ? "true" : "false"}
            data-value={opt.value}
            data-testid={testId ? `${testId}-item-${opt.value}` : undefined}
            onClick={() => {
              if (!isActive) onValueChange(opt.value);
            }}
            className={item({ active: isActive })}
          >
            {opt.icon}
            <span>{opt.label}</span>
          </button>
        );
      })}
    </div>
  );
}
