"use client";

import type { MaterialChoice } from "@flatcraft/types";

export interface MaterialSelection {
  readonly materialCode: string;
  readonly thicknessMm: number;
}

export interface MaterialSectionProps {
  readonly materials: ReadonlyArray<MaterialChoice>;
  readonly value: MaterialSelection;
  readonly onChange: (next: MaterialSelection) => void;
  /** Default — 2.0 (типова MVP-товщина), використовується при undefined у списку. */
  readonly preferredThicknessMm?: number;
}

// Phase 2.11 tokens — повторюємо стилі з AutoForm, щоб MaterialSection
// візуально був першим fieldset форми.
const FIELDSET_CLASS = "mb-6 rounded-md border border-border bg-bg-elevated p-4 space-y-3";
const LEGEND_CLASS = "px-2 text-base font-semibold text-fg";
const SELECT_CLASS =
  "min-h-tap w-full rounded-sm border border-border bg-surface-sunken px-3 py-2 text-sm text-fg " +
  "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:border-border-strong " +
  "transition-colors duration-fast ease-out";

/**
 * Селектор матеріалу + товщини — окремий fieldset, що рендериться першим
 * у студії. `materialCode` і `thicknessMm` зовнішньо керовані (controlled);
 * батьківський studio підіймає state у `useState` і передає в ExportRequest.
 *
 * Семантика зміни матеріалу: якщо поточна `thicknessMm` доступна у списку
 * нового матеріалу — лишається; інакше — beat-fallback на `preferredThicknessMm`
 * (default 2.0) або на найменшу доступну.
 */
export function MaterialSection({
  materials,
  value,
  onChange,
  preferredThicknessMm = 2.0,
}: MaterialSectionProps) {
  const current = materials.find((m) => m.code === value.materialCode);
  const thicknesses = current?.thicknesses_mm ?? [];

  const pickThickness = (next: ReadonlyArray<number>, desired: number): number => {
    if (next.includes(desired)) return desired;
    if (next.includes(preferredThicknessMm)) return preferredThicknessMm;
    return next[0] ?? desired;
  };

  const onMaterialChange = (nextCode: string) => {
    const nextMaterial = materials.find((m) => m.code === nextCode);
    const nextThicknesses = nextMaterial?.thicknesses_mm ?? [];
    onChange({
      materialCode: nextCode,
      thicknessMm: pickThickness(nextThicknesses, value.thicknessMm),
    });
  };

  const onThicknessChange = (nextThickness: number) => {
    onChange({ materialCode: value.materialCode, thicknessMm: nextThickness });
  };

  return (
    <fieldset className={FIELDSET_CLASS} data-testid="auto-form-group-Матеріал і товщина">
      <legend className={LEGEND_CLASS}>Матеріал і товщина</legend>
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <label className="flex flex-col gap-1.5 text-sm" data-testid="field-material_code">
          <span className="text-fg font-medium">Матеріал</span>
          <select
            data-testid="select-material_code"
            className={SELECT_CLASS}
            value={value.materialCode}
            onChange={(e) => onMaterialChange(e.target.value)}
          >
            {materials.map((m) => (
              <option key={m.code} value={m.code}>
                {m.name_uk}
              </option>
            ))}
          </select>
        </label>

        <label className="flex flex-col gap-1.5 text-sm" data-testid="field-thickness_mm">
          <span className="text-fg font-medium">Товщина листа, мм</span>
          <select
            data-testid="select-thickness_mm"
            className={SELECT_CLASS}
            value={String(value.thicknessMm)}
            onChange={(e) => onThicknessChange(Number(e.target.value))}
            disabled={thicknesses.length === 0}
          >
            {thicknesses.map((t) => (
              <option key={t} value={String(t)}>
                {t.toFixed(t % 1 === 0 ? 0 : 1)} мм
              </option>
            ))}
          </select>
        </label>
      </div>
    </fieldset>
  );
}
