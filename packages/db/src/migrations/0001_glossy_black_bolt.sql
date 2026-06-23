CREATE TABLE "products" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"slug" text NOT NULL,
	"name" text NOT NULL,
	"description" text,
	"base_template_slug" text NOT NULL,
	"fixed_parameters" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"user_editable_fields" text[] NOT NULL,
	"preview_image_url" text,
	"use_cases" text[] DEFAULT '{}'::text[] NOT NULL,
	"is_published" boolean DEFAULT false NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "products_slug_unique" UNIQUE("slug")
);
--> statement-breakpoint
CREATE INDEX "products_published_idx" ON "products" USING btree ("is_published") WHERE "products"."is_published";--> statement-breakpoint
CREATE INDEX "products_base_template_idx" ON "products" USING btree ("base_template_slug");