/**
 * enclosed_shelf-специфічні серверні перевірки (issue #283, ADR-019): ребро
 * жорсткості (flange-after-bend) і перфорація боковин (вміщення у площину,
 * злиття отворів, вихід на край). Окремий файл, не `profile.ts`/
 * `perforation.ts` — ці два валідатори не мають case'у "enclosed_shelf" у
 * своїх дискримінованих union-входах, а розширювати їх під один шаблон зі
 * своєю геометрією (cross-розгортка, дві незалежні боковини) недоцільно.
 *
 * Дзеркало Python `workers/cad/flatcraft_cad/validate/enclosed_shelf.py` —
 * захист в глибину (клієнт-банер + Fastify-gate тут + cad-worker, ADR-019/026).
 *
 * Browser-safe: жодного `node:*`, чисті функції.
 */

export type EnclosedShelfGateCode =
  | "FLANGE_TOO_SHORT"
  | "HOLES_OVERLAP"
  | "MARGIN_TOO_SMALL"
  | "PERFORATION_DOES_NOT_FIT";

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
 * Ребро жорсткості (issue #283 п.1): валідно при `height_mm > t + r`
 * (строго) — як flange у z_bracket/wall_shelf/perforated_panel
 * (`profile.ts`), той самий код `FLANGE_TOO_SHORT`. `null` — ребра немає,
 * нічого перевіряти.
 */
export function validateEnclosedShelfRib(
  params: EnclosedShelfRibParams,
  thicknessMm: number,
): EnclosedShelfGateError[] {
  if (params.stiffening_rib === null) return [];
  const t = thicknessMm;
  const r = params.bend_radius_mm;
  const h = params.stiffening_rib.height_mm;
  const min = t + r;
  if (h > min) return [];
  return [
    {
      field: "stiffening_rib.height_mm",
      code: "FLANGE_TOO_SHORT",
      value: h,
      message: `Збільшіть «Висота ребра»: потрібно більше за ${fmt(min)} мм (товщина ${fmt(t)} + радіус ${fmt(r)}) — зараз ${fmt(h)} мм.`,
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

  return errors;
}
