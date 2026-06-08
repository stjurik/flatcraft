/**
 * Hotfix 2.9.c (C): createExport має витягувати RFC 9457 `detail`/`errors[]`
 * з тіла 4xx, щоб UI показав дружнє повідомлення замість generic «422».
 */
import { L_BRACKET_DEFAULT_PARAMETERS, type ExportRequest } from "@flatcraft/types";
import { afterEach, describe, expect, it, vi } from "vitest";

import { ApiError, createExport } from "./api";

const REQUEST: ExportRequest = {
  template_slug: "l_bracket",
  parameters: L_BRACKET_DEFAULT_PARAMETERS,
  material_code: "cold_rolled_steel",
  thickness_mm: 5,
};

afterEach(() => {
  vi.restoreAllMocks();
});

function mockFetch(status: number, body: unknown): void {
  vi.stubGlobal(
    "fetch",
    vi.fn(async () => ({
      ok: status >= 200 && status < 300,
      status,
      json: async () => body,
    })),
  );
}

describe("createExport — RFC 9457 parsing", () => {
  it("422 → ApiError.message = problem.detail (дружнє, не generic)", async () => {
    mockFetch(422, {
      type: "https://flatcraft.io/errors/validation",
      title: "Validation failed",
      status: 422,
      detail:
        "Збільшіть радіус гибки: для товщини 5 мм мінімальний радіус 4 мм (дозволено: 4, 5 мм).",
      instance: "/exports",
      errors: [{ field: "bend_radius_mm", code: "RADIUS_NOT_ALLOWED", message: "..." }],
    });

    const err = await createExport(REQUEST).catch((e) => e);
    expect(err).toBeInstanceOf(ApiError);
    expect((err as ApiError).status).toBe(422);
    expect((err as ApiError).message).toMatch(/Збільшіть радіус/);
    expect((err as ApiError).message).not.toMatch(/експорт не вдався/i);
  });

  it("fallback на errors[0].message коли detail відсутній", async () => {
    mockFetch(422, {
      status: 422,
      errors: [
        {
          field: "bend_radius_mm",
          code: "RADIUS_NOT_ALLOWED",
          message: "Оберіть радіус 4 або 5 мм.",
        },
      ],
    });
    const err = (await createExport(REQUEST).catch((e) => e)) as ApiError;
    expect(err.message).toBe("Оберіть радіус 4 або 5 мм.");
  });

  it("graceful fallback коли тіло не JSON", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => ({
        ok: false,
        status: 500,
        json: async () => {
          throw new Error("not json");
        },
      })),
    );
    const err = (await createExport(REQUEST).catch((e) => e)) as ApiError;
    expect(err).toBeInstanceOf(ApiError);
    expect(err.status).toBe(500);
    expect(err.message).toContain("500");
  });
});
