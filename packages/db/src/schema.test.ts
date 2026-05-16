/**
 * Перевіряє форму Drizzle-схеми (структуру колонок, FK, унікальності, PK)
 * через `getTableConfig`. Це не тести БД — лише гарантія, що метадані схеми
 * відповідають docs/05_DATA_MODEL.md. Інтеграційні тести проти Postgres —
 * у `migrate.int.test.ts` (Phase 0.3, після `docker compose up`).
 */
import { getTableConfig } from "drizzle-orm/pg-core";
import { describe, expect, it } from "vitest";

import * as schema from "./schema.js";

describe("schema — users", () => {
  it("має таблицю users з PK id та UNIQUE email", () => {
    const cfg = getTableConfig(schema.users);
    expect(cfg.name).toBe("users");
    const colNames = cfg.columns.map((c) => c.name);
    expect(colNames).toEqual(
      expect.arrayContaining([
        "id",
        "email",
        "email_verified_at",
        "password_hash",
        "display_name",
        "locale",
        "units",
        "role",
        "created_at",
        "deleted_at",
      ]),
    );
    const id = cfg.columns.find((c) => c.name === "id");
    expect(id?.primary).toBe(true);
    const email = cfg.columns.find((c) => c.name === "email");
    expect(email?.notNull).toBe(true);
    expect(email?.isUnique).toBe(true);
  });

  it("дефолти locale/units/role відповідають doc", () => {
    const cfg = getTableConfig(schema.users);
    expect(cfg.columns.find((c) => c.name === "locale")?.default).toBe("uk");
    expect(cfg.columns.find((c) => c.name === "units")?.default).toBe("mm");
    expect(cfg.columns.find((c) => c.name === "role")?.default).toBe("user");
  });
});

describe("schema — oauth_accounts", () => {
  it("має FK на users і UNIQUE (provider, provider_account_id)", () => {
    const cfg = getTableConfig(schema.oauthAccounts);
    expect(cfg.name).toBe("oauth_accounts");
    expect(cfg.foreignKeys).toHaveLength(1);
    const fk = cfg.foreignKeys[0]!.reference();
    expect(fk.foreignTable).toBe(schema.users);
    expect(fk.foreignColumns.map((c) => c.name)).toEqual(["id"]);
    const unique = cfg.uniqueConstraints[0];
    expect(unique?.columns.map((c) => c.name)).toEqual(["provider", "provider_account_id"]);
  });
});

describe("schema — sessions", () => {
  it("має FK на users і поле refresh_token_hash", () => {
    const cfg = getTableConfig(schema.sessions);
    expect(cfg.name).toBe("sessions");
    expect(cfg.columns.find((c) => c.name === "refresh_token_hash")?.notNull).toBe(true);
    expect(cfg.foreignKeys.length).toBeGreaterThan(0);
  });
});

describe("schema — materials і material_thicknesses", () => {
  it("materials.code — UNIQUE NOT NULL", () => {
    const cfg = getTableConfig(schema.materials);
    expect(cfg.name).toBe("materials");
    const code = cfg.columns.find((c) => c.name === "code");
    expect(code?.notNull).toBe(true);
    expect(code?.isUnique).toBe(true);
  });

  it("material_thicknesses має UNIQUE (material_id, thickness_mm)", () => {
    const cfg = getTableConfig(schema.materialThicknesses);
    expect(cfg.name).toBe("material_thicknesses");
    const unique = cfg.uniqueConstraints[0];
    expect(unique?.columns.map((c) => c.name)).toEqual(["material_id", "thickness_mm"]);
  });
});

describe("schema — templates і template_compatibility", () => {
  it("templates.slug — UNIQUE", () => {
    const cfg = getTableConfig(schema.templates);
    expect(cfg.name).toBe("templates");
    expect(cfg.columns.find((c) => c.name === "slug")?.isUnique).toBe(true);
  });

  it("template_compatibility має композитний PK (template_id, material_id)", () => {
    const cfg = getTableConfig(schema.templateCompatibility);
    expect(cfg.name).toBe("template_compatibility");
    const pk = cfg.primaryKeys[0];
    expect(pk?.columns.map((c) => c.name)).toEqual(["template_id", "material_id"]);
  });
});

describe("schema — model_drafts і exports", () => {
  it("model_drafts.user_id nullable (guest drafts)", () => {
    const cfg = getTableConfig(schema.modelDrafts);
    expect(cfg.name).toBe("model_drafts");
    expect(cfg.columns.find((c) => c.name === "user_id")?.notNull).toBe(false);
  });

  it("exports.user_id NOT NULL і formats — text[]", () => {
    const cfg = getTableConfig(schema.exports);
    expect(cfg.name).toBe("exports");
    expect(cfg.columns.find((c) => c.name === "user_id")?.notNull).toBe(true);
    const formats = cfg.columns.find((c) => c.name === "formats");
    expect(formats?.columnType).toBe("PgArray");
  });
});

describe("schema — usage_quota і donation_claims", () => {
  it("usage_quota має композитний PK (user_id, period_start)", () => {
    const cfg = getTableConfig(schema.usageQuota);
    expect(cfg.name).toBe("usage_quota");
    const pk = cfg.primaryKeys[0];
    expect(pk?.columns.map((c) => c.name)).toEqual(["user_id", "period_start"]);
  });

  it("donation_claims має поле channel і verified_by → users", () => {
    const cfg = getTableConfig(schema.donationClaims);
    expect(cfg.name).toBe("donation_claims");
    expect(cfg.columns.find((c) => c.name === "channel")?.notNull).toBe(true);
    // verified_by — self-FK на users
    const verifiedByFk = cfg.foreignKeys.find((fk) =>
      fk.reference().columns.some((c) => c.name === "verified_by"),
    );
    expect(verifiedByFk?.reference().foreignTable).toBe(schema.users);
  });
});

describe("schema — audit_log", () => {
  it("існує і має поле action", () => {
    const cfg = getTableConfig(schema.auditLog);
    expect(cfg.name).toBe("audit_log");
    expect(cfg.columns.find((c) => c.name === "action")?.notNull).toBe(true);
  });
});
