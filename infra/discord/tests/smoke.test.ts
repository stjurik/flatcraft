import { describe, expect, it } from "vitest";

// Smoke: workspace зібрано, vitest запускається, ESM-резолюція працює.
describe("workspace smoke", () => {
  it("runs vitest in ESM mode", () => {
    expect(import.meta.url).toContain("infra/discord/tests");
  });
});
