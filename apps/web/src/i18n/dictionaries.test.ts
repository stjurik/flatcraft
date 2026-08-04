import { describe, expect, it } from "vitest";

import { dictionaries } from "./dictionaries";

/**
 * Паритет словників uk/en — інваріант ADR-037 §2 (CLAUDE.md §13): будь-який
 * ключ, доданий або видалений в одній локалі, має бути дзеркально відображений
 * у другій. TypeScript ловить це на рівні інтерфейсу `Dictionary`, але лише
 * доки обидва об'єкти анотовані — цей тест лишається робочим і тоді, коли
 * анотацію знімуть чи послаблять до `satisfies`.
 *
 * Кейси запропонував agy/Gemini у ролі Тест-інженера під час рев'ю PR #97
 * (видалення пункту «Telegram» із футера), верифіковані Claude.
 */
describe("dictionaries — паритет uk/en", () => {
  it("common.siteLinks має однаковий набір ключів у обох локалях", () => {
    const uk = Object.keys(dictionaries.uk.common.siteLinks).sort();
    const en = Object.keys(dictionaries.en.common.siteLinks).sort();
    expect(uk).toEqual(en);
  });

  it("common.siteLinks не містить осиротілого ключа telegram (PR #97)", () => {
    expect(dictionaries.uk.common.siteLinks).not.toHaveProperty("telegram");
    expect(dictionaries.en.common.siteLinks).not.toHaveProperty("telegram");
  });

  it("верхній рівень common має однаковий набір ключів у обох локалях", () => {
    const uk = Object.keys(dictionaries.uk.common).sort();
    const en = Object.keys(dictionaries.en.common).sort();
    expect(uk).toEqual(en);
  });
});
