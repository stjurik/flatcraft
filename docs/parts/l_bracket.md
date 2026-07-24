# Специфікація деталі: L-кронштейн

> Заповнений екземпляр бланка `docs/18_NEW_PART_SPEC.md`. Це **референс** —
> `l_bracket` вже реалізований у платформі (Phase 1.5, канонічний шаблон
> ADR-033/`docs/12_TEMPLATE_CONTRACT.md` §6 PR 5); документ відтворює
> існуючу поведінку заднім числом як зразок для заповнення майбутніх
> `docs/parts/<slug>.md`. Саме цей файл `agy` перевірятиме
> adversarial-кейсами на Етапі 3 (`docs/promts/master-registry-track.md`).

## 1. Ідентифікація

- **name_uk**: L-кронштейн
- **name_en**: L-bracket
- **slug**: `l_bracket`
- **type**: базова деталь (canonical форма — `corner_angle` і `wall_shelf`
  розширюють той самий L-профіль отворами/бортиком, `docs/12` §6)

## 2. Геометрія

- **Референси**: `packages/types/src/templates/l-bracket.ts` (Zod-контракт),
  `workers/cad/flatcraft_cad/templates/l_bracket.py` (CadQuery-builder),
  `workers/cad/flatcraft_cad/unfold.py::unfold_l_bracket` (розгортка).
- **Сегменти (Flanges)**:
  - `F1` (leg A): вертикальна полиця, задає `zmax` bounding box'а.
  - `F2` (leg B): горизонтальна полиця, задає `xmax` bounding box'а.
- **Гиби (Bends)**:
  - `B1` (між F1 та F2): Кут **90°** (MVP — лише 90°, `bend_angle_deg` є
    `z.literal(90)`), Напрямок **down** (default; `bend_direction`,
    Hotfix 2.10.e — поле є в моделі, але generic-редактор його не показує),
    Радіус **лише з фіксованого набору {1, 2.5, 4, 5} мм** (не довільний
    діапазон — `bend_radius_mm: z.union([z.literal(1), ...])`).

## 3. Параметризація

| UI Група | Назва (UA)             | Змінна (slug)    | Одиниці | Min                                         | Max  | Default | Крок                               | Тип (Edit/Fixed)                                       |
| :------- | :--------------------- | :--------------- | :------ | :------------------------------------------ | :--- | :------ | :--------------------------------- | :----------------------------------------------------- |
| Розміри  | Висота полиці A        | `legA_mm`        | мм      | 20                                          | 500  | 60      | 1.0                                | Editable                                               |
| Розміри  | Глибина полиці B       | `legB_mm`        | мм      | 20                                          | 500  | 60      | 1.0                                | Editable                                               |
| Розміри  | Ширина (довжина гиба)  | `width_mm`       | мм      | 20                                          | 3000 | 100     | 1.0                                | Editable                                               |
| Гиб      | Внутрішній радіус гиба | `bend_radius_mm` | мм      | {1,2.5,4,5} — фіксований набір, не діапазон | 2.5  | —       | Editable (select, не number input) |
| Гиб      | Кут гиба               | `bend_angle_deg` | °       | 90                                          | 90   | 90      | —                                  | Fixed (MVP: лише 90°, `z.literal(90)`)                 |
| Гиб      | Напрям згину           | `bend_direction` | —       | up/down                                     | —    | down    | —                                  | Fixed на рівні generic-редактора (Hotfix 2.10.e)       |
| Отвори   | Отвори                 | `holes`          | —       | 0                                           | 20   | []      | —                                  | Editable — масив об'єктів, не скалярне поле (§4 нижче) |

## 4. Отвори та Перфорація

- **Патерн**: Задані координати (не grid) — довільний масив `holes[]`, без
  auto-layout.
- **Форма отворів**: Круглі.
- **Параметри отворів** (кожен елемент `holes[]`):
  - `leg`: `"A"` (вертикальна полиця) або `"B"` (горизонтальна) — на якій
    полиці розміщено отвір.
  - `distance_from_edge_mm`: відстань від найближчого зовнішнього краю
    полиці, мм, **min 5**.
  - `distance_from_bend_mm`: відстань від лінії гиба (центр-до-центру), мм,
    **min 5**. Додатково — формула `hole_to_bend_distance` з
    `docs/07_BEND_MACHINE_SPEC.md` §3: `a × thickness_mm + inner_radius_mm`
    (коефіцієнт `a` залежить від матеріалу, напр. `cold_rolled_steel: 2.0`).
  - `diameter_mm`: **2–50 мм**.
- **Розташування**: до **20 отворів** сумарно на F1+F2 (`holes.max(20)`).

## 5. Специфічні обмеження (Валідація)

- **Мінімальна полиця**: після гиба (`flat_a`/`flat_b`, §8) — **≥ 7.5 мм**
  (`spec.global.min_flange_mm`, `packages/cad-engine/src/validators/bend.ts`).
- **Колізії**: `flat_a = legA_mm − T − R` і `flat_b = legB_mm − T − R`
  обидва мають бути **> 0** — інакше `unfold_l_bracket` кидає
  `ValueError("L-bracket legs too short for bend")`.
- **Радіус**: лише зі списку `{1, 2.5, 4, 5}` мм (Pydantic
  `field_validator` + Zod `union(literal)`) — довільне значення відхиляється
  до виклику воркера.
- **Кут**: лише **90°** у MVP.
- **Отвори**: `distance_from_edge_mm ≥ 5`, `distance_from_bend_mm ≥ 5` +
  `hole_to_bend_distance`-формула §4.

## 6. Матеріали та Товщини

- **Сумісність**: повна матриця бази матеріалів (`capability_matrix` у
  `packages/cad-engine/data/bend-machine-esi.yaml`) — усі 8 MVP-матеріалів,
  межі товщини/радіуса за таблицею того ж файлу.
- **Примітка для K-фактора**: стандартні значення з
  `docs/07_BEND_MACHINE_SPEC.md` §3 (`k_factor.default_by_material` +
  `ratio_correction` за `R_inner / thickness`) — для контрольного прикладу
  нижче докладний розрахунок.

## 7. Продуктовий шар (UX/UI)

- **Use Cases**: Базовий L-кронштейн для кріплення полиць, балок, меблевих
  з'єднань — canonical форма, на яку спираються `corner_angle` (той самий
  профіль + auto-grid отворів) і `wall_shelf` (профіль + передній бортик).
- **Fixed параметри**: наразі жодного продукту (ADR-027) на базі `l_bracket`
  не заведено в `packages/db/src/seed.ts` — лише part-mode
  (`/templates/l_bracket`, усі поля editable). `bend_angle_deg` і
  `bend_direction` зафіксовані на рівні самого шаблону (MVP-обмеження), не
  продукту.
- **Прев'ю**: `/template-previews/l_bracket.png` (вже існує,
  `packages/db/src/seed.ts`).

## 8. Контрольний приклад (Test Fixture / Golden Source)

**Вхідні параметри:**

- Матеріал: **cold_rolled_steel**
- Товщина (T): **2.0 мм**
- Радіус гиба (R): **2.5 мм**
- Змінні:
  - `legA_mm`: **60 мм**
  - `legB_mm`: **60 мм**
  - `width_mm`: **100 мм**
  - `bend_angle_deg`: **90°**
  - `holes`: **[]**

**Очікувані розрахунки (за реальним `unfold_l_bracket()`,
`workers/cad/flatcraft_cad/unfold.py:252-282` — точніша за спрощений
pseudocode `docs/07_BEND_MACHINE_SPEC.md` §5):**

- **K-фактор**: `k_factor.default_by_material.cold_rolled_steel` = **0.40**
  (`docs/07_BEND_MACHINE_SPEC.md` §3). `ratio_correction` за
  `R/T = 2.5/2 = 1.25` потрапляє у діапазон `[1.0, 3.0)` →
  `multiplier = 1.00` → K лишається **0.40** (без корекції).
- **Bend Allowance (BA)** = `(π/180) × 90 × (R + K×T)` =
  `(π/2) × (2.5 + 0.4×2)` = `(π/2) × 3.3` ≈ **5.183628 мм**.
- **Довжина розгортки (Flat length)**:
  - `flat_a = legA_mm − T − R = 60 − 2 − 2.5 = 55.5 мм`
  - `flat_b = legB_mm − T − R = 60 − 2 − 2.5 = 55.5 мм`
  - `L_flat = flat_b + BA + flat_a = 55.5 + 5.183628 + 55.5` ≈
    **116.183628 мм**
  - Позиція лінії гиба від краю `flat_b`: `flat_b + BA/2 = 55.5 + 2.591814`
    ≈ **58.091814 мм**
- **Габарити готової деталі (Bounding Box)**: **60 (legB, X) × 100 (width,
  Y) × 60 (legA, Z) мм**
- **Маса (приблизна)**: `profile_area ≈ T×(legA+legB−T) = 2×(60+60−2) = 236
мм²` → `volume ≈ 236×100 = 23 600 мм³ = 23.6 см³` → `mass ≈ 23.6 × 7.85
г/см³` ≈ **185.3 г** (щільність сталі; дуга у внутрішньому куті трохи
  зменшує реальний об'єм — допуск ~5%, `test_l_bracket.py::
test_volume_близько_до_аналітичного`).

**Перевірено проти byte-детермінованого golden fixture**
(`workers/cad/tests/snapshots/dxf/l_bracket_60x60_t2_r25.json`,
`test_dxf_export.py:422`): зовнішній контур `LWPOLYLINE`
`(0,0)→(116.183628,0)→(116.183628,100)→(0,100)`, лінія гиба `BEND_LINES` при
`x=58.091814` — **точний збіг** з розрахунком вище.
