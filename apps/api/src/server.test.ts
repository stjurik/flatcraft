import { describe, expect, it } from "vitest";

import { createServer } from "./server.js";

describe("Fastify server", () => {
  it("GET /health → 200 і повертає валідний health-payload", async () => {
    const app = await createServer({ logger: false });
    try {
      const res = await app.inject({ method: "GET", url: "/health" });
      expect(res.statusCode).toBe(200);
      const body = res.json<{
        status: string;
        uptime: number;
        version: string;
      }>();
      expect(body.status).toBe("ok");
      expect(typeof body.uptime).toBe("number");
      expect(body.uptime).toBeGreaterThanOrEqual(0);
      expect(typeof body.version).toBe("string");
    } finally {
      await app.close();
    }
  });

  it("невідомий URL повертає 404", async () => {
    const app = await createServer({ logger: false });
    try {
      const res = await app.inject({ method: "GET", url: "/this-does-not-exist" });
      expect(res.statusCode).toBe(404);
    } finally {
      await app.close();
    }
  });

  it("ставить sane дефолти безпеки: x-powered-by не виставляється", async () => {
    const app = await createServer({ logger: false });
    try {
      const res = await app.inject({ method: "GET", url: "/health" });
      // Fastify за замовчуванням не додає X-Powered-By; перевіряємо інваріант.
      expect(res.headers["x-powered-by"]).toBeUndefined();
    } finally {
      await app.close();
    }
  });
});
