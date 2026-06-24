"use client";

import { validatePerforation } from "@flatcraft/cad-engine";
import { AutoForm, SegmentedControl, zodIssuesToFieldErrors } from "@flatcraft/ui";
import { useMemo } from "react";

import {
  holeSizeFieldFor,
  normalizeVisibleFields,
  schemaForHoleShape,
  slugForHoleShape,
  syncHoleKeys,
  type HoleShape,
  type PerforationParameters,
} from "../lib/perforation-shape";

interface PerforatedPanelEditorProps {
  readonly value: PerforationParameters;
  readonly onChange: (next: PerforationParameters) => void;
  /** Активна форма отвору — керує схемою/лейблами/гліфом. */
  readonly holeShape: HoleShape;
  /** Перемикач форми (піднятий у студію — свопає slug/viewport). */
  readonly onHoleShapeChange: (shape: HoleShape) => void;
  /** Phase 3.0 PR 4: visible_fields для product-mode (нормалізується під форму). */
  readonly visibleFields?: readonly string[];
}

const IS_DEV = process.env.NEXT_PUBLIC_ENV === "dev";

const SHAPE_OPTIONS = [
  { value: "circle" as const, label: "Круглі" },
  { value: "square" as const, label: "Квадратні" },
];

/** Centered grid — мусить збігатися з Python `unfold_perforated_panel*`. */
function computeGrid(p: PerforationParameters): { cols: number; rows: number; total: number } {
  const availX = p.length_mm - 2 * p.margin_mm;
  const availY = p.width_mm - 2 * p.margin_mm;
  if (availX < 0 || availY < 0) return { cols: 0, rows: 0, total: 0 };
  const cols = Math.max(1, Math.floor(availX / p.pitch_x_mm) + 1);
  const rows = Math.max(1, Math.floor(availY / p.pitch_y_mm) + 1);
  return { cols, rows, total: cols * rows };
}

/**
 * Єдиний редактор перфо-панелі для обох форм отвору (Варіант B). Зверху —
 * SegmentedControl «Тип отвору»; нижче — AutoForm активної схеми. Значення
 * розміру дзеркалиться в обидва ключі (`syncHoleKeys`), тож перемикання форми
 * у студії не втрачає введеного. Банер перетину отворів — спільний валідатор.
 */
export function PerforatedPanelEditor({
  value,
  onChange,
  holeShape,
  onHoleShapeChange,
  visibleFields,
}: PerforatedPanelEditorProps) {
  const schema = useMemo(() => schemaForHoleShape(holeShape), [holeShape]);
  const validation = useMemo(() => schema.safeParse(value), [schema, value]);
  const fieldErrors = useMemo(
    () => (validation.success ? {} : zodIssuesToFieldErrors(validation.error.issues)),
    [validation],
  );
  const zodErrors = useMemo(() => {
    if (validation.success) return [] as string[];
    return validation.error.issues.map((i) => `${i.path.join(".") || "form"}: ${i.message}`);
  }, [validation]);

  // Grid-геометрія: крок має перевищувати розмір отвору, інакше отвори
  // зливаються (той самий валідатор, що й серверний gate).
  const perforationIssues = useMemo(
    () => validatePerforation({ templateSlug: slugForHoleShape(holeShape), parameters: value }),
    [holeShape, value],
  );
  const allErrors = useMemo(
    () => [...perforationIssues.map((i) => i.message), ...zodErrors],
    [perforationIssues, zodErrors],
  );

  const grid = useMemo(() => computeGrid(value), [value]);

  const effectiveVisibleFields = useMemo(
    () => normalizeVisibleFields(visibleFields, holeShape),
    [visibleFields, holeShape],
  );

  const holeValue = value[holeSizeFieldFor(holeShape)];
  const glyph = holeShape === "square" ? "□" : "Ø";

  return (
    <form
      data-testid="perforated-panel-editor"
      data-hole-shape={holeShape}
      className="flex flex-col gap-4"
      onSubmit={(e) => e.preventDefault()}
    >
      <div className="flex flex-col gap-2">
        <span className="text-fg text-sm font-medium">Тип отвору</span>
        <SegmentedControl
          value={holeShape}
          onValueChange={onHoleShapeChange}
          options={SHAPE_OPTIONS}
          ariaLabel="Тип отвору"
          testId="hole-shape-toggle"
        />
      </div>

      <AutoForm
        schema={schema}
        value={value as unknown as Record<string, unknown>}
        onChange={(next) =>
          onChange(syncHoleKeys(next as unknown as PerforationParameters, holeShape))
        }
        errors={fieldErrors}
        {...(effectiveVisibleFields ? { visibleFields: effectiveVisibleFields } : {})}
      />

      <p className="text-fg-muted text-xs" data-testid="grid-summary">
        Grid: {grid.cols}×{grid.rows} = {grid.total} отворів {glyph}
        {holeValue} мм (centered, pitch_x={value.pitch_x_mm} pitch_y={value.pitch_y_mm}).
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
