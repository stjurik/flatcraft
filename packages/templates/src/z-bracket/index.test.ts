/**
 * Регресія для issue #247 ч.1: `holes` лишається прихованим полем
 * (`HIDDEN_FIELDS`), але summary-плейсхолдер, що обіцяв майбутній редактор
 * отворів, видалено (редактора отворів немає, DXF/PDF їх не рендерять —
 * напис обіцяв неіснуючу функціональність).
 */
import { describe, expect, it } from "vitest";

import { zBracketDefinition } from "./index.js";

describe("zBracketDefinition — holes placeholder видалено (issue #247 ч.1)", () => {
  it("extraControls не містить testId auto-form-holes-placeholder", () => {
    const control = zBracketDefinition.ui.extraControls?.find(
      (c) => "testId" in c && c.testId === "auto-form-holes-placeholder",
    );
    expect(control).toBeUndefined();
  });

  it("holes лишається прихованим полем (API/гейт експорту не змінено)", () => {
    expect(zBracketDefinition.ui.visibleFields).not.toContain("holes");
  });
});
