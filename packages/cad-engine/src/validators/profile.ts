/**
 * Profile-валідатор (Hotfix 2.9.f, ADR-026): геометрична валідність профілю
 * листозгинального виробу ДО побудови 3D-mesh.
 *
 * Єдине джерело істини, що **дзеркалить assertion'и** з
 * `packages/ui/src/3d-viewport/geometry.ts` (`build*ShapeCommands`). Ті builder'и
 * кидають `throw` на невалідних розмірах (напр. `legA_mm` < товщина+радіус) →
 * uncaught у React-дереві → крах R3F (white-screen). Цей валідатор повертає
 * issues БЕЗ throw, тож:
 *   - render-gate у viewport'ах не рендерить `<Canvas>` при issues (apps/web);
 *   - форма показує банер + блокує експорт;
 *   - Fastify-gate (ADR-019) та Python-worker дзеркалять те саме (defense-in-depth).
 *
 * Strictness ТОЧНО як у geometry.ts (інакше gate і throw розійдуться на межі):
 *   - legs (l_bracket/corner_angle): валідно при `leg >= t + r`   (assert `t+r > leg`)
 *   - z/wall flanges, offset, shelf: валідно при `value > threshold` (assert `value <= ...`)
 *
 * Browser-safe: жодного `node:*`, чиста функція.
 *
 * Розміри типуємо як `number` (не Zod-літерали схем) — валідатор має приймати
 * будь-яке введене значення, зокрема невалідне. Реальні `*Parameters` типи
 * (де `bend_radius_mm` — літерал-union дозволених радіусів) лишаються assignable.
 */
export type ProfileIssueCode =
  | "LEG_TOO_SHORT"
  | "FLANGE_TOO_SHORT"
  | "OFFSET_TOO_SMALL"
  | "SHELF_TOO_SHORT";

export interface ProfileIssue {
  readonly code: ProfileIssueCode;
  /** Логічне ім'я виміру: legA, legB, top_flange, bottom_flange, offset, back_height, shelf_depth. */
  readonly which: string;
  /** Граничне значення (мм). Для inclusive-правил — мінімум; для строгих — поріг, який треба перевищити. */
  readonly min: number;
  /** Введене значення (мм). */
  readonly got: number;
  /** Дружнє україномовне повідомлення (підказка, як виправити). */
  readonly message: string;
}

interface LegProfile {
  readonly legA_mm: number;
  readonly legB_mm: number;
  readonly bend_radius_mm: number;
}
interface ZProfile {
  readonly top_flange_mm: number;
  readonly bottom_flange_mm: number;
  readonly offset_mm: number;
  readonly bend_radius_mm: number;
}
interface WallProfile {
  readonly back_height_mm: number;
  readonly shelf_depth_mm: number;
  readonly front_lip_mm: number;
  readonly bend_radius_mm: number;
}

export type ProfileValidationInput =
  | {
      readonly templateSlug: "l_bracket" | "corner_angle";
      readonly parameters: LegProfile;
      readonly thicknessMm: number;
    }
  | {
      readonly templateSlug: "z_bracket";
      readonly parameters: ZProfile;
      readonly thicknessMm: number;
    }
  | {
      readonly templateSlug: "wall_shelf";
      readonly parameters: WallProfile;
      readonly thicknessMm: number;
    }
  | {
      readonly templateSlug: "perforated_panel";
      readonly parameters: Readonly<Record<string, number>>;
      readonly thicknessMm: number;
    };

/** Округлення до 0.001 мм без хвостових нулів — для повідомлень. */
function fmt(n: number): string {
  return String(Math.round(n * 1000) / 1000);
}

const LABEL: Record<string, string> = {
  legA: "Довжина плеча A",
  legB: "Довжина плеча B",
  top_flange: "Верхня полиця",
  bottom_flange: "Нижня полиця",
  offset: "Вертикальний offset",
  back_height: "Висота задньої стінки",
  shelf_depth: "Глибина полиці",
};

/** «Збільшіть «X» до мінімум N мм (товщина T + радіус R).» — inclusive-правило (>=). */
function minMessage(which: string, min: number, t: number, r: number): string {
  return `Збільшіть «${LABEL[which] ?? which}» до мінімум ${fmt(min)} мм (товщина ${fmt(t)} + радіус ${fmt(r)}).`;
}

/** «Збільшіть «X»: потрібно більше за N мм …» — строге правило (>). */
function gtMessage(which: string, threshold: number, t: number, r: number): string {
  return `Збільшіть «${LABEL[which] ?? which}»: потрібно більше за ${fmt(threshold)} мм (товщина ${fmt(t)} + радіус ${fmt(r)}).`;
}

/**
 * Валідує геометричну достатність профілю. Повертає [] коли валідно або коли
 * шаблон без гибу (perforated_panel). Дзеркалить geometry.ts один-в-один.
 */
export function validateProfile(input: ProfileValidationInput): ProfileIssue[] {
  const t = input.thicknessMm;
  // thicknessMm <= 0 — захист від ділення/невалідного стану (як `t <= 0` throw у geometry.ts).
  if (t <= 0) return [];

  const issues: ProfileIssue[] = [];

  switch (input.templateSlug) {
    case "l_bracket":
    case "corner_angle": {
      const { legA_mm: a, legB_mm: b, bend_radius_mm: r } = input.parameters;
      const min = t + r;
      // geometry.ts: `t + r > leg` → throw. Валідно при leg >= t+r.
      if (t + r > a) {
        issues.push({
          code: "LEG_TOO_SHORT",
          which: "legA",
          min,
          got: a,
          message: minMessage("legA", min, t, r),
        });
      }
      if (t + r > b) {
        issues.push({
          code: "LEG_TOO_SHORT",
          which: "legB",
          min,
          got: b,
          message: minMessage("legB", min, t, r),
        });
      }
      return issues;
    }

    case "z_bracket": {
      const {
        top_flange_mm: tf,
        bottom_flange_mm: bf,
        offset_mm: off,
        bend_radius_mm: r,
      } = input.parameters;
      const min = t + r;
      // geometry.ts: `off <= r` → throw. Валідно при off > r.
      if (off <= r) {
        issues.push({
          code: "OFFSET_TOO_SMALL",
          which: "offset",
          min: r,
          got: off,
          message: gtMessage("offset", r, t, r),
        });
      }
      // `tf <= t+r` / `bf <= t+r` → throw. Валідно при flange > t+r.
      if (tf <= min) {
        issues.push({
          code: "FLANGE_TOO_SHORT",
          which: "top_flange",
          min,
          got: tf,
          message: gtMessage("top_flange", min, t, r),
        });
      }
      if (bf <= min) {
        issues.push({
          code: "FLANGE_TOO_SHORT",
          which: "bottom_flange",
          min,
          got: bf,
          message: gtMessage("bottom_flange", min, t, r),
        });
      }
      return issues;
    }

    case "wall_shelf": {
      const {
        back_height_mm: bh,
        shelf_depth_mm: sd,
        front_lip_mm: lip,
        bend_radius_mm: r,
      } = input.parameters;
      const min = t + r;
      // `bh <= t+r` → throw. Валідно при bh > t+r.
      if (bh <= min) {
        issues.push({
          code: "FLANGE_TOO_SHORT",
          which: "back_height",
          min,
          got: bh,
          message: gtMessage("back_height", min, t, r),
        });
      }
      // lip>0: shelf має вистачити на 2 гиби (sd > 2(t+r)); інакше на 1 (sd > t+r).
      const shelfThreshold = lip > 0 ? 2 * min : min;
      if (sd <= shelfThreshold) {
        issues.push({
          code: "SHELF_TOO_SHORT",
          which: "shelf_depth",
          min: shelfThreshold,
          got: sd,
          message: gtMessage("shelf_depth", shelfThreshold, t, r),
        });
      }
      return issues;
    }

    case "perforated_panel":
      // Без гибу — немає assertion'у в geometry.ts, профіль завжди валідний.
      return issues;
  }
}
