/**
 * In-memory store для export-jobs з pub/sub.
 *
 * Phase 2.8: одна Node-replica, без persistence. На restart активні
 * jobs губляться — клієнт побачить EventSource reconnection і
 * `not_found` для job, що зник. BullMQ + Redis persistence — Phase 5.
 *
 * pub/sub: subscribe(jobId, cb) → cb на кожен update; повертає
 * `unsubscribe`. SSE handler підписується, шле події у потік, чистить
 * на close.
 */
import type { ExportResponse, JobStatus } from "@flatcraft/types";
import { randomUUID } from "node:crypto";

export interface ExportJob {
  readonly id: string;
  readonly status: JobStatus;
  /** 0..100. */
  readonly progress: number;
  readonly createdAt: Date;
  readonly result?: ExportResponse;
  readonly error?: string;
}

type Listener = (job: ExportJob) => void;

export class JobStore {
  private readonly jobs = new Map<string, ExportJob>();
  private readonly listeners = new Map<string, Set<Listener>>();
  private readonly retentionMs: number;

  constructor(options: { retentionMs?: number } = {}) {
    this.retentionMs = options.retentionMs ?? 5 * 60 * 1000; // 5 хв
  }

  create(): ExportJob {
    const job: ExportJob = {
      id: randomUUID(),
      status: "queued",
      progress: 0,
      createdAt: new Date(),
    };
    this.jobs.set(job.id, job);
    return job;
  }

  get(id: string): ExportJob | undefined {
    return this.jobs.get(id);
  }

  update(id: string, patch: Partial<Omit<ExportJob, "id" | "createdAt">>): ExportJob | undefined {
    const prev = this.jobs.get(id);
    if (!prev) return undefined;
    const next: ExportJob = { ...prev, ...patch };
    this.jobs.set(id, next);
    for (const cb of this.listeners.get(id) ?? []) cb(next);
    if (next.status === "done" || next.status === "failed") {
      // GC через retention, щоб client встиг прочитати фінальну подію.
      setTimeout(() => {
        this.jobs.delete(id);
        this.listeners.delete(id);
      }, this.retentionMs).unref?.();
    }
    return next;
  }

  subscribe(id: string, cb: Listener): () => void {
    let set = this.listeners.get(id);
    if (!set) {
      set = new Set();
      this.listeners.set(id, set);
    }
    set.add(cb);
    return () => {
      set?.delete(cb);
      if (set && set.size === 0) this.listeners.delete(id);
    };
  }
}
