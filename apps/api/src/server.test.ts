import { describe, expect, it } from "vitest";

import { createServer } from "./server.js";

// Dummy URL — postgres-js створює пул лазі, реальне з'єднання тільки при
// першому запиті. /health і 404-тести не торкаються db, тому жодних
// з'єднань не відкривається.
const DUMMY_DB_URL = "postgresql://dummy:dummy@127.0.0.1:1/dummy";

describe("Fastify server", () => {
  it("GET /health → 200 і повертає валідний health-payload", async () => {
    const app = await createServer({ logger: false, dbUrl: DUMMY_DB_URL });
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
    const app = await createServer({ logger: false, dbUrl: DUMMY_DB_URL });
    try {
      const res = await app.inject({ method: "GET", url: "/this-does-not-exist" });
      expect(res.statusCode).toBe(404);
    } finally {
      await app.close();
    }
  });

  it("ставить sane дефолти безпеки: x-powered-by не виставляється", async () => {
    const app = await createServer({ logger: false, dbUrl: DUMMY_DB_URL });
    try {
      const res = await app.inject({ method: "GET", url: "/health" });
      // Fastify за замовчуванням не додає X-Powered-By; перевіряємо інваріант.
      expect(res.headers["x-powered-by"]).toBeUndefined();
    } finally {
      await app.close();
    }
  });
});
