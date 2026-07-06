CREATE TABLE "events" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"ts" timestamp with time zone DEFAULT now() NOT NULL,
	"event_type" text NOT NULL,
	"template_slug" text,
	"process" text DEFAULT 'sheet_metal' NOT NULL,
	"params" jsonb,
	"error_code" text,
	"duration_ms" integer,
	"session_hash" text
);
--> statement-breakpoint
ALTER TABLE "exports" ALTER COLUMN "user_id" DROP NOT NULL;--> statement-breakpoint
ALTER TABLE "exports" ALTER COLUMN "draft_id" DROP NOT NULL;--> statement-breakpoint
ALTER TABLE "exports" ADD COLUMN "template_slug" text;--> statement-breakpoint
ALTER TABLE "exports" ADD COLUMN "process" text DEFAULT 'sheet_metal' NOT NULL;--> statement-breakpoint
ALTER TABLE "exports" ADD COLUMN "session_hash" text;--> statement-breakpoint
CREATE INDEX "events_ts_idx" ON "events" USING btree ("ts" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX "events_type_ts_idx" ON "events" USING btree ("event_type","ts" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX "events_template_idx" ON "events" USING btree ("template_slug","ts" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX "exports_template_created_at_idx" ON "exports" USING btree ("template_slug","created_at" DESC NULLS LAST);