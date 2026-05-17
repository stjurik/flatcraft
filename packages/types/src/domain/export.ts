/**
 * Контракт `POST /exports` між web → api → cad-worker.
 *
 * thickness — у MVP параметрі моделі (Phase 3.5 додасть MaterialPicker
 * у UI; зараз web передає 2.0 за замовчуванням, але контракт уже типизований).
 *
 * Тільки L-bracket у Phase 2.7. Для решти шаблонів треба буде union
 * на parameters з відповідною Zod-схемою (Phase 2.10).
 */
import { z } from "zod";

import { LBracketParametersSchema } from "../templates/l-bracket.js";

export const ExportRequestSchema = z.object({
  template_slug: z.literal("l_bracket"),
  parameters: LBracketParametersSchema,
  thickness_mm: z.number().positive().max(10),
});

export type ExportRequest = z.infer<typeof ExportRequestSchema>;

export const ExportResponseSchema = z.object({
  dxf_url: z.string().url(),
  bytes: z.number().int().positive(),
  expires_at: z.string().datetime(),
  s3_key: z.string().min(1),
});

export type ExportResponse = z.infer<typeof ExportResponseSchema>;
