/**
 * Юніт-тести POST /exports з mock'ed cad-worker.
 * Інтеграційний тест проти живого Python /export — у workers/cad, не тут.
 */
import type { FastifyInstance } from "fastify";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { createServer } from "../server.js";

const DUMMY_DB_URL = "postgresql://dummy:dummy@127.0.0.1:1/dummy";

const VALID_REQUEST = {
  template_slug: "l_bracket" as const,
  parameters: {
    legA_mm: 60,
    legB_mm: 60,
    bend_radius_mm: 2.5,
    bend_angle_deg: 90,
    width_mm: 100,
    holes: [],
  },
  thickness_mm: 2,
};

const UPSTREAM_OK_BODY = {
  dxf_url: "https://flatcraft.s3.amazonaws.com/key.dxf?Signature=abc&Expires=123",
  bytes: 16384,
  expires_at: "2026-05-17T00:00:00.000Z",
  s3_key: "exports/2026/05/17/abc_l_bracket.dxf",
};

describe("POST /exports", () => {
  let app: FastifyInstance;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let fetchSpy: any;

  beforeEach(async () => {
    app = await createServer({ logger: false, dbUrl: DUMMY_DB_URL });
    fetchSpy = vi.spyOn(globalThis, "fetch");
  });

  afterEach(async () => {
    fetchSpy.mockRestore();
    await app.close();
  });

  it("200: forward'ить body до cad-worker і повертає його response", async () => {
    fetchSpy.mockResolvedValueOnce(
      new Response(JSON.stringify(UPSTREAM_OK_BODY), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );

    const res = await app.inject({
      method: "POST",
      url: "/exports",
      payload: VALID_REQUEST,
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual(UPSTREAM_OK_BODY);

    expect(fetchSpy).toHaveBeenCalledTimes(1);
    const [url, init] = fetchSpy.mock.calls[0]! as [string, RequestInit | undefined];
    expect(String(url)).toMatch(/\/export$/);
    expect(init?.method).toBe("POST");
    expect(JSON.parse(String(init?.body))).toEqual(VALID_REQUEST);
  });

  it("400: невалідний body (legA < min) — без fetch до cad-worker", async () => {
    const res = await app.inject({
      method: "POST",
      url: "/exports",
      payload: {
        ...VALID_REQUEST,
        parameters: { ...VALID_REQUEST.parameters, legA_mm: 10 },
      },
    });
    expect(res.statusCode).toBe(400);
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("502: cad-worker недоступний (мережева помилка)", async () => {
    fetchSpy.mockRejectedValueOnce(new Error("ECONNREFUSED"));

    const res = await app.inject({
      method: "POST",
      url: "/exports",
      payload: VALID_REQUEST,
    });
    expect(res.statusCode).toBe(502);
    const body = res.json<{ error: string; status: number; detail?: string }>();
    expect(body.error).toBe("cad_worker_failed");
    expect(body.detail).toBe("unreachable");
  });

  it("502: cad-worker повертає 5xx — wrap'имо у наш формат", async () => {
    fetchSpy.mockResolvedValueOnce(new Response("internal error trace", { status: 500 }));

    const res = await app.inject({
      method: "POST",
      url: "/exports",
      payload: VALID_REQUEST,
    });
    expect(res.statusCode).toBe(502);
    const body = res.json<{ error: string; status: number; detail?: string }>();
    expect(body.error).toBe("cad_worker_failed");
    expect(body.status).toBe(500);
    expect(body.detail).toContain("internal error");
  });

  it("502: cad-worker повертає невалідну схему — Zod catches", async () => {
    fetchSpy.mockResolvedValueOnce(
      new Response(JSON.stringify({ wrong: "shape" }), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );

    const res = await app.inject({
      method: "POST",
      url: "/exports",
      payload: VALID_REQUEST,
    });
    // Fastify ловить throw з Zod parse як 500.
    expect(res.statusCode).toBeGreaterThanOrEqual(500);
  });
});
