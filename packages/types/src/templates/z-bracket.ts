/**
 * Z-кронштейн — параметрична схема.
 *
 * Геометрія: 3 плоскі сегменти, з'єднані двома 90° гибами.
 *
 *       ─────────────────  ← top_flange_mm (горизонталь, на висоті offset)
 *                       │
 *                       │  ← vertical middle (offset_mm, паралельно товщині листа)
 *                       │
 *                       ─────────────────  ← bottom_flange_mm
 *
 * Контракт параметрів збігається з `workers/cad/templates/z_bracket.py`
 * (Pydantic) — JSON-aliases для camelCase зберігають TS-сумісність.
 */
import { z } from "zod";

import { BendSpecSchema } from "./bends.js";

const HoleSchema = z.object({
  /** На якій секції отвір: T — top, M — middle (вертикальна), B — bottom. */
  segment: z.enum(["T", "M", "B"]),
  /** Відстань від найближчого зовнішнього краю секції, мм. */
  distance_from_edge_mm: z.number().min(5),
  /** Відстань від найближчого гиба, мм. */
  distance_from_bend_mm: z.number().min(5),
  diameter_mm: z.number().min(2).max(50),
});

export const ZBracketParametersSchema = z.object({
  /** Довжина верхньої полиці (горизонтальна), мм. */
  top_flange_mm: z.number().min(20).max(500).describe("group:Верхня полиця|label:Довжина (мм)"),
  /** Довжина нижньої полиці, мм. */
  bottom_flange_mm: z.number().min(20).max(500).describe("group:Нижня полиця|label:Довжина (мм)"),
  /** Вертикальний offset між полицями = довжина середньої вертикальної секції, мм. */
  offset_mm: z
    .number()
    .min(20)
    .max(500)
    .describe("group:Середня полиця|label:Вертикальний offset (мм)"),
  /** Внутрішній радіус гиба, мм. */
  bend_radius_mm: z
    .union([z.literal(1), z.literal(2.5), z.literal(4), z.literal(5)])
    .describe("group:Гиби|label:Внутрішній радіус (мм)"),
  /** MVP: лише 90°. */
  bend_angle_deg: z.literal(90).describe("group:Гиби|label:Кут гиба (°)"),
  /**
   * Напрям кожного з 2 гибів. Дефолт [down, up]: Z-профіль фізично гнеться
   * у протилежні боки. bends[0] — гиб bottom→middle, bends[1] — middle→top.
   */
  bends: z
    .array(BendSpecSchema)
    .length(2)
    .default([{ direction: "down" }, { direction: "up" }])
    .describe("group:Гиби|label:Напрями згину"),
  /** Ширина (довжина гиба), мм. */
  width_mm: z.number().min(20).max(3000).describe("group:Загальне|label:Ширина (довжина гиба, мм)"),
  holes: z.array(HoleSchema).max(20).describe("group:Отвори|label:Отвори"),
});

export type ZBracketParameters = z.infer<typeof ZBracketParametersSchema>;
export type ZBracketHole = z.infer<typeof HoleSchema>;

export const Z_BRACKET_DEFAULT_PARAMETERS: ZBracketParameters = {
  top_flange_mm: 60,
  bottom_flange_mm: 60,
  offset_mm: 40,
  bend_radius_mm: 2.5,
  bend_angle_deg: 90,
  bends: [{ direction: "down" }, { direction: "up" }],
  width_mm: 100,
  holes: [],
};
