/**
 * Контракт `POST /exports` між web → api → cad-worker.
 *
 * Phase 2.10: discriminated union на slug. Кожен шаблон має свою
 * Zod-схему параметрів. Якщо payload не пройде discriminator — 400.
 *
 * thickness_mm — окремо від parameters (Phase 3.5 додасть MaterialPicker;
 * поки web передає 2.0 за замовчуванням).
 */
import { z } from "zod";

import { CornerAngleParametersSchema } from "../templates/corner-angle.js";
import { LBracketParametersSchema } from "../templates/l-bracket.js";
import { PerforatedPanelParametersSchema } from "../templates/perforated-panel.js";
// Base (non-refined) — discriminatedUnion вимагає ZodObject, не ZodEffects.
// Cross-field constraint живе у `WallShelfParametersSchema` (UI), і у Pydantic.
import { WallShelfParametersBaseSchema } from "../templates/wall-shelf.js";
import { ZBracketParametersSchema } from "../templates/z-bracket.js";

export const ExportRequestSchema = z.discriminatedUnion("template_slug", [
  z.object({
    template_slug: z.literal("l_bracket"),
    parameters: LBracketParametersSchema,
    thickness_mm: z.number().positive().max(10),
  }),
  z.object({
    template_slug: z.literal("z_bracket"),
    parameters: ZBracketParametersSchema,
    thickness_mm: z.number().positive().max(10),
  }),
  z.object({
    template_slug: z.literal("corner_angle"),
    parameters: CornerAngleParametersSchema,
    thickness_mm: z.number().positive().max(10),
  }),
  z.object({
    template_slug: z.literal("wall_shelf"),
    parameters: WallShelfParametersBaseSchema,
    thickness_mm: z.number().positive().max(10),
  }),
  z.object({
    template_slug: z.literal("perforated_panel"),
    parameters: PerforatedPanelParametersSchema,
    thickness_mm: z.number().positive().max(10),
  }),
]);

export type ExportRequest = z.infer<typeof ExportRequestSchema>;

export const ExportArtifactSchema = z.object({
  url: z.string().url(),
  bytes: z.number().int().positive(),
  expires_at: z.string().datetime({ offset: true }),
  s3_key: z.string().min(1),
});

export type ExportArtifact = z.infer<typeof ExportArtifactSchema>;

export const ExportResponseSchema = z.object({
  artifacts: z.object({
    dxf: ExportArtifactSchema,
    pdf: ExportArtifactSchema,
  }),
});

export type ExportResponse = z.infer<typeof ExportResponseSchema>;

/**
 * Async-флоу (Phase 2.8): POST /exports повертає JobAccepted, далі
 * клієнт підписується на /exports/:id/events (SSE) і отримує JobEvent
 * допоки status='done' або 'failed'.
 */
export const JobStatusSchema = z.enum(["queued", "running", "done", "failed"]);
export type JobStatus = z.infer<typeof JobStatusSchema>;

export const ExportJobAcceptedSchema = z.object({
  id: z.string().uuid(),
  status: JobStatusSchema,
});
export type ExportJobAccepted = z.infer<typeof ExportJobAcceptedSchema>;

export const ExportJobEventSchema = z.object({
  id: z.string().uuid(),
  status: JobStatusSchema,
  /** 0..100. Для queued — 0; для done — 100; running — proportional. */
  progress: z.number().min(0).max(100),
  /** Заповнено коли status='done'. */
  result: ExportResponseSchema.optional(),
  /** Заповнено коли status='failed'. */
  error: z.string().optional(),
});
export type ExportJobEvent = z.infer<typeof ExportJobEventSchema>;
