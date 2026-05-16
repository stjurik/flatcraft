import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { runMigrations } from "./migrate.js";

const ORIGINAL = process.env["DATABASE_URL"];

describe("runMigrations", () => {
  beforeEach(() => {
    delete process.env["DATABASE_URL"];
  });

  afterEach(() => {
    if (ORIGINAL === undefined) {
      delete process.env["DATABASE_URL"];
    } else {
      process.env["DATABASE_URL"] = ORIGINAL;
    }
  });

  it("кидає помилку, якщо DATABASE_URL не заданий", async () => {
    await expect(runMigrations()).rejects.toThrow(/DATABASE_URL/);
  });
});
