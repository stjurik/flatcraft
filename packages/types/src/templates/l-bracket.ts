/**
 * L-кронштейн — параметрична схема (docs/05 §5).
 *
 * Власне геометрія живе у Python (workers/cad/templates/l_bracket.py),
 * але контракт параметрів — спільний: web → api → BullMQ → cad-worker.
 * Pydantic у воркері валідує те ж JSON-Schema, що виходить з цього Zod
 * (Phase 1.5 згенерує його через @asteasolutions/zod-to-openapi або
 * прямий ZodToJsonSchema).
 *
 * MVP-обмеження (CLAUDE.md §7 і doc/05):
 *   - дозволено лише 90°
 *   - радіус з фіксованого набору {1, 2.5, 4, 5} мм
 *   - до 20 отворів на полицю
 */
import { z } from "zod";

const HoleSchema = z.object({
  /** На якій полиці отвір: A — вертикальна, B — горизонтальна. */
  leg: z.enum(["A", "B"]),
  /** Відстань від найближчого зовнішнього краю полиці, мм. */
  distance_from_edge_mm: z.number().min(5),
  /** Відстань від лінії гиба (centre to centre), мм. */
  distance_from_bend_mm: z.number().min(5),
  diameter_mm: z.number().min(2).max(50),
});

export const LBracketParametersSchema = z.object({
  /** Висота вертикальної полиці, мм. */
  legA_mm: z.number().min(20).max(500).describe("group:Полиця A|label:Висота полиці A (мм)"),
  /** Глибина горизонтальної полиці, мм. */
  legB_mm: z.number().min(20).max(500).describe("group:Полиця B|label:Глибина полиці B (мм)"),
  /** Внутрішній радіус гиба, мм. Відповідає allowed_inner_radius_mm у bend-machine spec. */
  bend_radius_mm: z
    .union([z.literal(1), z.literal(2.5), z.literal(4), z.literal(5)])
    .describe("group:Гиб|label:Внутрішній радіус гиба (мм)"),
  /** MVP: лише 90°. Інші кути додамо post-launch. */
  bend_angle_deg: z.literal(90).describe("group:Гиб|label:Кут гиба (°)"),
  /** Ширина L-кронштейна (довжина лінії гиба), мм. */
  width_mm: z.number().min(20).max(3000).describe("group:Загальне|label:Ширина (довжина гиба, мм)"),
  holes: z.array(HoleSchema).max(20).describe("group:Отвори|label:Отвори"),
});

export type LBracketParameters = z.infer<typeof LBracketParametersSchema>;
export type LBracketHole = z.infer<typeof HoleSchema>;

/**
 * Стартовий набір параметрів. Використовується як:
 *   - default_parameters у seed.ts для шаблону l_bracket (post-launch).
 *   - prefill для нових drafts у UI.
 */
export const L_BRACKET_DEFAULT_PARAMETERS: LBracketParameters = {
  legA_mm: 60,
  legB_mm: 60,
  bend_radius_mm: 2.5,
  bend_angle_deg: 90,
  width_mm: 100,
  holes: [],
};
