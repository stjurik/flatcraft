import { describe, expect, it } from "vitest";
import { ExportArtifactSchema, ExportRequestSchema } from "./export.js";
import { L_BRACKET_DEFAULT_PARAMETERS } from "../templates/l-bracket.js";

describe("ExportArtifactSchema", () => {
  const validBase = {
    url: "https://example.com/file.dxf",
    bytes: 1024,
    s3_key: "some/key.dxf",
  };

  it("accepts Z-formatted UTC datetime", () => {
    const data = {
      ...validBase,
      expires_at: "2026-05-30T10:30:57.123Z",
    };
    expect(ExportArtifactSchema.safeParse(data).success).toBe(true);
  });

  it("accepts offset-formatted datetime (Python-style)", () => {
    const data = {
      ...validBase,
      expires_at: "2026-05-30T10:30:57.123456+00:00",
    };
    expect(ExportArtifactSchema.safeParse(data).success).toBe(true);
  });

  it("rejects non-ISO datetime", () => {
    const data = {
      ...validBase,
      expires_at: "2026-05-30 10:30:57",
    };
    expect(ExportArtifactSchema.safeParse(data).success).toBe(false);
  });
});

describe("ExportRequestSchema — material_code (Phase 2.12 / ADR-018)", () => {
  const basePayload = {
    template_slug: "l_bracket" as const,
    parameters: L_BRACKET_DEFAULT_PARAMETERS,
    thickness_mm: 2.0,
  };

  it("accepts valid material_code", () => {
    expect(
      ExportRequestSchema.safeParse({ ...basePayload, material_code: "cold_rolled_steel" }).success,
    ).toBe(true);
  });

  it("rejects payload without material_code", () => {
    const result = ExportRequestSchema.safeParse(basePayload);
    expect(result.success).toBe(false);
  });

  it("rejects empty material_code", () => {
    expect(ExportRequestSchema.safeParse({ ...basePayload, material_code: "" }).success).toBe(
      false,
    );
  });
});
