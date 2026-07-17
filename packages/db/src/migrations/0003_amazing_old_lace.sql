CREATE TABLE "export_feedback" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"export_id" uuid NOT NULL,
	"outcome" text NOT NULL,
	"deviation_description" text,
	"comment" text,
	"locale" text DEFAULT 'uk' NOT NULL,
	"session_hash" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "export_feedback" ADD CONSTRAINT "export_feedback_export_id_exports_id_fk" FOREIGN KEY ("export_id") REFERENCES "public"."exports"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "export_feedback_export_idx" ON "export_feedback" USING btree ("export_id");--> statement-breakpoint
CREATE INDEX "export_feedback_outcome_idx" ON "export_feedback" USING btree ("outcome","created_at" DESC NULLS LAST);