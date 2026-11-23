/**
 * enclosed_shelf-специфічні серверні перевірки (issue #283, ADR-019): ребро
 * жорсткості (flange-after-bend) і перфорація боковин (вміщення у площину,
 * злиття отворів, вихід на край, відстань від гиба, кутові виступи). Окремий
 * файл, не `profile.ts`/`perforation.ts` — ці два валідатори не мають case'у
 * "enclosed_shelf" у своїх дискримінованих union-входах, а розширювати їх під
 * один шаблон зі своєю геометрією (cross-розгортка, дві незалежні боковини)
 * недоцільно.
 *
 * Дзеркало Python `workers/cad/flatcraft_cad/validate/enclosed_shelf.py` —
 * захист в глибину (клієнт-банер + Fastify-gate тут + cad-worker, ADR-019/026).
 *
 * Browser-safe: жодного `node:*`, чисті функції. Коефіцієнт `hole_to_bend_distance`
 * береться з `bakedSpec` (та сама константа, що й `holes.ts`, але
 * `validateExportPerforation` викликається з ОДНИМ аргументом — spec у неї
 * передати нема звідки, тож тут власний імпорт, issue #303).
 */
import { bakedSpec } from "../generated/baked-spec.js";

export type EnclosedShelfGateCode =
  | "FLANGE_TOO_SHORT"
  | "HOLES_OVERLAP"
  | "MARGIN_TOO_SMALL"
  | "PERFORATION_DOES_NOT_FIT"
  | "HOLE_TOO_CLOSE_TO_BEND"
  | "HOLE_IN_CORNER_TAB";

/**
 * Допуск на представлення чисел із рухомою крапкою (CLAUDE.md §7 — межа «від
 * краю»), той самий 1e-9, що `holes.ts::EDGE_DISTANCE_EPSILON_MM` і Python
 * `validate/holes.py::EDGE_DISTANCE_EPSILON_MM`.
 */
const EDGE_DISTANCE_EPSILON_MM = 1e-9;

export interface EnclosedShelfGateError {
  readonly field: string;
  readonly code: EnclosedShelfGateCode;
  readonly value: number;
  readonly message: string;
}

/** Округлення до 0.001 мм без хвостових нулів — для повідомлень. */
function fmt(n: number): string {
  return String(Math.round(n * 1000) / 1000);
}

export interface EnclosedShelfRibParams {
  readonly stiffening_rib: { readonly height_mm: number } | null;
  readonly bend_radius_mm: number;
}

/**
 * Ребро жорсткості (issue #283 п.1, доробка #304): ребро — це полиця, тож
 * валідно при `height_mm >= M` (глобальний `global.min_flange_mm`,
 * bend-machine spec, CLAUDE.md §7) **і** `height_mm > t + r` (строго, як
 * flange у z_bracket/wall_shelf/perforated_panel, `profile.ts`) — обидві
 * умови одночасно, той самий код `FLANGE_TOO_SHORT`. Повідомлення називає
 * діючий порог `max(M, t + r)`: коли `M >= t + r`, діє мінімальна полиця;
 * інакше — геометрія (товщина + радіус). `null` — ребра немає, нічого
 * перевіряти.
 */
export function validateEnclosedShelfRib(
  params: EnclosedShelfRibParams,
  thicknessMm: number,
): EnclosedShelfGateError[] {
  if (params.stiffening_rib === null) return [];
  const t = thicknessMm;
  const r = params.bend_radius_mm;
  const h = params.stiffening_rib.height_mm;
  const tr = t + r;
  const minFlangeMm = bakedSpec.global.min_flange_mm;
  if (h >= minFlangeMm && h > tr) return [];
  const threshold = Math.max(minFlangeMm, tr);
  const message =
    minFlangeMm >= tr
      ? `Збільшіть «Висота ребра»: потрібно не менше ${fmt(threshold)} мм (мінімальна полиця після гиба) — зараз ${fmt(h)} мм.`
      : `Збільшіть «Висота ребра»: потрібно більше за ${fmt(threshold)} мм (товщина ${fmt(t)} + радіус ${fmt(r)}) — зараз ${fmt(h)} мм.`;
  return [
    {
      field: "stiffening_rib.height_mm",
      code: "FLANGE_TOO_SHORT",
      value: h,
      message,
    },
  ];
}

export interface EnclosedShelfSidePerforationParams {
  readonly side_perforation: {
    readonly hole_size_mm: number;
    readonly pitch_x_mm: number;
    readonly pitch_y_mm: number;
    readonly margin_mm: number;
  } | null;
  readonly depth_mm: number;
  readonly bend_radius_mm: number;
  readonly stiffening_rib: { readonly height_mm: number } | null;
  readonly material_code: string;
}

/**
 * Ефективні відступи центрованої сітки отворів (issue #303) — та сама
 * формула, що Python `unfold.py::_enclosed_shelf_side_holes`: `null`, якщо
 * отворів взагалі немає (`avail < 0` по будь-якій осі, уже ловить
 * PERFORATION_DOES_NOT_FIT/056).
 */
function sidePerforationEffectiveMargins(
  wMm: number,
  hMm: number,
  pitchXMm: number,
  pitchYMm: number,
  marginMm: number,
): { readonly effMarginXMm: number; readonly effMarginYMm: number } | null {
  const availX = wMm - 2 * marginMm;
  const availY = hMm - 2 * marginMm;
  if (availX < 0 || availY < 0) return null;
  const nCols = Math.floor(availX / pitchXMm) + 1;
  const nRows = Math.floor(availY / pitchYMm) + 1;
  return {
    effMarginXMm: (wMm - (nCols - 1) * pitchXMm) / 2,
    effMarginYMm: (hMm - (nRows - 1) * pitchYMm) / 2,
  };
}

const AXIS_LABEL: Record<"pitch_x_mm" | "pitch_y_mm", string> = {
  pitch_x_mm: "Крок X",
  pitch_y_mm: "Крок Y",
};

/**
 * Перфорація боковин (issue #283 п.2). Позначення: h=hole_size_mm,
 * m=margin_mm, w = depth_mm − (t+r) — вужча вісь боковини (та сама формула,
 * що `avail_x` у Python `unfold.py::_enclosed_shelf_side_holes`; друга вісь,
 * depth_mm, завжди вміщається сама — боковина квадратна depth×depth, а
 * bend відсікає лише по осі w).
 *
 * Чотири незалежні правила — усі порушені перевіряються разом, без раннього
 * виходу (інакше користувач виправляє одне й отримує щойно сховану іншу
 * помилку):
 *   a. pitch_x_mm/pitch_y_mm > h — інакше отвори зливаються (HOLES_OVERLAP,
 *      окремо на кожну вісь).
 *   b. margin_mm > h/2 — інакше отвір виходить на край стінки (MARGIN_TOO_SMALL).
 *   c. 2·margin_mm ≤ w — інакше перфорація не вміщається по відступу
 *      (PERFORATION_DOES_NOT_FIT на margin_mm).
 *   d. hole_size_mm < w — інакше отвір більший за боковину
 *      (PERFORATION_DOES_NOT_FIT на hole_size_mm) — окрема підказка
 *      («зменшіть отвір»), щоб не ходити по колу з (c) («зменшіть відступ»).
 * `null` — перфорації немає, нічого перевіряти.
 *
 * Ще два незалежні правила (issue #303, CLAUDE.md §7 — отвір не ближче
 * `a·t+R` до гиба): рахуються лише коли отвори реально є (інакше про них
 * нічого сказати — це вже ловить (c)). Позначення: tr = t+r, M_hb = a·t+r
 * (a — коефіцієнт `hole_to_bend_distance.coefficient_by_material[material_code]`
 * з `bakedSpec`), q = tr, якщо задано ребро жорсткості, інакше tr/2 (висота
 * смуги кутового виступу боковини — похідна від `flat_bottom_y` у
 * `unfold.py::unfold_enclosed_shelf`, не залежить від depth_mm).
 *   e. ефективний відступ сітки по осі X (лінія гиба боковина↔дно) мінус
 *      половина отвору ≥ M_hb — інакше край отвору заходить у зону гиба
 *      (HOLE_TOO_CLOSE_TO_BEND на margin_mm). Невідомий material_code —
 *      правило пропускається (матеріал ловить власний гейт, `validateExportBends`).
 *   f. ефективний відступ сітки по осі Y мінус половина отвору ≥ q — інакше
 *      ряд отворів заходить у кутовий виступ (HOLE_IN_CORNER_TAB на margin_mm).
 *      Не залежить від матеріалу.
 */
export function validateEnclosedShelfSidePerforation(
  params: EnclosedShelfSidePerforationParams,
  thicknessMm: number,
): EnclosedShelfGateError[] {
  const p = params.side_perforation;
  if (p === null) return [];
  const { hole_size_mm: h, margin_mm: m, pitch_x_mm: px, pitch_y_mm: py } = p;
  const errors: EnclosedShelfGateError[] = [];

  for (const [axis, pitch] of [
    ["pitch_x_mm", px],
    ["pitch_y_mm", py],
  ] as const) {
    if (pitch <= h) {
      errors.push({
        field: `side_perforation.${axis}`,
        code: "HOLES_OVERLAP",
        value: pitch,
        message: `Збільшіть «${AXIS_LABEL[axis]}»: крок ${fmt(pitch)} мм має бути більший за сторону отвору ${fmt(h)} мм — інакше сусідні отвори перетинаються.`,
      });
    }
  }

  if (m <= h / 2) {
    errors.push({
      field: "side_perforation.margin_mm",
      code: "MARGIN_TOO_SMALL",
      value: m,
      message: `Збільшіть «Відступ від країв»: відступ ${fmt(m)} мм має бути більший за половину сторони отвору (${fmt(h / 2)} мм) — інакше отвір виходить на край стінки.`,
    });
  }

  const w = params.depth_mm - (thicknessMm + params.bend_radius_mm);
  if (2 * m > w) {
    errors.push({
      field: "side_perforation.margin_mm",
      code: "PERFORATION_DOES_NOT_FIT",
      value: m,
      message: `Зменшіть «Відступ від країв» (${fmt(m)} мм): при глибині ${fmt(params.depth_mm)} мм боковина вміщає перфорацію шириною ${fmt(w)} мм, а подвоєний відступ ${fmt(2 * m)} мм перевищує її.`,
    });
  }
  if (h >= w) {
    errors.push({
      field: "side_perforation.hole_size_mm",
      code: "PERFORATION_DOES_NOT_FIT",
      value: h,
      message: `Зменшіть «Сторона □»: отвір ${fmt(h)} мм не вміщається у боковину шириною ${fmt(w)} мм.`,
    });
  }

  const grid = sidePerforationEffectiveMargins(w, params.depth_mm, px, py, m);
  if (grid !== null) {
    const tr = thicknessMm + params.bend_radius_mm;
    const coeff = bakedSpec.hole_to_bend_distance.coefficient_by_material[params.material_code];
    if (coeff !== undefined) {
      const minHb = coeff * thicknessMm + params.bend_radius_mm;
      const edgeX = grid.effMarginXMm - h / 2;
      if (edgeX < minHb - EDGE_DISTANCE_EPSILON_MM) {
        errors.push({
          field: "side_perforation.margin_mm",
          code: "HOLE_TOO_CLOSE_TO_BEND",
          value: m,
          message: `Збільшіть «Відступ від країв» чи «Крок X», або зменшіть отвір: відстань від краю найближчого отвору до лінії гиба боковина↔дно ${fmt(edgeX)} мм менша за мінімум ${fmt(minHb)} мм (a·t+R = ${fmt(coeff)}×${fmt(thicknessMm)}+${fmt(params.bend_radius_mm)}).`,
        });
      }
    }

    const q = params.stiffening_rib !== null ? tr : tr / 2;
    const edgeY = grid.effMarginYMm - h / 2;
    if (edgeY < q - EDGE_DISTANCE_EPSILON_MM) {
      errors.push({
        field: "side_perforation.margin_mm",
        code: "HOLE_IN_CORNER_TAB",
        value: m,
        message: `Перемістіть ряд отворів усередину чи зменшіть отвір: ряд заходить у кутовий виступ боковини на ${fmt(q - edgeY)} мм (відступ від виступу ${fmt(edgeY)} мм, потрібно не менше ${fmt(q)} мм).`,
      });
    }
  }

  return errors;
}
