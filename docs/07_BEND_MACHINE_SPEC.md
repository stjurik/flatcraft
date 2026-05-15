# 07. Bend Machine Spec — ТОВ «ЕСІ ПРОММЕТАЛ» (референсне обладнання MVP)

> Джерело: офіційна таблиця можливостей листозгинальних машин ТОВ «ЕСІ ПРОММЕТАЛ» (фото надане замовником, 2026-05-08).
> Цей файл — **єдине джерело істини** для CAD-валідатора. Будь-яка зміна тут → автоматичні правки у `packages/cad-engine` та регресійні тести.

## 1. Принцип

CAD-валідатор використовує цю специфікацію щоб для кожного гиба перевірити:

1. Чи **матеріал × товщина** взагалі підтримується.
2. Чи обраний користувачем **радіус гиба** (`R_inner`) є у переліку дозволених для цієї пари.
3. Чи **довжина гиба** (`L_bend`) не перевищує дозволену для цієї товщини.
4. Чи виконуються побічні умови (наприклад: «без отворів близько до лінії гибу» — для деяких комбінацій).

Якщо хоч одна перевірка не пройшла → експорт блокується, у UI підсвічується конкретне обмеження.

## 2. Матриця можливостей (вихідні дані з фото)

| Матеріал | Товщина S, мм | Радіус внутр. R, мм | Макс. довжина L, мм | Примітка |
|----------|---------------|---------------------|---------------------|----------|
| ст.3, нерж, алюм, оц | 1.0 | 1.0; 2.5 | 3000 | — |
| ст.3, нерж, алюм, оц | 1.5; 1.8 | 1.0; 2.5; 4.0 | 3000 | R=4 → без отворів близько до лінії гибу |
| ст.3, нерж, алюм, оц | 2.0 | 1.0; 2.5; 4.0 | 3000 | R=4 → без отворів близько до лінії гибу |
| ст.3, нерж, алюм, оц | 2.5 | 2.5; 4.0 | 3000 | R=4 → без отворів близько до лінії гибу |
| ст.3, нерж, алюм, оц | 3.0 | 2.5; 4.0 | 3000 | R=4 → без отворів близько до лінії гибу |
| ст.3, нерж, алюм, оц | 4.0 | 2.5; 4.0 | 2500 | — |
| ст.3, нерж, алюм, оц | 5.0 | 4.0; 5.0 | 2500 | — |
| ст.3, нерж, алюм, оц | 6.0 | 4.0; 5.0 | 2300 | — |
| ст.3, нерж, алюм, оц | 8.0 | 5.0 | 1000 | — |
| ст.3, алюм, оц | 10.0 | 5.0 – 1000.0 | 1000 | без нержавійки; великий радіус — спец. вальцювання |
| ст.3, нерж | пруток Ø 12, 14, 16, 20 | 12.0 | — | поза MVP (інший інструмент) |
| ст.3, нерж, оц | плющення 0.5 – 2.0 | — | 2400 | поза MVP (інша операція) |

**Скорочення матеріалів** (як у документі ESI):
- `ст.3` → конструкційна сталь (DC01/08кп холоднокатана, DC01/St37 гарячекатана) — у нашій базі це матеріали `cold_rolled_steel`, `hot_rolled_steel`.
- `нерж` → нержавійка AISI 304/430 — `stainless_304`, `stainless_430`.
- `алюм` → алюміній АМг3/5754 — `aluminum_5754`, `aluminum_amg3`.
- `оц` → оцинкована сталь — `galvanized_steel`.

**Не входить у MVP:**
- Мідь і латунь — з опитувальника замовник позначив, але ESI не вказує параметри. Виносимо в `docs/00_OPEN_QUESTIONS.md` (потрібен окремий референс).
- Прутки і плющення — інший інструмент, відкладаємо на v2.

## 3. Машиночитаємий формат (`bend-machine.yaml`)

Цей блок один-в-один лежатиме у `packages/cad-engine/data/bend-machine-esi.yaml` і завантажується валідатором. Будь-які зміни у фізичних параметрах → редагуємо тільки цей YAML, ніяких magic numbers у коді.

```yaml
# packages/cad-engine/data/bend-machine-esi.yaml
machine:
  vendor: "ТОВ ЕСІ ПРОММЕТАЛ"
  model: "reference-100t"
  source: "docs/07_BEND_MACHINE_SPEC.md"
  source_date: "2026-05-08"

global:
  max_force_t: 100
  min_flange_mm: 7.5         # мін. ширина полиці після гиба
  angle_tolerance_deg: 0.25  # ±0.25°
  allowed_angles_deg: [30, 45, 60, 90, 120, 135]  # стартовий список; розширюватимемо
  default_angle_deg: 90

# Сумісність матеріалу із групою «ст.3, нерж, алюм, оц» з фото.
# Кожен матеріал у нашій БД мапиться на одну з груп, а група має таблицю можливостей.
material_groups:
  carbon_and_stainless_and_alu_and_galv:
    members: [cold_rolled_steel, hot_rolled_steel, stainless_304, stainless_430, aluminum_5754, aluminum_amg3, galvanized_steel]
  carbon_alu_galv_only:
    members: [cold_rolled_steel, hot_rolled_steel, aluminum_5754, aluminum_amg3, galvanized_steel]

# Кожен запис: для якої групи матеріалів і товщини — які радіуси і яка макс. довжина гиба.
capability_matrix:
  - thickness_mm: 1.0
    group: carbon_and_stainless_and_alu_and_galv
    allowed_inner_radius_mm: [1.0, 2.5]
    max_bend_length_mm: 3000

  - thickness_mm: 1.5
    group: carbon_and_stainless_and_alu_and_galv
    allowed_inner_radius_mm: [1.0, 2.5, 4.0]
    max_bend_length_mm: 3000
    notes:
      r4_no_holes_near_bend_line: true

  - thickness_mm: 1.8
    group: carbon_and_stainless_and_alu_and_galv
    allowed_inner_radius_mm: [1.0, 2.5, 4.0]
    max_bend_length_mm: 3000
    notes:
      r4_no_holes_near_bend_line: true

  - thickness_mm: 2.0
    group: carbon_and_stainless_and_alu_and_galv
    allowed_inner_radius_mm: [1.0, 2.5, 4.0]
    max_bend_length_mm: 3000
    notes:
      r4_no_holes_near_bend_line: true

  - thickness_mm: 2.5
    group: carbon_and_stainless_and_alu_and_galv
    allowed_inner_radius_mm: [2.5, 4.0]
    max_bend_length_mm: 3000
    notes:
      r4_no_holes_near_bend_line: true

  - thickness_mm: 3.0
    group: carbon_and_stainless_and_alu_and_galv
    allowed_inner_radius_mm: [2.5, 4.0]
    max_bend_length_mm: 3000
    notes:
      r4_no_holes_near_bend_line: true

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
    allowed_inner_radius_mm: [5.0]   # від 5 і вище аж до R=1000 (вальцювання)
    inner_radius_max_mm: 1000
    max_bend_length_mm: 1000

# K-фактор: емпіричні дефолти, доки не калібруємо під реальну машину.
# Залежить від матеріалу, товщини і радіуса. Формула стартова: K = K_base(material) × correction(R/S).
k_factor:
  default_by_material:
    cold_rolled_steel: 0.40
    hot_rolled_steel:  0.42
    galvanized_steel:  0.40
    stainless_304:     0.45
    stainless_430:     0.44
    aluminum_5754:     0.33
    aluminum_amg3:     0.33
    copper:            0.38   # потребує калібрування
    brass:             0.38   # потребує калібрування
  # Корекційний множник залежно від співвідношення R_inner / S
  # (стандартна апроксимація DIN 6935; буде перекалібровано після пілота)
  ratio_correction:
    - { ratio_min: 0.0, ratio_max: 1.0, multiplier: 0.85 }
    - { ratio_min: 1.0, ratio_max: 3.0, multiplier: 1.00 }
    - { ratio_min: 3.0, ratio_max: 999.0, multiplier: 1.10 }

# Мін. відстань від отвору до лінії гиба, щоб не «з'їхав» край.
# Базова формула: distance >= a × S + R_inner, де a залежить від матеріалу.
hole_to_bend_distance:
  formula: "a * thickness_mm + inner_radius_mm"
  coefficient_by_material:
    cold_rolled_steel: 2.0
    hot_rolled_steel:  2.5
    galvanized_steel:  2.0
    stainless_304:     2.5
    stainless_430:     2.5
    aluminum_5754:     1.5
    aluminum_amg3:     1.5
    copper:            1.5
    brass:             1.5
```

## 4. Алгоритм валідації (псевдокод для `cad-engine`)

```ts
function validateBend(bend: Bend, sheet: Sheet, spec: BendMachineSpec): ValidationResult[] {
  const errors: ValidationResult[] = [];

  // 1. Знайти запис у capability_matrix по товщині
  const row = spec.capability_matrix.find(r =>
    r.thickness_mm === sheet.thickness_mm &&
    spec.material_groups[r.group].members.includes(sheet.material_code)
  );
  if (!row) {
    errors.push({ code: "MATERIAL_THICKNESS_NOT_SUPPORTED", ... });
    return errors;
  }

  // 2. Радіус
  const rOk = row.allowed_inner_radius_mm.includes(bend.inner_radius_mm)
    || (row.inner_radius_max_mm && bend.inner_radius_mm <= row.inner_radius_max_mm);
  if (!rOk) errors.push({ code: "RADIUS_NOT_ALLOWED", ... });

  // 3. Довжина гиба
  if (bend.length_mm > row.max_bend_length_mm) {
    errors.push({ code: "BEND_LENGTH_EXCEEDED", ... });
  }

  // 4. Полиця після гиба
  if (bend.flange_mm < spec.global.min_flange_mm) {
    errors.push({ code: "FLANGE_TOO_SHORT", ... });
  }

  // 5. Кут гиба
  if (!spec.global.allowed_angles_deg.includes(bend.angle_deg)) {
    errors.push({ code: "ANGLE_NOT_ALLOWED", ... });
  }

  // 6. Близькість отворів до лінії гиба (якщо це обмеження активне для запису)
  if (row.notes?.r4_no_holes_near_bend_line && bend.inner_radius_mm === 4.0) {
    for (const hole of bend.nearbyHoles) {
      const minDist = computeMinHoleDistance(sheet.material_code, sheet.thickness_mm, bend.inner_radius_mm, spec);
      if (hole.distance_to_bend_mm < minDist) {
        errors.push({ code: "HOLE_TOO_CLOSE_TO_BEND", ... });
      }
    }
  }

  return errors;
}
```

## 5. Розгортка (bend allowance)

Для розгортки використовуємо стандартну формулу через k-фактор:

```
BA = (π / 180) × bend_angle_deg × (R_inner + K × thickness)
flat_length = leg1 + leg2 + BA - 2 × thickness × tan(bend_angle_deg / 2)   // компенсація для зовнішнього контуру
```

K береться з `k_factor.default_by_material[material]` і множиться на `ratio_correction` за `R_inner / thickness`.

## 6. Що ще потрібно у вас уточнити (виноситься у `00_OPEN_QUESTIONS.md`)

1. Параметри гибки для **міді** і **латуні** (фото від ESI їх не покриває). Якщо ESI їх не гне взагалі — викидаємо з MVP-матеріалів.
2. Чи потрібна підтримка **кутів окрім 90°** з самого MVP (фаска 45°, 135°)? Я заклав список `[30, 45, 60, 90, 120, 135]`, але якщо MVP — тільки 90°, спростимо валідатор.
3. Чи має машина обмеження **на кількість гибів на одній заготовці** (часом інструмент не доходить до повторного гиба)? Поки не обмежуємо.
4. Лазерна різка — макс. товщина по матеріалах не вказана. Поки беру 8 мм для всіх (узгодити з реальним обладнанням).
5. **Калібрування k-фактора** — після перших 5–10 реальних виробів треба буде заміряти фактичну розгортку і скоригувати таблицю. Це окремий процес.

---

_Оновлюйте цей файл, якщо зміняться характеристики обладнання — тести у `cad-engine` автоматично перевірять регресії._
