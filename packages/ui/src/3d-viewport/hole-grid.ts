/**
 * Обчислення centered grid отворів для 3D-preview перфо-виробів
 * (perforated_panel, perforated_panel_square, enclosed_shelf side-perforation).
 *
 * Layout ідентичний Python `unfold_perforated_panel*`: для кожного виміру
 * рахуємо `floor((dim − 2·margin)/pitch) + 1` отворів, центруємо grid.
 *
 * **Чому є децимація (Phase 3.1 fix):** раніше кожна сцена при
 * `total > MAX` рендерила НУЛЬ отворів → панель виглядала суцільною плитою
 * (баг: збільшення розміру за ~580 мм «гасило» всю перфорацію). Тепер,
 * якщо повний grid перевищує ліміт preview, ми рівномірно прорідимо його
 * кроком `stride`, щоб панель ЗАВЖДИ читалась як перфорована. Точна
 * геометрія (усі отвори) — у DXF; viewport — умовне відображення.
 *
 * Реальний рендер — через InstancedMesh (1 draw call), тож ліміт високий і
 * децимація вмикається лише на гігантських панелях, далеких від типових.
 */
export interface HoleGridInput {
  /** Повна довжина листа вздовж осі X, мм. */
  readonly lengthMm: number;
  /** Повна ширина листа вздовж осі Y, мм. */
  readonly widthMm: number;
  readonly pitchXMm: number;
  readonly pitchYMm: number;
  readonly marginMm: number;
  /** Макс. отворів у preview після децимації. За замовч. DEFAULT_MAX_HOLES_PREVIEW. */
  readonly maxHoles?: number;
}

export interface HoleGridCell {
  /** Координата вздовж length, центрована навколо 0 (−L/2 … L/2). */
  readonly u: number;
  /** Координата вздовж width, центрована навколо 0 (−W/2 … W/2). */
  readonly v: number;
}

export interface HoleGrid {
  /** Повна кількість колонок (до децимації). */
  readonly nCols: number;
  /** Повна кількість рядів (до децимації). */
  readonly nRows: number;
  /** Повна кількість отворів (до децимації) = nCols·nRows. */
  readonly total: number;
  /** Центри отворів для рендеру (можливо проріджені), ≤ maxHoles. */
  readonly cells: readonly HoleGridCell[];
  /** true, якщо grid проріджено (cells розрідженіші за реальний виріб). */
  readonly decimated: boolean;
}

/**
 * Високий ліміт: InstancedMesh рендерить тисячі отворів одним draw call'ом,
 * тож децимація — лише запобіжник для екстремальних панелей (напр. 3000×3000
 * з кроком 10 → 90k отворів). Типові вироби (навіть 580+ мм) показуються повністю.
 */
export const DEFAULT_MAX_HOLES_PREVIEW = 8000;

export function computeHoleGrid(input: HoleGridInput): HoleGrid {
  const { lengthMm: L, widthMm: W, pitchXMm: px, pitchYMm: py, marginMm: m } = input;
  const maxHoles = input.maxHoles ?? DEFAULT_MAX_HOLES_PREVIEW;

  const nCols = Math.max(1, Math.floor((L - 2 * m) / px) + 1);
  const nRows = Math.max(1, Math.floor((W - 2 * m) / py) + 1);
  const effMarginX = (L - (nCols - 1) * px) / 2;
  const effMarginY = (W - (nRows - 1) * py) / 2;
  const total = nCols * nRows;

  // Рівномірний крок проріджування: stride² ≈ total/maxHoles → cells ≤ maxHoles.
  const stride = total <= maxHoles ? 1 : Math.ceil(Math.sqrt(total / maxHoles));

  const cells: HoleGridCell[] = [];
  for (let i = 0; i < nCols; i += stride) {
    const u = effMarginX + i * px - L / 2;
    for (let j = 0; j < nRows; j += stride) {
      const v = effMarginY + j * py - W / 2;
      cells.push({ u, v });
    }
  }

  return { nCols, nRows, total, cells, decimated: stride > 1 };
}
