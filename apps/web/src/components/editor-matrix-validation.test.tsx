/**
 * Hotfix 2.9.c (ADR-022): кожен editor-wrapper рендерить матричний банер.
 *
 * SSR-рендер (renderToString, як template-thumb.test) — web-suite працює без
 * jsdom. Перевіряємо банер для валідної vs матрично-невалідної (товщина, радіус)
 * комбінації: default-параметри мають bend_radius_mm=2.5, що недопустимо для
 * t=5 (дозволено [4, 5]) → червоний банер; t=2 → зелений.
 */
import {
  CORNER_ANGLE_DEFAULT_PARAMETERS,
  L_BRACKET_DEFAULT_PARAMETERS,
  WALL_SHELF_DEFAULT_PARAMETERS,
  Z_BRACKET_DEFAULT_PARAMETERS,
} from "@flatcraft/types";
import { renderToString } from "react-dom/server";
import { describe, expect, it } from "vitest";

// @flatcraft/ui аліасовано на стаб у vitest.config.ts (R3F 3d-viewport + dist —
// нестабільно у node). Тестуємо ВЛАСНУ логіку редактора (матричний банер); форму
// рендерить стаб-AutoForm (null).
import { CornerAngleEditor } from "./corner-angle-editor";
import { LBracketEditor } from "./l-bracket-editor";
import { WallShelfEditor } from "./wall-shelf-editor";
import { ZBracketEditor } from "./z-bracket-editor";

const noop = () => {};
const VALID_T = 2.0; // R=2.5 дозволено
const INVALID_T = 5.0; // R=2.5 недопустимо (дозволено 4, 5)

const cases = [
  {
    name: "LBracketEditor",
    render: (t: number) =>
      renderToString(
        <LBracketEditor
          value={L_BRACKET_DEFAULT_PARAMETERS}
          onChange={noop}
          materialCode="cold_rolled_steel"
          thicknessMm={t}
        />,
      ),
  },
  {
    name: "ZBracketEditor",
    render: (t: number) =>
      renderToString(
        <ZBracketEditor
          value={Z_BRACKET_DEFAULT_PARAMETERS}
          onChange={noop}
          materialCode="cold_rolled_steel"
          thicknessMm={t}
        />,
      ),
  },
  {
    name: "CornerAngleEditor",
    render: (t: number) =>
      renderToString(
        <CornerAngleEditor
          value={CORNER_ANGLE_DEFAULT_PARAMETERS}
          onChange={noop}
          materialCode="cold_rolled_steel"
          thicknessMm={t}
        />,
      ),
  },
  {
    name: "WallShelfEditor",
    render: (t: number) =>
      renderToString(
        <WallShelfEditor
          value={WALL_SHELF_DEFAULT_PARAMETERS}
          onChange={noop}
          materialCode="cold_rolled_steel"
          thicknessMm={t}
        />,
      ),
  },
] as const;

describe("editor матричний банер (Hotfix 2.9.c)", () => {
  for (const c of cases) {
    it(`${c.name}: валідна товщина → зелений банер, без помилок`, () => {
      const html = c.render(VALID_T);
      expect(html).toContain('data-testid="validation-ok"');
      expect(html).not.toContain('data-testid="validation-errors"');
    });

    it(`${c.name}: невалідний радіус для товщини → червоний банер з матричним повідомленням`, () => {
      const html = c.render(INVALID_T);
      expect(html).toContain('data-testid="validation-errors"');
      expect(html).not.toContain('data-testid="validation-ok"');
      // Матричне повідомлення згадує допустимі радіуси.
      expect(html).toContain("дозволено");
    });
  }
});
