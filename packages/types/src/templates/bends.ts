/**
 * Напрям згину (Hotfix 2.10.e).
 *
 * Виробничі креслення вимагають явного напряму кожного гибу (UP/DOWN) — без
 * нього виробник може отримати дзеркальну деталь. Дефолт за рішенням
 * замовника: 'down' для всіх шаблонів.
 *
 * Single-bend шаблони (l_bracket, corner_angle) мають скалярний
 * `bend_direction`. Multi-bend (z_bracket, wall_shelf) — масив `bends` з
 * напрямом на кожен гиб (Z-кронштейн фізично гнеться у різні боки).
 */
import { z } from "zod";

export const BendDirectionSchema = z.enum(["up", "down"]);
export type BendDirection = z.infer<typeof BendDirectionSchema>;

export const BendSpecSchema = z.object({
  direction: BendDirectionSchema.default("down").describe("group:Гиб|label:Напрям згину"),
});
export type BendSpec = z.infer<typeof BendSpecSchema>;
