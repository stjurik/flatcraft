/**
 * Perforation-валідатор: геометрична коректність grid отворів перфо-панелі.
 *
 * Окремий концерн від `validateProfile` (той — про достатність плеча/полиці
 * відносно гибу, дзеркало geometry.ts проти крашу R3F). Тут — про наповненість
 * робочої площини отворами: якщо крок (pitch) не більший за розмір отвору,
 * сусідні отвори перетинаються і зливаються у суцільний проріз — заготовка
 * фізично інша за те, що рахує BOM («N окремих отворів»).
 *
 * Правило: для НЕперетину потрібен додатний місток (ligament) між отворами:
 *   pitch > hole_size   (валідно)
 *   pitch <= hole_size  (отвори торкаються/перетинаються → invalid)
 * де hole_size = `hole_size_mm` (сторона квадрата при hole_shape='square' або
 * діаметр при 'circle'). Перевірка по кожній осі окремо (pitch_x, pitch_y).
 *
 * Browser-safe: жодного `node:*`, чиста функція. Дзеркалиться у Python
 * (`workers/cad/flatcraft_cad/validate/perforation.py`) для defense-in-depth:
 * клієнт (UX-банер) + Fastify-gate + cad-worker (остання лінія) — ADR-019/026.
 */
export type PerforationIssueCode = "HOLES_OVERLAP";

export interface PerforationIssue {
  readonly code: PerforationIssueCode;
  /** Поле з проблемою: `pitch_x_mm` або `pitch_y_mm`. */
  readonly which: string;
  /** Поріг, який крок має перевищити (= розмір отвору, мм). */
  readonly min: number;
  /** Введений крок (мм). */
  readonly got: number;
  /** Дружнє україномовне повідомлення (підказка, як виправити). */
  readonly message: string;
}

export interface PerforationValidationInput {
  readonly templateSlug: "perforated_panel";
  readonly parameters: Readonly<Record<string, number | string>>;
}

const AXIS_LABEL: Record<string, string> = {
  pitch_x_mm: "Крок X",
  pitch_y_mm: "Крок Y",
};

/** Округлення до 0.001 мм без хвостових нулів — для повідомлень. */
function fmt(n: number): string {
  return String(Math.round(n * 1000) / 1000);
}

function overlapMessage(which: string, pitch: number, holeSize: number, shapeWord: string): string {
  return (
    `Збільшіть «${AXIS_LABEL[which] ?? which}»: крок ${fmt(pitch)} мм має бути більший за ` +
    `${shapeWord} отвору ${fmt(holeSize)} мм — інакше сусідні отвори перетинаються.`
  );
}

/**
 * Валідує grid перфорації. Повертає [] коли валідно (або коли розмір отвору
 * невідомий/непозитивний — це відсіється Zod-діапазонами окремо).
 */
export function validatePerforation(input: PerforationValidationInput): PerforationIssue[] {
  const p = input.parameters;
  // Уніфікований шаблон (ADR-031): hole_size = hole_size_mm; слово у повідомленні
  // («сторону»/«діаметр») — за hole_shape.
  const holeSize = typeof p.hole_size_mm === "number" ? p.hole_size_mm : undefined;
  const shapeWord = p.hole_shape === "circle" ? "діаметр" : "сторону";

  if (holeSize === undefined || holeSize <= 0) return [];

  const issues: PerforationIssue[] = [];
  const check = (which: "pitch_x_mm" | "pitch_y_mm"): void => {
    const pitch = p[which];
    if (typeof pitch !== "number") return;
    // Валідно при pitch > holeSize. pitch <= holeSize → торкання/перетин.
    if (pitch <= holeSize) {
      issues.push({
        code: "HOLES_OVERLAP",
        which,
        min: holeSize,
        got: pitch,
        message: overlapMessage(which, pitch, holeSize, shapeWord),
      });
    }
  };
  check("pitch_x_mm");
  check("pitch_y_mm");
  return issues;
}
