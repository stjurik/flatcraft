/**
 * Юніт-тести perforation-валідатора: крок отворів проти розміру отвору.
 *
 * Правило: pitch > hole_size → валідно; pitch <= hole_size → HOLES_OVERLAP.
 * Перевіряємо обидва шаблони (square → hole_size_mm, round → hole_diameter_mm),
 * обидві осі, межу торкання та еталонний дефект каталожної панелі.
 */
import { describe, expect, it } from "vitest";

import { validatePerforation } from "./perforation.js";

describe("validatePerforation — perforated_panel_square", () => {
  const base = {
    length_mm: 200,
    width_mm: 150,
    thickness_mm: 1.5,
    hole_size_mm: 8,
    pitch_x_mm: 30,
    pitch_y_mm: 30,
    margin_mm: 15,
  };

  it("крок більший за сторону отвору → []", () => {
    expect(
      validatePerforation({ templateSlug: "perforated_panel_square", parameters: base }),
    ).toEqual([]);
  });

  it("pitch_y менший за сторону → HOLES_OVERLAP для pitch_y_mm", () => {
    const issues = validatePerforation({
      templateSlug: "perforated_panel_square",
      parameters: { ...base, hole_size_mm: 20, pitch_y_mm: 10 },
    });
    expect(issues).toHaveLength(1);
    expect(issues[0]).toMatchObject({
      code: "HOLES_OVERLAP",
      which: "pitch_y_mm",
      min: 20,
      got: 10,
    });
    expect(issues[0]?.message).toContain("сторону");
  });

  it("pitch рівно == сторона (торкання, нульовий місток) → invalid", () => {
    const issues = validatePerforation({
      templateSlug: "perforated_panel_square",
      parameters: { ...base, hole_size_mm: 30, pitch_x_mm: 30, pitch_y_mm: 30 },
    });
    expect(issues).toHaveLength(2);
    expect(issues.map((i) => i.which)).toEqual(["pitch_x_mm", "pitch_y_mm"]);
  });

  it("еталонна декоративна панель з каталогу (□20, pitch 27/10) → лише pitch_y", () => {
    const issues = validatePerforation({
      templateSlug: "perforated_panel_square",
      parameters: {
        length_mm: 300,
        width_mm: 100,
        thickness_mm: 2,
        hole_size_mm: 20,
        pitch_x_mm: 27,
        pitch_y_mm: 10,
        margin_mm: 15,
      },
    });
    expect(issues).toHaveLength(1);
    expect(issues[0]?.which).toBe("pitch_y_mm");
  });
});

describe("validatePerforation — perforated_panel (round)", () => {
  const base = {
    length_mm: 200,
    width_mm: 150,
    thickness_mm: 1.5,
    hole_diameter_mm: 8,
    pitch_x_mm: 30,
    pitch_y_mm: 30,
    margin_mm: 15,
  };

  it("крок більший за діаметр → []", () => {
    expect(validatePerforation({ templateSlug: "perforated_panel", parameters: base })).toEqual([]);
  });

  it("обидва кроки менші за діаметр → дві HOLES_OVERLAP, message згадує діаметр", () => {
    const issues = validatePerforation({
      templateSlug: "perforated_panel",
      parameters: { ...base, hole_diameter_mm: 25, pitch_x_mm: 12, pitch_y_mm: 12 },
    });
    expect(issues).toHaveLength(2);
    expect(issues[0]?.message).toContain("діаметр");
  });

  it("невизначений розмір отвору → [] (відсіється Zod окремо)", () => {
    const issues = validatePerforation({
      templateSlug: "perforated_panel",
      parameters: { pitch_x_mm: 5, pitch_y_mm: 5 },
    });
    expect(issues).toEqual([]);
  });
});
