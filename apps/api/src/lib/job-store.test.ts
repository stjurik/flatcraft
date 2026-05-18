import type { ExportResponse } from "@flatcraft/types";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { JobStore } from "./job-store.js";

const SAMPLE_RESULT: ExportResponse = {
  artifacts: {
    dxf: {
      url: "https://example.com/test.dxf?Signature=x&Expires=1",
      bytes: 1024,
      expires_at: "2026-05-17T00:00:00.000Z",
      s3_key: "exports/test.dxf",
    },
    pdf: {
      url: "https://example.com/test.pdf?Signature=x&Expires=1",
      bytes: 512,
      expires_at: "2026-05-17T00:00:00.000Z",
      s3_key: "exports/test.pdf",
    },
  },
};

describe("JobStore", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it("create() повертає queued/progress=0 з UUID", () => {
    const store = new JobStore();
    const job = store.create();
    expect(job.status).toBe("queued");
    expect(job.progress).toBe(0);
    expect(job.id).toMatch(/^[0-9a-f]{8}-/);
  });

  it("get(id) повертає актуальний job", () => {
    const store = new JobStore();
    const job = store.create();
    expect(store.get(job.id)?.status).toBe("queued");
  });

  it("update() мутує і пуш'ить listeners", () => {
    const store = new JobStore();
    const job = store.create();
    const seen: string[] = [];
    store.subscribe(job.id, (j) => seen.push(`${j.status}:${j.progress}`));

    store.update(job.id, { status: "running", progress: 50 });
    expect(store.get(job.id)?.progress).toBe(50);
    expect(seen).toEqual(["running:50"]);

    store.update(job.id, { status: "done", progress: 100, result: SAMPLE_RESULT });
    expect(seen).toContain("done:100");
  });

  it("done/failed jobs прибираються після retention", () => {
    const store = new JobStore({ retentionMs: 1000 });
    const job = store.create();
    store.update(job.id, { status: "done", progress: 100, result: SAMPLE_RESULT });
    expect(store.get(job.id)).toBeDefined();
    vi.advanceTimersByTime(1001);
    expect(store.get(job.id)).toBeUndefined();
  });

  it("unsubscribe скасовує доставку подальших updates", () => {
    const store = new JobStore();
    const job = store.create();
    const seen: string[] = [];
    const off = store.subscribe(job.id, (j) => seen.push(j.status));
    store.update(job.id, { status: "running", progress: 10 });
    off();
    store.update(job.id, { status: "done", progress: 100, result: SAMPLE_RESULT });
    expect(seen).toEqual(["running"]);
  });

  it("update неіснуючого id повертає undefined", () => {
    const store = new JobStore();
    expect(store.update("not-real", { status: "done", progress: 100 })).toBeUndefined();
  });

  it("кілька listeners на одну job — кожен отримує events", () => {
    const store = new JobStore();
    const job = store.create();
    const a: number[] = [];
    const b: number[] = [];
    store.subscribe(job.id, (j) => a.push(j.progress));
    store.subscribe(job.id, (j) => b.push(j.progress));
    store.update(job.id, { progress: 25 });
    store.update(job.id, { progress: 75 });
    expect(a).toEqual([25, 75]);
    expect(b).toEqual([25, 75]);
  });
});
