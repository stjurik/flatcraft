/**
 * Property-based тести валідатора гиба (Hotfix 2.10.e C).
 *
 * Закриваємо цілий клас багів "радіус допустимий глобально, але не для цієї
 * товщини". Oracle обчислюється напряму з матриці YAML; для будь-якої
 * комбінації (матеріал, товщина, радіус):
 *   - матриця явно дозволяє  → validateBend повертає valid
 *   - матриця явно забороняє  → ≥1 помилка
 *   - невідома комбінація     → ≥1 помилка
 *
 * 1000 ітерацій. Цей самий oracle дзеркалиться у Python
 * (`tests/test_validator_property.py`) — обидва читають один YAML.
 */
import fc from "fast-check";
import { describe, it } from "vitest";

import { loadSpecFromFile } from "../spec.js";
import { validateBend } from "./bend.js";

const spec = await loadSpecFromFile();

// Усі матеріали з обох груп + явно невідомі.
const knownMaterials = Array.from(
  new Set(Object.values(spec.material_groups).flatMap((g) => g.members)),
);
const materialArb = fc.constantFrom(...knownMaterials, "unobtanium", "");

const knownThicknesses = spec.capability_matrix.map((r) => r.thickness_mm);
const thicknessArb = fc.constantFrom(...knownThicknesses, 7, 3.5, 0.7);

const knownRadii = [1, 2.5, 4, 5];
const radiusArb = fc.constantFrom(...knownRadii, 3, 6, 0.5);

/** Oracle: чи має валідатор відмовити для (matrix-driven) комбінації. */
function shouldReject(material: string, thickness: number, radius: number): boolean {
  const row = spec.capability_matrix.find((r) => r.thickness_mm === thickness);
  if (!row) return true;
  const group = spec.material_groups[row.group];
  if (group && !group.members.includes(material)) return true;
  if (!row.allowed_inner_radius_mm.includes(radius)) return true;
  return false;
}

describe("validateBend — property-based matrix parity", () => {
  it("узгоджується з матрицею для 1000 випадкових (матеріал, товщина, радіус)", () => {
    fc.assert(
      fc.property(materialArb, thicknessArb, radiusArb, (material, thickness, radius) => {
        const result = validateBend(
          {
            materialCode: material,
            thicknessMm: thickness,
            innerRadiusMm: radius,
            // angle/flange/bendLength — завжди валідні, щоб у грі лишались
            // тільки matrix-залежні (матеріал, товщина, радіус).
            angleDeg: 90,
            flangeMm: 50,
            bendLengthMm: 200,
          },
          spec,
        );
        return result.valid === !shouldReject(material, thickness, radius);
      }),
      { numRuns: 1000 },
    );
  });
});
