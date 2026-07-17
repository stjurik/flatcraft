import { describe, expect, it } from "vitest";

import { buildDigest, chunkForDiscord, type DigestData } from "./digest.js";

const EMPTY_WEEK: DigestData = {
  periodStart: "2026-06-29",
  periodEnd: "2026-07-05",
  validationErrors: [],
  failedExports: [],
  durations: [],
  feedback: [],
  sentry: [],
  volume: { uniqueSessions: 0, exportsDone: 0, exportsFailed: 0, validationRejections: 0 },
};

const TYPICAL_WEEK: DigestData = {
  periodStart: "2026-06-29",
  periodEnd: "2026-07-05",
  validationErrors: [
    { errorCode: "RADIUS_NOT_ALLOWED", count: 12, templates: ["z_bracket", "l_bracket"] },
    { errorCode: "HOLES_OVERLAP", count: 3, templates: ["perforated_panel"] },
  ],
  failedExports: [
    {
      templateSlug: "wall_shelf",
      errorCode: "CAD_WORKER_500",
      count: 2,
      exampleTs: "2026-07-02T10:00:00Z",
    },
  ],
  durations: [
    { stage: "export (повний, DXF+PDF)", p95Ms: 4200, budgetMs: 5000 },
    { stage: "cad (worker round-trip)", p95Ms: 6100, budgetMs: 5000 },
  ],
  feedback: [],
  sentry: [],
  volume: { uniqueSessions: 47, exportsDone: 88, exportsFailed: 2, validationRejections: 15 },
};

const DEVIATION_WEEK: DigestData = {
  ...TYPICAL_WEEK,
  feedback: [
    {
      templateSlug: "l_bracket",
      outcome: "deviations",
      deviationSummary: "полиця +0.3 мм",
    },
    {
      templateSlug: "perforated_panel",
      outcome: "failed",
      deviationSummary: "отвори не збіглись",
    },
    {
      templateSlug: "wall_shelf",
      outcome: "made",
      deviationSummary: null,
    },
  ],
};

describe("buildDigest", () => {
  it("порожній тиждень → плейсхолдери + нульовий обсяг", () => {
    const md = buildDigest(EMPTY_WEEK);
    expect(md).toContain("# hart · щотижневий digest (2026-06-29 … 2026-07-05)");
    // Кожна з 5 таблиць — порожня.
    expect(md.match(/_\(порожньо\)_/g)?.length).toBe(5);
    expect(md).toContain("унікальних сесій: 0 · експортів: 0 (0 done / 0 failed)");
  });

  it("типовий тиждень → таблиці + бюджет-статуси (✅ у межах, ⚠️ понад)", () => {
    const md = buildDigest(TYPICAL_WEEK);
    expect(md).toContain("RADIUS_NOT_ALLOWED");
    expect(md).toContain("z_bracket, l_bracket");
    expect(md).toContain("CAD_WORKER_500");
    // export p95 4.2c ≤ 5c → ✅; cad p95 6.1c > 5c → ⚠️.
    expect(md).toContain("| export (повний, DXF+PDF) | 4.20 c | 5.00 c | ✅ |");
    expect(md).toContain("| cad (worker round-trip) | 6.10 c | 5.00 c | ⚠️ |");
    expect(md).toContain(
      "унікальних сесій: 47 · експортів: 90 (88 done / 2 failed) · відхилень валідації: 15",
    );
  });

  it("тиждень з deviation-репортом → секція фідбеку заповнена", () => {
    const md = buildDigest(DEVIATION_WEEK);
    expect(md).toContain("| l_bracket | deviations | полиця +0.3 мм |");
    expect(md).toContain("| perforated_panel | failed | отвори не збіглись |");
    // outcome="made" з null-summary — прочерк:
    expect(md).toContain("| wall_shelf | made | — |");
    // Лише Sentry-секція порожня (валідація/failed/тривалості/фідбек — заповнені).
    expect(md.match(/_\(порожньо\)_/g)?.length).toBe(1);
  });

  it("детермінований (той самий вхід → той самий вихід)", () => {
    expect(buildDigest(TYPICAL_WEEK)).toBe(buildDigest(TYPICAL_WEEK));
  });
});

describe("chunkForDiscord", () => {
  it("короткий markdown → один шматок", () => {
    expect(chunkForDiscord("hello")).toEqual(["hello"]);
  });

  it("довгий markdown → кілька шматків, кожен ≤ ліміту", () => {
    const md = Array.from({ length: 200 }, (_, i) => `рядок ${i}`).join("\n");
    const chunks = chunkForDiscord(md, 100);
    expect(chunks.length).toBeGreaterThan(1);
    for (const chunk of chunks) expect(chunk.length).toBeLessThanOrEqual(100);
  });

  it("рядок, довший за ліміт, жорстко ріжеться", () => {
    const chunks = chunkForDiscord("x".repeat(250), 100);
    expect(chunks).toEqual(["x".repeat(100), "x".repeat(100), "x".repeat(50)]);
  });
});
