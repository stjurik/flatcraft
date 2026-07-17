/**
 * Drizzle schema — єдине джерело істини для структури БД.
 * Документ-першоджерело: docs/05_DATA_MODEL.md.
 *
 * Дизайн-замітки:
 * - Усі ID — uuid. Doc вимагає uuid v7 (sortable); до Postgres 18 нема нативного
 *   gen_uuid_v7(). MVP використовує gen_random_uuid() (uuid v4) — перехід на v7
 *   зробимо окремою міграцією, коли Mirohost-Postgres підтягне 18 або поставимо
 *   pg-uuidv7 extension.
 * - JSONB-поля валідуються Zod-схемами на запис (рівень API, не drizzle).
 * - Soft-delete (users.deleted_at) — окремий filter у репозиторіях.
 * - Текстові поля з обмеженим набором значень (role, status, channel) — без
 *   pgEnum, бо drizzle потребує міграції на кожну зміну enum-значень.
 *   CHECK-constraints додамо при потребі.
 */
import { sql } from "drizzle-orm";
import {
  boolean,
  date,
  index,
  inet,
  integer,
  jsonb,
  numeric,
  pgTable,
  primaryKey,
  text,
  timestamp,
  unique,
  uuid,
} from "drizzle-orm/pg-core";

const id = () =>
  uuid("id")
    .primaryKey()
    .default(sql`gen_random_uuid()`);
const createdAt = () => timestamp("created_at", { withTimezone: true }).notNull().defaultNow();
const updatedAt = () => timestamp("updated_at", { withTimezone: true }).notNull().defaultNow();

// ─── users ──────────────────────────────────────────────────────────────────
export const users = pgTable(
  "users",
  {
    id: id(),
    email: text("email").notNull().unique(),
    emailVerifiedAt: timestamp("email_verified_at", { withTimezone: true }),
    passwordHash: text("password_hash"),
    displayName: text("display_name"),
    locale: text("locale").notNull().default("uk"),
    units: text("units").notNull().default("mm"),
    role: text("role").notNull().default("user"),
    createdAt: createdAt(),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
  },
  (t) => ({
    roleCreatedIdx: index("users_role_created_at_idx").on(t.role, t.createdAt),
  }),
);

// ─── oauth_accounts ─────────────────────────────────────────────────────────
export const oauthAccounts = pgTable(
  "oauth_accounts",
  {
    id: id(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    provider: text("provider").notNull(),
    providerAccountId: text("provider_account_id").notNull(),
    createdAt: createdAt(),
  },
  (t) => ({
    providerAccountUnq: unique("oauth_accounts_provider_account_unq").on(
      t.provider,
      t.providerAccountId,
    ),
  }),
);

// ─── sessions ───────────────────────────────────────────────────────────────
export const sessions = pgTable("sessions", {
  id: id(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  refreshTokenHash: text("refresh_token_hash").notNull(),
  userAgent: text("user_agent"),
  ipFirstSeen: inet("ip_first_seen"),
  expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
  createdAt: createdAt(),
  revokedAt: timestamp("revoked_at", { withTimezone: true }),
});

// ─── materials ──────────────────────────────────────────────────────────────
export const materials = pgTable("materials", {
  id: id(),
  code: text("code").notNull().unique(),
  nameUk: text("name_uk").notNull(),
  nameEn: text("name_en").notNull(),
  densityKgM3: numeric("density_kg_m3", { precision: 7, scale: 2 }).notNull(),
  category: text("category").notNull(),
  isActive: boolean("is_active").notNull().default(true),
});

// ─── material_thicknesses ───────────────────────────────────────────────────
export const materialThicknesses = pgTable(
  "material_thicknesses",
  {
    id: id(),
    materialId: uuid("material_id")
      .notNull()
      .references(() => materials.id, { onDelete: "cascade" }),
    thicknessMm: numeric("thickness_mm", { precision: 4, scale: 2 }).notNull(),
    isActive: boolean("is_active").notNull().default(true),
  },
  (t) => ({
    materialThicknessUnq: unique("material_thicknesses_material_thickness_unq").on(
      t.materialId,
      t.thicknessMm,
    ),
  }),
);

// ─── templates ──────────────────────────────────────────────────────────────
export const templates = pgTable("templates", {
  id: id(),
  slug: text("slug").notNull().unique(),
  nameUk: text("name_uk").notNull(),
  nameEn: text("name_en").notNull(),
  descriptionUk: text("description_uk"),
  descriptionEn: text("description_en"),
  version: integer("version").notNull().default(1),
  parametersSchema: jsonb("parameters_schema").notNull(),
  defaultParameters: jsonb("default_parameters").notNull(),
  previewImageUrl: text("preview_image_url"),
  isPublished: boolean("is_published").notNull().default(false),
  createdAt: createdAt(),
  updatedAt: updatedAt(),
});

// ─── template_compatibility ─────────────────────────────────────────────────
export const templateCompatibility = pgTable(
  "template_compatibility",
  {
    templateId: uuid("template_id")
      .notNull()
      .references(() => templates.id, { onDelete: "cascade" }),
    materialId: uuid("material_id")
      .notNull()
      .references(() => materials.id, { onDelete: "cascade" }),
    minThicknessMm: numeric("min_thickness_mm", { precision: 4, scale: 2 }),
    maxThicknessMm: numeric("max_thickness_mm", { precision: 4, scale: 2 }),
  },
  (t) => ({
    pk: primaryKey({
      name: "template_compatibility_pk",
      columns: [t.templateId, t.materialId],
    }),
  }),
);

// ─── model_drafts ───────────────────────────────────────────────────────────
export const modelDrafts = pgTable(
  "model_drafts",
  {
    id: id(),
    userId: uuid("user_id").references(() => users.id, {
      onDelete: "cascade",
    }),
    templateId: uuid("template_id")
      .notNull()
      .references(() => templates.id, { onDelete: "restrict" }),
    name: text("name").notNull().default("Untitled"),
    parameters: jsonb("parameters").notNull(),
    materialId: uuid("material_id")
      .notNull()
      .references(() => materials.id, { onDelete: "restrict" }),
    thicknessMm: numeric("thickness_mm", { precision: 4, scale: 2 }).notNull(),
    surfaceFinish: text("surface_finish"),
    paintRal: text("paint_ral"),
    validationStatus: text("validation_status").notNull().default("unchecked"),
    validationErrors: jsonb("validation_errors"),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => ({
    userUpdatedAtIdx: index("model_drafts_user_updated_at_idx").on(t.userId, t.updatedAt.desc()),
  }),
);

// ─── exports ────────────────────────────────────────────────────────────────
// Phase 3.3 (ADR-032): персист замість in-memory JobStore. У soft-launch (ADR-020)
// нема auth/drafts → user_id/draft_id NULLABLE (заповнюються з Phase 3). Нові
// template_slug/process/session_hash роблять рядок осмисленим без draft'а і дають
// join з `events`.
export const exports = pgTable(
  "exports",
  {
    id: id(),
    userId: uuid("user_id").references(() => users.id, { onDelete: "cascade" }),
    draftId: uuid("draft_id").references(() => modelDrafts.id, { onDelete: "cascade" }),
    templateSlug: text("template_slug"),
    process: text("process").notNull().default("sheet_metal"),
    sessionHash: text("session_hash"),
    formats: text("formats").array().notNull(),
    status: text("status").notNull().default("queued"),
    r2Keys: jsonb("r2_keys"),
    bom: jsonb("bom"),
    errorMessage: text("error_message"),
    createdAt: createdAt(),
    completedAt: timestamp("completed_at", { withTimezone: true }),
  },
  (t) => ({
    userCreatedAtIdx: index("exports_user_created_at_idx").on(t.userId, t.createdAt.desc()),
    statusIdx: index("exports_status_idx").on(t.status),
    templateCreatedAtIdx: index("exports_template_created_at_idx").on(
      t.templateSlug,
      t.createdAt.desc(),
    ),
  }),
);

// ─── usage_quota ────────────────────────────────────────────────────────────
export const usageQuota = pgTable(
  "usage_quota",
  {
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    periodStart: date("period_start").notNull(),
    freeUsed: integer("free_used").notNull().default(0),
    freeLimit: integer("free_limit").notNull().default(10),
    bonusUntil: timestamp("bonus_until", { withTimezone: true }),
    updatedAt: updatedAt(),
  },
  (t) => ({
    pk: primaryKey({
      name: "usage_quota_pk",
      columns: [t.userId, t.periodStart],
    }),
  }),
);

// ─── donation_claims ────────────────────────────────────────────────────────
export const donationClaims = pgTable("donation_claims", {
  id: id(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  channel: text("channel").notNull(),
  claimedAmountUah: numeric("claimed_amount_uah", {
    precision: 10,
    scale: 2,
  }).notNull(),
  proofUrl: text("proof_url"),
  status: text("status").notNull().default("pending"),
  verifiedBy: uuid("verified_by").references(() => users.id, {
    onDelete: "set null",
  }),
  verifiedAt: timestamp("verified_at", { withTimezone: true }),
  notes: text("notes"),
  createdAt: createdAt(),
});

// ─── products (Phase 3.0, ADR-027) ─────────────────────────────────────────
// Preset базового шаблону з обмеженим набором user_editable_fields. Окрема
// таблиця від templates (Рішення 1). Слабкий зв'язок через base_template_slug
// (без FK) — templates можуть жити лише у seed/Python-коді; цілісність
// перевіряється Zod-валідатором seed'у.
export const products = pgTable(
  "products",
  {
    id: id(),
    slug: text("slug").notNull().unique(),
    name: text("name").notNull(),
    description: text("description"),
    baseTemplateSlug: text("base_template_slug").notNull(),
    // fixed_parameters: значення, які виробник фіксує. Cross-перевірка проти
    // template.parameters_schema — у seed-валідаторі.
    fixedParameters: jsonb("fixed_parameters").notNull().default({}),
    // user_editable_fields: список полів зі схеми base_template, які користувач
    // редагує. Підтримує dot-notation для nested (напр., side_perforation.hole_diameter_mm).
    userEditableFields: text("user_editable_fields").array().notNull(),
    previewImageUrl: text("preview_image_url"),
    // use_cases: теги для майбутньої фільтрації каталогу (Phase 3.5+).
    useCases: text("use_cases")
      .array()
      .notNull()
      .default(sql`'{}'::text[]`),
    isPublished: boolean("is_published").notNull().default(false),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => ({
    // Partial index: GET /products?is_published=true (default) — найгарячіший шлях.
    publishedIdx: index("products_published_idx")
      .on(t.isPublished)
      .where(sql`${t.isPublished}`),
    // Lookup для фільтрації за базовим шаблоном (UI: «всі вироби на основі X»).
    baseTemplateIdx: index("products_base_template_idx").on(t.baseTemplateSlug),
  }),
);

// ─── audit_log ──────────────────────────────────────────────────────────────
export const auditLog = pgTable("audit_log", {
  id: id(),
  userId: uuid("user_id").references(() => users.id, { onDelete: "set null" }),
  action: text("action").notNull(),
  metadata: jsonb("metadata"),
  createdAt: createdAt(),
});

// ─── events (Phase 3.3, ADR-032) ─────────────────────────────────────────────
// Append-only телеметрія, БЕЗ PII (docs/11_OBSERVABILITY.md). Слабкий зв'язок з
// exports/templates через template_slug + params (не строгий FK, тому й нема
// FK-колонок). `params` — знімок геометрії виробу (технічні дані, не PII).
// `session_hash` — добовий salt (непереслідуваний, ADR-032 п.6). Retention 12 міс
// (scheduled job). Пише лише api (worker не має доступу до Postgres).
export const events = pgTable(
  "events",
  {
    id: id(),
    ts: timestamp("ts", { withTimezone: true }).notNull().defaultNow(),
    eventType: text("event_type").notNull(),
    templateSlug: text("template_slug"),
    process: text("process").notNull().default("sheet_metal"),
    params: jsonb("params"),
    errorCode: text("error_code"),
    durationMs: integer("duration_ms"),
    sessionHash: text("session_hash"),
  },
  (t) => ({
    tsIdx: index("events_ts_idx").on(t.ts.desc()),
    typeTsIdx: index("events_type_ts_idx").on(t.eventType, t.ts.desc()),
    templateTsIdx: index("events_template_idx").on(t.templateSlug, t.ts.desc()),
  }),
);

// ─── export_feedback (Phase 3.4, ADR-032 §feedback / R-01 mitigation 4) ─────
// Виробничий фідбек з форми `/f/{export_id}` — читається з QR-коду у PDF.
// Мобільна форма без auth: 3 поля (виготовлено / відхилення / коментар).
// Мета — замкнути self-improvement loop: користувач замовив креслення →
// виробництво зробило деталь → залишили відгук → digest бачить deviation
// репорти → K-фактор калібрується.
// Rate-limit — IP-based на стороні api (не тут). Без PII.
export const exportFeedback = pgTable(
  "export_feedback",
  {
    id: id(),
    exportId: uuid("export_id")
      .notNull()
      .references(() => exports.id, { onDelete: "cascade" }),
    // Обов'язковий; enum-варіанти узгоджені з формою (див. `docs/promts/inputs/c4-feedback-copy.md`):
    // "made" = вийшла ✅, "deviations" = з відхиленнями ⚠️, "failed" = не вийшла ❌.
    outcome: text("outcome").notNull(),
    // Опис відхилень від креслення — вільна форма ≤ 500 символів (валідується у api).
    // NULL допустимо для outcome="made".
    deviationDescription: text("deviation_description"),
    // Довільний коментар — вільна форма ≤ 1000 символів (валідується у api).
    // Обов'язковий для outcome="failed", інакше опційний.
    comment: text("comment"),
    // Локаль форми на момент відправки (для аналітики UA vs EN). "uk"|"en".
    locale: text("locale").notNull().default("uk"),
    sessionHash: text("session_hash"),
    createdAt: createdAt(),
  },
  (t) => ({
    exportIdx: index("export_feedback_export_idx").on(t.exportId),
    outcomeCreatedAtIdx: index("export_feedback_outcome_idx").on(t.outcome, t.createdAt.desc()),
  }),
);
