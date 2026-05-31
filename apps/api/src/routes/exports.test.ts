/**
 * Юніт-тести async exports endpoint'у.
 *
 * 202 + jobId → background fetch → store update'и → GET /:id повертає
 * final state. SSE-streaming тестується окремо в integration (e2e),
 * бо app.inject() не тримає persistent connection.
 */
import type { FastifyInstance } from "fastify";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { JobStore } from "../lib/job-store.js";
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
  material_code: "cold_rolled_steel",
  thickness_mm: 2,
};

const UPSTREAM_OK_BODY = {
  artifacts: {
    dxf: {
      url: "https://flatcraft.s3.amazonaws.com/key.dxf?Signature=abc&Expires=123",
      bytes: 16384,
      expires_at: "2026-05-17T00:00:00.000Z",
      s3_key: "exports/2026/05/17/abc_l_bracket.dxf",
    },
    pdf: {
      url: "https://flatcraft.s3.amazonaws.com/key.pdf?Signature=abc&Expires=123",
      bytes: 8192,
      expires_at: "2026-05-17T00:00:00.000Z",
      s3_key: "exports/2026/05/17/abc_l_bracket.pdf",
    },
  },
};

async function flushAsync(): Promise<void> {
  // Дозволити mock-fetch + store.update resolved promises виконатись.
  for (let i = 0; i < 5; i++) await new Promise((r) => setImmediate(r));
}

describe("POST /exports — async flow", () => {
  let app: FastifyInstance;
  let store: JobStore;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let fetchSpy: any;

  beforeEach(async () => {
    store = new JobStore({ retentionMs: 60_000 });
    app = await createServer({ logger: false, dbUrl: DUMMY_DB_URL, jobStore: store });
    fetchSpy = vi.spyOn(globalThis, "fetch");
  });

  afterEach(async () => {
    fetchSpy.mockRestore();
    await app.close();
  });

  it("202 + jobId з відразу", async () => {
    fetchSpy.mockResolvedValue(
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
    expect(res.statusCode).toBe(202);
    const body = res.json<{ id: string; status: string }>();
    expect(body.id).toMatch(/^[0-9a-f]{8}-/);
    expect(["queued", "running"]).toContain(body.status);
  });

  it("background flow: GET /:id після обробки → done з result", async () => {
    fetchSpy.mockResolvedValue(
      new Response(JSON.stringify(UPSTREAM_OK_BODY), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );
    const create = await app.inject({
      method: "POST",
      url: "/exports",
      payload: VALID_REQUEST,
    });
    const { id } = create.json<{ id: string }>();

    await flushAsync();

    const status = await app.inject({ method: "GET", url: `/exports/${id}` });
    expect(status.statusCode).toBe(200);
    const data = status.json<{
      status: string;
      progress: number;
      result?: typeof UPSTREAM_OK_BODY;
    }>();
    expect(data.status).toBe("done");
    expect(data.progress).toBe(100);
    expect(data.result).toEqual(UPSTREAM_OK_BODY);
  });

  it("background flow: cad-worker 5xx → failed з detail", async () => {
    fetchSpy.mockResolvedValue(new Response("trace", { status: 500 }));
    const create = await app.inject({
      method: "POST",
      url: "/exports",
      payload: VALID_REQUEST,
    });
    const { id } = create.json<{ id: string }>();
    await flushAsync();

    const status = await app.inject({ method: "GET", url: `/exports/${id}` });
    expect(status.statusCode).toBe(200);
    const data = status.json<{ status: string; error?: string }>();
    expect(data.status).toBe("failed");
    expect(data.error).toContain("500");
  });

  it("400 на невалідне body — job не створюється", async () => {
    const before = (store as unknown as { jobs: Map<string, unknown> }).jobs.size;
    const res = await app.inject({
      method: "POST",
      url: "/exports",
      payload: { ...VALID_REQUEST, parameters: { ...VALID_REQUEST.parameters, legA_mm: 10 } },
    });
    expect(res.statusCode).toBe(400);
    expect(fetchSpy).not.toHaveBeenCalled();
    expect((store as unknown as { jobs: Map<string, unknown> }).jobs.size).toBe(before);
  });

  it("GET /exports/:id для неіснуючого → 404", async () => {
    const res = await app.inject({
      method: "GET",
      url: "/exports/00000000-0000-0000-0000-000000000000",
    });
    expect(res.statusCode).toBe(404);
    expect(res.json<{ error: string }>().error).toBe("job_not_found");
  });

  it("ADR-018: material_code приймається на /exports, але обрізається перед cad-worker", async () => {
    fetchSpy.mockResolvedValue(
      new Response(JSON.stringify(UPSTREAM_OK_BODY), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );
    const create = await app.inject({
      method: "POST",
      url: "/exports",
      payload: VALID_REQUEST,
    });
    expect(create.statusCode).toBe(202);
    await flushAsync();

    expect(fetchSpy).toHaveBeenCalledTimes(1);
    const [, init] = fetchSpy.mock.calls[0];
    const forwarded = JSON.parse(init.body as string) as Record<string, unknown>;
    expect(forwarded.template_slug).toBe("l_bracket");
    expect(forwarded.thickness_mm).toBe(2);
    expect(forwarded.parameters).toBeDefined();
    expect(forwarded).not.toHaveProperty("material_code");
  });

  it("400 коли material_code відсутній — нова обов'язковість (Phase 2.12)", async () => {
    const { material_code: _omit, ...payloadWithoutMaterial } = VALID_REQUEST;
    const res = await app.inject({
      method: "POST",
      url: "/exports",
      payload: payloadWithoutMaterial,
    });
    expect(res.statusCode).toBe(400);
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("GET /exports/:id/events: для done job шле data-event і одразу закриває", async () => {
    fetchSpy.mockResolvedValue(
      new Response(JSON.stringify(UPSTREAM_OK_BODY), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );
    const create = await app.inject({
      method: "POST",
      url: "/exports",
      payload: VALID_REQUEST,
    });
    const { id } = create.json<{ id: string }>();
    await flushAsync();

    const sse = await app.inject({ method: "GET", url: `/exports/${id}/events` });
    expect(sse.statusCode).toBe(200);
    expect(sse.headers["content-type"]).toMatch(/text\/event-stream/);
    expect(sse.body).toContain("data: ");
    expect(sse.body).toContain('"status":"done"');
    expect(sse.body).toContain('"progress":100');
  });
});
