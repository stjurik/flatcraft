# Вхід для agy — ТЕСТ-ІНЖЕНЕР (Run 7 Master Registry Track, Етап 1)

Ти — незалежний тест-інженер (окремий vendor, Gemini). Твоя роль тут:
знайти прогалини в conformance-suite і запропонувати adversarial-тести на
межах, які могла пропустити модель (Claude), що сама писала і код, і тести.

НЕ використовуй жодних command/bash/terminal інструментів — лише `read_file`
і `write_file`. Увесь контекст, потрібний тобі, вже є у цьому файлі нижче.

## Завдання

**(а) Прогалини.** Порівняй перелік перевірок нижче (docs/12 §3 + CLAUDE.md §7)
з наведеним кодом conformance-suite. Які інваріанти НЕ покриваються жодним
тестом зараз? Збережи список у
`/home/yurii/hart/docs/promts/inputs/agy-conformance-gaps.md`.

**(б) 8-12 adversarial-кейсів.** Проти наведеної нижче bend-machine spec
(`bend-machine-esi.yaml`) і двох Zod-схем (`l-bracket.ts`, `perforated-panel.ts`)
— запропонуй 8-12 кейсів на межах: t=max з R=min для товщини, полиця рівно
7.5 мм (`min_flange_mm`), pitch≈діаметр отвору (перфорація), стики діапазонів
capability_matrix (напр.ت=2.5 vs t=3.0 — різні allowed_inner_radius_mm).
Для КОЖНОГО кейсу вкажи: вхідні параметри (JSON), яке same geometry/поле
перевіряється, і ОЧІКУВАННЯ — прийнято чи відхилено-з-кодом (конкретний код
помилки, якщо є — дивись `ProfileIssueCode`/`ValidationError.code` нижче).
Збережи у `/home/yurii/hart/docs/promts/inputs/testcases-registry.md` як
markdown-таблицю: `# | вхід (JSON) | що перевіряється | очікування | код помилки`.

НЕ пиши в жодні інші файли. Не запускай жодних інструментів окрім read_file
(цей файл вже містить усе) і write_file (лише 2 файли вище).

---

## 1. Перелік перевірок, які МАЄ покривати conformance-suite

### docs/12_TEMPLATE_CONTRACT.md §3 (4 автогенеровані перевірки на slug)

1. Schema parity TS↔Python (property-based) + slug parity.
2. DXF/PDF детермінізм (фіксований seed → фіксовані байти).
3. Render-gate (invalid params → fallback, не крах).
4. e2e smoke (Playwright, /templates/{slug}).
5. React-free import у apps/api (§3.5).

### CLAUDE.md §7 (CAD-обмеження, «Перевіряти при кожній зміні параметрів моделі»)

1. Товщина у дозволеному діапазоні (`bend-machine-esi.yaml` → `capability_matrix[].thickness_mm`).
2. Радіус гиба ≥ мін. для (матеріал, товщина) — `allowed_inner_radius_mm`.
3. Полиця після гиба ≥ 7.5 мм (`global.min_flange_mm`).
4. Габарит у площі заготовки ≤ 3050 × макс. ширина листа (`global.max_force_t`/`max_bend_length_mm`).
5. Перетинів геометрії немає (CadQuery isValid — Python-side, не в TS conformance).
6. Напрям згину (UP/DOWN) заданий для кожного гибу.

---

## 2. Код conformance-suite (Run 7 Етап 1, packages/templates/test/)

### packages/templates/test/registry-invariants.test.ts

```ts
/**
 * Conformance-suite — структурні інваріанти + render-gate (docs/12_TEMPLATE_CONTRACT.md
 * §3.3). Автогенерується з `Object.keys(TEMPLATE_REGISTRY)` — з порожнім
 * реєстром (Run 7 Етап 1) іде 0 ітерацій `describe.each` (зелено, не пропуск).
 */
import { describe, expect, test } from "vitest";

import type { TemplateDefinition } from "../src/definition.js";
import { TEMPLATE_REGISTRY } from "../src/registry.js";

const entries = Object.entries(TEMPLATE_REGISTRY) as Array<[string, TemplateDefinition<unknown>]>;

describe.each(entries)("registry invariants — %s", (slug, def) => {
  test("slug у визначенні збігається з ключем реєстру", () => {
    expect(def.slug).toBe(slug);
  });

  test("defaults проходять власну schema", () => {
    expect(def.schema.safeParse(def.defaults).success).toBe(true);
  });

  test("capabilities непорожній", () => {
    expect(def.capabilities.length).toBeGreaterThan(0);
  });

  test("labels.uk і labels.en непорожні (ADR-037 §5 Consequence)", () => {
    expect(def.labels.uk.length).toBeGreaterThan(0);
    expect(def.labels.en.length).toBeGreaterThan(0);
  });

  test("render-gate: усі валідатори мовчать на дефолтних параметрах", () => {
    for (const validator of def.validators) {
      expect(validator(def.defaults, 2)).toHaveLength(0);
    }
  });

  test("render-gate: явно неможлива товщина стрельне хоча б одним валідатором (якщо валідатори є)", () => {
    if (def.validators.length === 0) return;
    const issues = def.validators.flatMap((validator) => validator(def.defaults, 999));
    expect(issues.length).toBeGreaterThan(0);
  });
});
```

### packages/templates/test/registry-schema-property.test.ts

```ts
/**
 * Schema-паритет, property-based слайс. Повний крос-мовний прогін (TS
 * fast-check → JSON → Python Pydantic model_validate_json) ВІДКЛАДЕНО до
 * першого реального шаблону (Етап 2) — CI-жоби test (Node) і python
 * (Python) окремі, без спільного runtime. Зараз перевіряється лише JSON
 * round-trip дефолтів проти власної Zod-схеми.
 */
import fc from "fast-check";
import { describe, test } from "vitest";

import type { TemplateDefinition } from "../src/definition.js";
import { TEMPLATE_REGISTRY } from "../src/registry.js";

const entries = Object.entries(TEMPLATE_REGISTRY) as Array<[string, TemplateDefinition<unknown>]>;

describe.each(entries)("schema property — %s", (_slug, def) => {
  test("JSON round-trip дефолтів лишається валідним", () => {
    fc.assert(
      fc.property(fc.constant(def.defaults), (sample) => {
        const roundTripped: unknown = JSON.parse(JSON.stringify(sample));
        return def.schema.safeParse(roundTripped).success;
      }),
    );
  });
});
```

### packages/templates/test/registry-fixture-sync.test.ts (+ дзеркальний Python-тест)

```ts
// Slug-паритет TS ↔ Python через спільний JSON-фікстур-файл
// (workers/cad/tests/fixtures/ts_registry_slugs.json), генерований
// tools/scripts/export-registry.ts. Порівнює Object.keys(TEMPLATE_REGISTRY)
// проти фікстури; дзеркальний Python-тест звіряє TEMPLATES.keys().
```

### ЩО НЕ РЕАЛІЗОВАНО в Етапі 1 (для контексту, не питання)

- Жодного зареєстрованого шаблону — `TEMPLATE_REGISTRY = {}`. Уся вищенаведена
  conformance-suite зараз виконує 0 ітерацій на template-специфічних тестах
  (registry порожній — «нуль змін поведінки», docs/12 §6 PR2).
- Adversarial-кейси, які ти пропонуєш нижче, мають цілитись у ІСНУЮЧУ
  (пре-registry) валідаційну логіку — `packages/cad-engine/src/validators/*`
  і Python `workers/cad/flatcraft_cad/validate/*` — яку майбутні per-template
  registry-тести (Етап 2) успадкують без змін. Мета: перевірити, що спільне
  ядро валідації (bend-machine spec + profile-валідатор) само по собі коректне
  на межах, ДО того, як шаблони на нього спираються через реєстр.

---

## 3. bend-machine-esi.yaml (єдине джерело істини для матриці гиба)

```yaml
machine:
  vendor: "ТОВ ЕСІ ПРОММЕТАЛ"
  model: "reference-100t"

global:
  max_force_t: 100
  min_flange_mm: 7.5
  angle_tolerance_deg: 0.25
  allowed_angles_deg: [30, 45, 60, 90, 120, 135]
  default_angle_deg: 90

material_groups:
  carbon_and_stainless_and_alu_and_galv:
    members:
      [
        cold_rolled_steel,
        hot_rolled_steel,
        stainless_304,
        stainless_430,
        aluminum_5754,
        aluminum_amg3,
        galvanized_steel,
      ]
  carbon_alu_galv_only:
    members: [cold_rolled_steel, hot_rolled_steel, aluminum_5754, aluminum_amg3, galvanized_steel]

capability_matrix:
  - thickness_mm: 1.0
    group: carbon_and_stainless_and_alu_and_galv
    allowed_inner_radius_mm: [1.0, 2.5]
    max_bend_length_mm: 3000
  - thickness_mm: 1.5
    group: carbon_and_stainless_and_alu_and_galv
    allowed_inner_radius_mm: [1.0, 2.5, 4.0]
    max_bend_length_mm: 3000
  - thickness_mm: 1.8
    group: carbon_and_stainless_and_alu_and_galv
    allowed_inner_radius_mm: [1.0, 2.5, 4.0]
    max_bend_length_mm: 3000
  - thickness_mm: 2.0
    group: carbon_and_stainless_and_alu_and_galv
    allowed_inner_radius_mm: [1.0, 2.5, 4.0]
    max_bend_length_mm: 3000
  - thickness_mm: 2.5
    group: carbon_and_stainless_and_alu_and_galv
    allowed_inner_radius_mm: [2.5, 4.0]
    max_bend_length_mm: 3000
  - thickness_mm: 3.0
    group: carbon_and_stainless_and_alu_and_galv
    allowed_inner_radius_mm: [2.5, 4.0]
    max_bend_length_mm: 3000
  - thickness_mm: 4.0
    group: carbon_and_stainless_and_alu_and_galv
    allowed_inner_radius_mm: [2.5, 4.0]
    max_bend_length_mm: 2500
  - thickness_mm: 5.0
    group: carbon_and_stainless_and_alu_and_galv
    allowed_inner_radius_mm: [4.0, 5.0]
    max_bend_length_mm: 2500
  - thickness_mm: 6.0
    group: carbon_and_stainless_and_alu_and_galv
    allowed_inner_radius_mm: [4.0, 5.0]
    max_bend_length_mm: 2300
  - thickness_mm: 8.0
    group: carbon_and_stainless_and_alu_and_galv
    allowed_inner_radius_mm: [5.0]
    max_bend_length_mm: 1000
  - thickness_mm: 10.0
    group: carbon_alu_galv_only
    allowed_inner_radius_mm: [5.0]
    inner_radius_max_mm: 1000
    max_bend_length_mm: 1000

k_factor:
  default_by_material:
    cold_rolled_steel: 0.40
    hot_rolled_steel: 0.42
    galvanized_steel: 0.40
    stainless_304: 0.45
    stainless_430: 0.44
    aluminum_5754: 0.33
    aluminum_amg3: 0.33
    copper: 0.38
    brass: 0.38
  ratio_correction:
    - { ratio_min: 0.0, ratio_max: 1.0, multiplier: 0.85 }
    - { ratio_min: 1.0, ratio_max: 3.0, multiplier: 1.00 }
    - { ratio_min: 3.0, ratio_max: 999.0, multiplier: 1.10 }

hole_to_bend_distance:
  formula: "a * thickness_mm + inner_radius_mm"
  coefficient_by_material:
    cold_rolled_steel: 2.0
    hot_rolled_steel: 2.5
    galvanized_steel: 2.0
    stainless_304: 2.5
    stainless_430: 2.5
    aluminum_5754: 1.5
    aluminum_amg3: 1.5
    copper: 1.5
    brass: 1.5
```

---

## 4. Схема l_bracket (packages/types/src/templates/l-bracket.ts)

```ts
// MVP-обмеження: лише 90°, радіус з {1, 2.5, 4, 5} мм, до 20 отворів на полицю.
const HoleSchema = z.object({
  leg: z.enum(["A", "B"]),
  distance_from_edge_mm: z.number().min(5),
  distance_from_bend_mm: z.number().min(5),
  diameter_mm: z.number().min(2).max(50),
});

export const LBracketParametersSchema = z.object({
  legA_mm: z.number().min(20).max(500),
  legB_mm: z.number().min(20).max(500),
  bend_radius_mm: z.union([z.literal(1), z.literal(2.5), z.literal(4), z.literal(5)]),
  bend_angle_deg: z.literal(90),
  bend_direction: BendDirectionSchema.default("down"),
  width_mm: z.number().min(20).max(3000),
  holes: z.array(HoleSchema).max(20),
});

// Профіль валідний, коли: legA_mm >= thickness_mm + bend_radius_mm
//                     і   legB_mm >= thickness_mm + bend_radius_mm
// (packages/cad-engine/src/validators/profile.ts, "LEG_TOO_SHORT" якщо ні)
```

## 5. Схема perforated_panel (packages/types/src/templates/perforated-panel.ts)

```ts
export const PerforatedPanelParametersSchema = z.object({
  length_mm: z.number().min(100).max(3000),
  width_mm: z.number().min(100).max(3000),
  hole_shape: z.enum(["circle", "square"]),
  hole_size_mm: z.number().min(3).max(30), // діаметр (circle) або сторона (square)
  pitch_x_mm: z.number().min(10).max(200), // крок між центрами отворів по X
  pitch_y_mm: z.number().min(10).max(200), // крок між центрами отворів по Y
  margin_mm: z.number().min(5).max(100), // відступ від країв до центра крайнього отвору
  rib_height_mm: z.number().min(15).max(50),
  bend_radius_mm: z.union([z.literal(1), z.literal(2.5), z.literal(4), z.literal(5)]),
  bend_angle_deg: z.literal(90),
});

// Профіль валідний, коли: rib_height_mm > thickness_mm + bend_radius_mm
// (packages/cad-engine/src/validators/profile.ts, "FLANGE_TOO_SHORT" якщо ні)
// Perforation-валідатор (packages/cad-engine/src/validators/perforation.ts)
// перевіряє grid: чи влазять отвори з заданим pitch/margin/hole_size у
// length_mm × width_mm без накладання і без виходу за margin.
```

## 6. Коди помилок (для колонки «очікування»)

- `ProfileIssueCode`: `LEG_TOO_SHORT | FLANGE_TOO_SHORT | OFFSET_TOO_SMALL | SHELF_TOO_SHORT`
  (packages/cad-engine/src/validators/profile.ts).
- Bend-matrix `ValidationError.code`: `bend.inner_radius_not_allowed | bend.thickness_unsupported
| bend.material_not_in_group | bend.angle_not_allowed | bend.flange_too_short
| bend.exceeds_max_bend_length` (packages/cad-engine/src/validators/bend.ts,
  мапляться у RFC 9457 `ProblemError` через `export-gate.ts`: `RADIUS_NOT_ALLOWED`,
  `THICKNESS_NOT_SUPPORTED`, `MATERIAL_NOT_ALLOWED`, `ANGLE_NOT_ALLOWED`,
  `FLANGE_TOO_SHORT`, `BEND_LENGTH_EXCEEDED`).
- Perforation issue codes: дивись `packages/cad-engine/src/validators/perforation.ts`
  (якщо потрібен точний список — заклади припущення явно у своїй відповіді,
  не вигадуй код, якого не бачив; якщо не впевнений — напиши "TBD, перевір
  perforation.ts" замість вигаданого коду).
