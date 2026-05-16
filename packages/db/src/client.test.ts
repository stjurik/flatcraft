import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { createClient } from "./client.js";

const ORIGINAL_DATABASE_URL = process.env["DATABASE_URL"];

describe("createClient", () => {
  beforeEach(() => {
    delete process.env["DATABASE_URL"];
  });

  afterEach(() => {
    if (ORIGINAL_DATABASE_URL === undefined) {
      delete process.env["DATABASE_URL"];
    } else {
      process.env["DATABASE_URL"] = ORIGINAL_DATABASE_URL;
    }
  });

  it("кидає помилку, якщо DATABASE_URL не заданий і url не переданий явно", () => {
    expect(() => createClient()).toThrowError(/DATABASE_URL/);
  });

  it("повертає клієнт з пулом postgres і drizzle-інстансом", async () => {
    // postgres-js створює пул лазі — реальне з'єднання не відкривається,
    // поки не виконається запит. Тому тест безпечний без БД.
    const client = createClient("postgresql://u:p@127.0.0.1:5432/x");
    try {
      expect(client.db).toBeDefined();
      expect(client.sql).toBeDefined();
      expect(typeof client.close).toBe("function");
    } finally {
      await client.close();
    }
  });

  it("читає DATABASE_URL із process.env, якщо url не переданий", async () => {
    process.env["DATABASE_URL"] = "postgresql://u:p@127.0.0.1:5432/x";
    const client = createClient();
    try {
      expect(client.db).toBeDefined();
    } finally {
      await client.close();
    }
  });
});
