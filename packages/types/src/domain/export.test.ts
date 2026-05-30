import { describe, expect, it } from "vitest";
import { ExportArtifactSchema } from "./export.js";

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
