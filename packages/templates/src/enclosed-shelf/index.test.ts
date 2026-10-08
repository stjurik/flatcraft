/**
 * Регресія для `enclosedShelfDefinition` (Run 7 Master Registry Track, Етап
 * 2, шоста міграція) — паритет з видаленим `enclosed-shelf-editor.tsx`:
 * `bends`/`side_perforation`/`stiffening_rib` поза generic AutoForm, summary
 * на дефолтах — той самий текст, що показував старий editor.
 */
import { describe, expect, it } from "vitest";

import { enclosedShelfDefinition } from "./index.js";

describe("enclosedShelfDefinition — visibleFields", () => {
  it("ховає bends, side_perforation, stiffening_rib (nested/масив — поза generic AutoForm)", () => {
    for (const hidden of ["bends", "side_perforation", "stiffening_rib"]) {
      expect(enclosedShelfDefinition.ui.visibleFields).not.toContain(hidden);
    }
  });

  it("показує width_mm, depth_mm, bend_radius_mm", () => {
    for (const visible of ["width_mm", "depth_mm", "bend_radius_mm"]) {
      expect(enclosedShelfDefinition.ui.visibleFields).toContain(visible);
    }
  });
});

describe("enclosedShelfDefinition — summary (testId enclosed-shelf-summary)", () => {
  const summaryControl = enclosedShelfDefinition.ui.extraControls?.find(
    (c) => c.kind === "summary",
  );

  it("зареєстрований з testId enclosed-shelf-summary", () => {
    expect(summaryControl?.testId).toBe("enclosed-shelf-summary");
  });

  it("на дефолтних параметрах — «3 гиби UP · без перфорації»", () => {
    if (summaryControl?.kind !== "summary") throw new Error("summary control not found");
    expect(summaryControl.render(enclosedShelfDefinition.defaults)).toBe(
      "3 гиби UP · без перфорації",
    );
  });
});
