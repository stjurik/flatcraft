/**
 * Юніт-тести POST /feedback/:exportId.
 *
 * Без БД (app.db undefined) — гілка "unit-режим" телеметрії. Інтеграційні
 * тести з testcontainers, які перевіряють INSERT у `export_feedback` +
 * 404 на невідомий export_id + rate-limit, з'являться після drizzle-міграції
 * `export_feedback` (яку yurii зробить вручну, як #55).
 */
import type { EventPayload } from "@flatcraft/types";
import { describe, expect, it } from "vitest";

import type { Telemetry } from "../lib/telemetry.js";
import { createServer } from "../server.js";

const DUMMY_DB_URL = "postgresql://dummy:dummy@127.0.0.1:1/dummy";

function recordingTelemetry(): { telemetry: Telemetry; events: EventPayload[] } {
  const events: EventPayload[] = [];
  return {
    events,
    telemetry: {
      async writeEvent(payload) {
        events.push(payload);
      },
      async insertExport() {},
      async completeExport() {},
    },
  };
}

const VALID_EXPORT_ID = "11111111-2222-3333-4444-555555555555";

describe("POST /feedback/:exportId", () => {
  it("outcome=made без коментаря → 200 + telemetry event з correct params", async () => {
    const { telemetry, events } = recordingTelemetry();
    const app = await createServer({ logger: false, dbUrl: DUMMY_DB_URL, telemetry });
    try {
      const res = await app.inject({
        method: "POST",
        url: `/feedback/${VALID_EXPORT_ID}`,
        headers: { "content-type": "application/json" },
        payload: { outcome: "made", locale: "uk" },
      });
      expect(res.statusCode).toBe(200);
      expect(res.json()).toEqual({ status: "received" });
      expect(events).toHaveLength(1);
      const first = events[0];
      expect(first).toBeDefined();
      expect(first).toMatchObject({
        event_type: "feedback_submitted",
        params: {
          outcome: "made",
          has_deviation_description: false,
          has_comment: false,
          locale: "uk",
        },
      });
    } finally {
      await app.close();
    }
  });

  it("outcome=deviations з deviation-текстом → params.has_deviation_description=true", async () => {
    const { telemetry, events } = recordingTelemetry();
    const app = await createServer({ logger: false, dbUrl: DUMMY_DB_URL, telemetry });
    try {
      const res = await app.inject({
        method: "POST",
        url: `/feedback/${VALID_EXPORT_ID}`,
        headers: { "content-type": "application/json" },
        payload: {
          outcome: "deviations",
          deviation_description: "полиця +0.3 мм",
          locale: "en",
        },
      });
      expect(res.statusCode).toBe(200);
      const first = events[0];
      expect(first).toBeDefined();
      expect(first).toMatchObject({
        event_type: "feedback_submitted",
        params: {
          outcome: "deviations",
          has_deviation_description: true,
          has_comment: false,
          locale: "en",
        },
      });
    } finally {
      await app.close();
    }
  });

  it("outcome=failed без коментаря → 400 (superRefine валідація)", async () => {
    const { telemetry, events } = recordingTelemetry();
    const app = await createServer({ logger: false, dbUrl: DUMMY_DB_URL, telemetry });
    try {
      const res = await app.inject({
        method: "POST",
        url: `/feedback/${VALID_EXPORT_ID}`,
        headers: { "content-type": "application/json" },
        payload: { outcome: "failed", locale: "uk" },
      });
      expect(res.statusCode).toBe(400);
      expect(events).toHaveLength(0);
    } finally {
      await app.close();
    }
  });

  it("невалідний UUID у path → 400 (Zod-валідація params)", async () => {
    const { telemetry, events } = recordingTelemetry();
    const app = await createServer({ logger: false, dbUrl: DUMMY_DB_URL, telemetry });
    try {
      const res = await app.inject({
        method: "POST",
        url: "/feedback/not-a-uuid",
        headers: { "content-type": "application/json" },
        payload: { outcome: "made", locale: "uk" },
      });
      expect(res.statusCode).toBe(400);
      expect(events).toHaveLength(0);
    } finally {
      await app.close();
    }
  });

  it("невалідний outcome → 400 (Zod enum)", async () => {
    const { telemetry, events } = recordingTelemetry();
    const app = await createServer({ logger: false, dbUrl: DUMMY_DB_URL, telemetry });
    try {
      const res = await app.inject({
        method: "POST",
        url: `/feedback/${VALID_EXPORT_ID}`,
        headers: { "content-type": "application/json" },
        payload: { outcome: "bogus", locale: "uk" },
      });
      expect(res.statusCode).toBe(400);
      expect(events).toHaveLength(0);
    } finally {
      await app.close();
    }
  });

  it("comment > 1000 символів → 400 (Zod max)", async () => {
    const { telemetry, events } = recordingTelemetry();
    const app = await createServer({ logger: false, dbUrl: DUMMY_DB_URL, telemetry });
    try {
      const res = await app.inject({
        method: "POST",
        url: `/feedback/${VALID_EXPORT_ID}`,
        headers: { "content-type": "application/json" },
        payload: {
          outcome: "deviations",
          comment: "a".repeat(1001),
          locale: "uk",
        },
      });
      expect(res.statusCode).toBe(400);
      expect(events).toHaveLength(0);
    } finally {
      await app.close();
    }
  });
});
