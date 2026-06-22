# 05. Data Model

> Постгре 16 + Drizzle ORM. Усі ID — `uuid v7` (sortable + unique). Усі timestamps — `timestamptz` у UTC.
> Принцип: типобезпечні шлюзи між кодом і БД. Усе, що типу JSONB, валідується Zod-схемою на запис і на читання.

---

## 1. ER-діаграма (текстова)

```
users ──┬─< model_drafts >──┬── templates
        │                    │
        ├─< exports >────────┴── (artifacts in R2)
        │
        └─< usage_quota >── monthly counters
                  ▲
        donation_claims ──┘  (extends quota)

materials ─< material_thicknesses >─< template_compatibility >── templates
```

---

## 2. Сутності

### users

| Поле                | Тип           | Constraint                                    | Опис                            |
| ------------------- | ------------- | --------------------------------------------- | ------------------------------- |
| `id`                | `uuid`        | PK                                            | uuid v7                         |
| `email`             | `text`        | UNIQUE NOT NULL                               | lowercased на запис             |
| `email_verified_at` | `timestamptz` | NULL                                          | NULL = не верифіковано          |
| `password_hash`     | `text`        | NOT NULL для credentials, NULL для OAuth-only | argon2id                        |
| `display_name`      | `text`        | NULL                                          | для штампа на креслі            |
| `locale`            | `text`        | DEFAULT 'uk'                                  | `uk` \| `en`                    |
| `units`             | `text`        | DEFAULT 'mm'                                  | `mm` \| `inch`                  |
| `role`              | `text`        | DEFAULT 'user'                                | `guest` \| `user` \| `admin`    |
| `created_at`        | `timestamptz` | DEFAULT now()                                 |                                 |
| `deleted_at`        | `timestamptz` | NULL                                          | soft-delete (GDPR 30-day grace) |

**Індекси:** `email` (UNIQUE), `(role, created_at)` для адмінки.

---

### oauth_accounts

| Поле                  | Тип           | Constraint                      |
| --------------------- | ------------- | ------------------------------- |
| `id`                  | `uuid`        | PK                              |
| `user_id`             | `uuid`        | FK → users.id ON DELETE CASCADE |
| `provider`            | `text`        | `google` \| (later: `github`)   |
| `provider_account_id` | `text`        | google sub                      |
| `created_at`          | `timestamptz` |                                 |

**Індекси:** UNIQUE `(provider, provider_account_id)`.

---

### sessions

Зберігаємо refresh tokens. Access tokens — JWT короткі, у пам'яті.

| Поле                 | Тип           | Constraint                                          |
| -------------------- | ------------- | --------------------------------------------------- |
| `id`                 | `uuid`        | PK                                                  |
| `user_id`            | `uuid`        | FK → users.id                                       |
| `refresh_token_hash` | `text`        | sha256                                              |
| `user_agent`         | `text`        | для відображення в `/account/sessions`              |
| `ip_first_seen`      | `inet`        | НЕ зберігаємо постійно — обнуляємо через 24h (GDPR) |
| `expires_at`         | `timestamptz` |                                                     |
| `created_at`         | `timestamptz` |                                                     |
| `revoked_at`         | `timestamptz` |                                                     |

---

### materials

Довідник, що ми взагалі підтримуємо.

| Поле            | Тип            | Constraint   | Опис                                                     |
| --------------- | -------------- | ------------ | -------------------------------------------------------- |
| `id`            | `uuid`         | PK           |                                                          |
| `code`          | `text`         | UNIQUE       | `cold_rolled_steel`, `stainless_304`, `aluminum_5754`, … |
| `name_uk`       | `text`         | NOT NULL     | «Холоднокатана сталь DC01»                               |
| `name_en`       | `text`         | NOT NULL     | "Cold-rolled steel DC01"                                 |
| `density_kg_m3` | `numeric(7,2)` | NOT NULL     | для розрахунку маси                                      |
| `category`      | `text`         |              | `steel` \| `stainless` \| `aluminum` \| `non_ferrous`    |
| `is_active`     | `boolean`      | DEFAULT true | вмикаємо/вимикаємо у адмінці                             |

---

### material_thicknesses

Допустимі товщини (стандартний прайс-лист).

| Поле           | Тип            | Constraint        |
| -------------- | -------------- | ----------------- |
| `id`           | `uuid`         | PK                |
| `material_id`  | `uuid`         | FK → materials.id |
| `thickness_mm` | `numeric(4,2)` | NOT NULL          |
| `is_active`    | `boolean`      | DEFAULT true      |

UNIQUE `(material_id, thickness_mm)`.

---

### templates

Параметричні моделі. Сама геометрія — у Python-коді (`workers/cad/templates/`); у БД — метадані + Zod-схема параметрів.

| Поле                                | Тип           | Constraint                           |
| ----------------------------------- | ------------- | ------------------------------------ |
| `id`                                | `uuid`        | PK                                   |
| `slug`                              | `text`        | UNIQUE — `l_bracket`, `z_bracket`, … |
| `name_uk` / `name_en`               | `text`        |                                      |
| `description_uk` / `description_en` | `text`        | markdown                             |
| `version`                           | `int`         | для backward-compat draft-ів         |
| `parameters_schema`                 | `jsonb`       | Zod schema у JSON-Schema-форматі     |
| `default_parameters`                | `jsonb`       | стартові значення                    |
| `preview_image_url`                 | `text`        | у R2                                 |
| `is_published`                      | `boolean`     | DEFAULT false                        |
| `created_at` / `updated_at`         | `timestamptz` |                                      |

---

### template_compatibility

Які матеріали і товщини сумісні з шаблоном.

| Поле                                    | Тип            | Constraint |
| --------------------------------------- | -------------- | ---------- |
| `template_id`                           | `uuid`         | FK         |
| `material_id`                           | `uuid`         | FK         |
| `min_thickness_mm` / `max_thickness_mm` | `numeric(4,2)` |            |

PK `(template_id, material_id)`.

---

### model_drafts

Чернетка користувача — до експорту. Дозволяє повертатись до проєкту.

| Поле                        | Тип            | Constraint                                                |
| --------------------------- | -------------- | --------------------------------------------------------- |
| `id`                        | `uuid`         | PK                                                        |
| `user_id`                   | `uuid`         | FK (NULL для гостя — зберігається у localStorage)         |
| `template_id`               | `uuid`         | FK                                                        |
| `name`                      | `text`         | юзер-friendly назва, дефолт «Untitled»                    |
| `parameters`                | `jsonb`        | актуальні значення                                        |
| `material_id`               | `uuid`         | FK                                                        |
| `thickness_mm`              | `numeric(4,2)` |                                                           |
| `surface_finish`            | `text`         | NULL \| `raw` \| `painted`                                |
| `paint_ral`                 | `text`         | NULL \| RAL-код                                           |
| `validation_status`         | `text`         | `valid` \| `invalid` \| `unchecked`                       |
| `validation_errors`         | `jsonb`        | масив об'єктів `{ code, message_uk, message_en, fields }` |
| `created_at` / `updated_at` | `timestamptz`  |                                                           |

**Індекс:** `(user_id, updated_at DESC)`.

---

### exports

Метадані про згенеровані файли.

| Поле                          | Тип           | Constraint                                      |
| ----------------------------- | ------------- | ----------------------------------------------- |
| `id`                          | `uuid`        | PK                                              |
| `user_id`                     | `uuid`        | FK NOT NULL                                     |
| `draft_id`                    | `uuid`        | FK → model_drafts.id                            |
| `formats`                     | `text[]`      | `['dxf', 'pdf', 'step']`                        |
| `status`                      | `text`        | `queued` \| `running` \| `done` \| `failed`     |
| `r2_keys`                     | `jsonb`       | `{ dxf: '...', pdf: '...', step: '...' }`       |
| `bom`                         | `jsonb`       | бруто, маса, площа, к-сть гибів, площа покраски |
| `error_message`               | `text`        | NULL якщо успіх                                 |
| `created_at` / `completed_at` | `timestamptz` |                                                 |

**Індекс:** `(user_id, created_at DESC)`, `status` для черги.

---

### usage_quota

Лічильник на місяць.

| Поле           | Тип           | Constraint                         |
| -------------- | ------------- | ---------------------------------- |
| `user_id`      | `uuid`        | FK PK part 1                       |
| `period_start` | `date`        | PK part 2 (1-ше число місяця)      |
| `free_used`    | `int`         | DEFAULT 0                          |
| `free_limit`   | `int`         | DEFAULT 10                         |
| `bonus_until`  | `timestamptz` | NULL — якщо є активний донат-бонус |
| `updated_at`   | `timestamptz` |                                    |

PK = `(user_id, period_start)`.

---

### donation_claims

Користувач каже «я задонатив», адмін перевіряє.

| Поле                 | Тип             | Constraint                                              |
| -------------------- | --------------- | ------------------------------------------------------- |
| `id`                 | `uuid`          | PK                                                      |
| `user_id`            | `uuid`          | FK                                                      |
| `channel`            | `text`          | `monobank_banka` \| `united24` \| `usdt` \| `acquiring` |
| `claimed_amount_uah` | `numeric(10,2)` |                                                         |
| `proof_url`          | `text`          | R2 — скрін/PDF чек                                      |
| `status`             | `text`          | `pending` \| `approved` \| `rejected`                   |
| `verified_by`        | `uuid`          | FK → users.id (admin)                                   |
| `verified_at`        | `timestamptz`   |                                                         |
| `notes`              | `text`          |                                                         |
| `created_at`         | `timestamptz`   |                                                         |

При `approved` — створюємо/оновлюємо `usage_quota.bonus_until = now() + 30 days`.

---

### audit_log

Для GDPR DSR і безпеки.

| Поле         | Тип           | Constraint                                                           |
| ------------ | ------------- | -------------------------------------------------------------------- |
| `id`         | `uuid`        | PK                                                                   |
| `user_id`    | `uuid`        | FK NULL (системні події)                                             |
| `action`     | `text`        | `login`, `export.created`, `donation.approved`, `account.deleted`, … |
| `metadata`   | `jsonb`       | без PII                                                              |
| `created_at` | `timestamptz` |                                                                      |

---

## 3. Drizzle schema sketch (для першого PR)

```ts
// packages/db/src/schema.ts
import {
  pgTable,
  uuid,
  text,
  timestamp,
  boolean,
  integer,
  numeric,
  jsonb,
  date,
  inet,
} from "drizzle-orm/pg-core";

export const users = pgTable("users", {
  id: uuid("id").primaryKey().defaultRandom(),
  email: text("email").notNull().unique(),
  emailVerifiedAt: timestamp("email_verified_at", { withTimezone: true }),
  passwordHash: text("password_hash"),
  displayName: text("display_name"),
  locale: text("locale").notNull().default("uk"),
  units: text("units").notNull().default("mm"),
  role: text("role").notNull().default("user"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  deletedAt: timestamp("deleted_at", { withTimezone: true }),
});

export const materials = pgTable("materials", {
  id: uuid("id").primaryKey().defaultRandom(),
  code: text("code").notNull().unique(),
  nameUk: text("name_uk").notNull(),
  nameEn: text("name_en").notNull(),
  densityKgM3: numeric("density_kg_m3", { precision: 7, scale: 2 }).notNull(),
  category: text("category").notNull(),
  isActive: boolean("is_active").notNull().default(true),
});

// … далі за схемою вище
```

## 4. Seed (drizzle-seed)

Перший seed (`packages/db/src/seed.ts`) додає:

- 7 матеріалів: cold_rolled_steel, hot_rolled_steel, galvanized_steel, stainless_304, stainless_430, aluminum_5754, aluminum_amg3.
- Для кожного — стандартні товщини: 1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0 мм (для 10мм — без нержавійки, як у ESI).
- 5 шаблонів (поки що з пустими `parameters_schema`, заповнимо при імплементації).
- 1 admin-користувача (email з `.env`).

## 5. Параметри шаблонів (Zod-схеми, чорновик)

### L-кронштейн

```ts
import { z } from "zod";

export const LBracketParameters = z.object({
  legA_mm: z.number().min(20).max(500), // вертикальна полиця
  legB_mm: z.number().min(20).max(500), // горизонтальна полиця
  bend_radius_mm: z.union([z.literal(1), z.literal(2.5), z.literal(4), z.literal(5)]),
  bend_angle_deg: z.literal(90), // MVP — тільки 90°
  bend_direction: z.enum(["up", "down"]).default("down"), // Hotfix 2.10.e — напрям згину
  width_mm: z.number().min(20).max(3000), // довжина гиба
  // отвори (опційно)
  holes: z
    .array(
      z.object({
        leg: z.enum(["A", "B"]),
        distance_from_edge_mm: z.number().min(5),
        distance_from_bend_mm: z.number().min(5),
        diameter_mm: z.number().min(2).max(50),
      }),
    )
    .max(20),
});
```

### Напрям згину (Hotfix 2.10.e)

Кожен гиб має обов'язковий напрям (UP/DOWN), дефолт `down`. Single-bend шаблони (`l_bracket`, `corner_angle`) — скалярне поле `bend_direction: z.enum(["up","down"]).default("down")`. Multi-bend (`z_bracket`, `wall_shelf`) — масив `bends`, по одному запису на гиб:

```ts
const BendSpec = z.object({ direction: z.enum(["up", "down"]).default("down") });
// z_bracket:  bends: z.array(BendSpec).length(2).default([{direction:"down"},{direction:"up"}])
//             // [0] bottom→middle, [1] middle→top (Z гнеться у протилежні боки)
// wall_shelf: bends: z.array(BendSpec).min(1).max(2).default([{direction:"down"},{direction:"down"}])
//             // [0] back→shelf, [1] shelf→lip (за наявності front_lip)
```

`perforated_panel` гибів не має — поля напряму не отримує. Напрям не впливає на геометрію розгортки, лише на анотацію креслення (стрілка ↓/↑ у bend-table і callout; `DOWN/UP` у DXF). Pydantic у `workers/cad` дзеркалить ці схеми (`BendSpec` у `templates/base.py`).

### Z-кронштейн, кутник, полиця настінна, перфо-панель

Аналогічні Zod-схеми у `packages/types/src/templates/`. Опишемо при імплементації відповідних шаблонів.

## 6. Міграції

- Усі міграції — через `drizzle-kit generate`.
- Лежать у `packages/db/src/migrations/`.
- Naming: `YYYYMMDD_HHMMSS_<short_name>.sql`.
- На прод тільки через `drizzle-kit migrate` у Docker entrypoint.
- Rollback — через явний down-script (drizzle не генерує сам, пишемо руками).

## 7. Ретенція даних (GDPR)

| Дані              | Тривалість                        | Видалення                                                                               |
| ----------------- | --------------------------------- | --------------------------------------------------------------------------------------- |
| Email + аккаунт   | до видалення користувачем         | DSR `/account/delete` → soft-delete; через 30 днів — hard-delete + анонімізація exports |
| IP у sessions     | 24 години                         | scheduled job обнуляє `ip_first_seen` після 24h                                         |
| Logs              | 30 днів                           | logrotate видаляє файли > 30 дн                                                         |
| DXF/PDF/STEP у R2 | 90 днів від останнього скачування | scheduled job видаляє та оновлює exports.r2_keys                                        |
| Backups           | 30 днів rolling                   | окремий R2 bucket з encryption-at-rest                                                  |
| audit_log         | 1 рік                             | для security investigations                                                             |

---

## 8. Products (Phase 3.0)

> Контекст: ADR-027 — Products як preset базового шаблону. Окрема таблиця (не дискримінатор у `templates`), слабкий зв'язок через `base_template_slug` (без FK). Composite products — відкладено до Phase 3.1.

### products

Готові вироби з обмеженим набором редагованих полів (preset базового шаблону). Користувач конфігурує лише `user_editable_fields`; решта параметрів — fixed виробником продукту.

```sql
CREATE TABLE products (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug                  TEXT UNIQUE NOT NULL,
  name                  TEXT NOT NULL,
  description           TEXT,
  base_template_slug    TEXT NOT NULL,
  fixed_parameters      JSONB NOT NULL DEFAULT '{}'::jsonb,
  user_editable_fields  TEXT[] NOT NULL,
  preview_image_url     TEXT,
  use_cases             TEXT[] NOT NULL DEFAULT '{}'::text[],
  is_published          BOOLEAN NOT NULL DEFAULT FALSE,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX products_published_idx ON products (is_published) WHERE is_published;
CREATE INDEX products_base_template_idx ON products (base_template_slug);
```

**Поля.**

| Поле                   | Тип             | Призначення                                                                                                            |
| ---------------------- | --------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `id`                   | `uuid`          | uuid v4 (ADR-012); upgrade до v7 — окрема міграція                                                                     |
| `slug`                 | `text` UNIQUE   | Стабільний ідентифікатор у URL `/products/<slug>` (наприклад, `perforated-panel-decorative`, `wall-shelf-custom`)      |
| `name`                 | `text` NOT NULL | Юзер-friendly назва (UA), наприклад «Декоративна перфо-панель»                                                         |
| `description`          | `text`          | Markdown-опис у каталозі та на сторінці продукту                                                                       |
| `base_template_slug`   | `text` NOT NULL | Семантичний зв'язок з `templates.slug` (slug, не FK — templates можуть жити у seed/code, ADR-027 Рішення 1)            |
| `fixed_parameters`     | `jsonb`         | Параметри, які виробник фіксує (наприклад, `{"hole_shape": "square", "thickness_mm": 2}`); валідуються Zod-валідатором |
| `user_editable_fields` | `text[]`        | Список полів зі схеми `base_template_slug`, які користувач редагує; решта береться з `fixed_parameters`                |
| `preview_image_url`    | `text`          | URL до PNG-рендера у `apps/web/public/product-previews/<slug>.png` (генерується через скрипт)                          |
| `use_cases`            | `text[]`        | Теги для майбутньої фільтрації каталогу (наприклад, `["дім", "офіс", "інтер'єр"]`)                                     |
| `is_published`         | `boolean`       | False → не видно у `/products` listing; для draft'ів і staging                                                         |
| `created_at`           | `timestamptz`   |                                                                                                                        |
| `updated_at`           | `timestamptz`   | Оновлюється тригером або на коді при PATCH'і (для майбутніх admin-операцій)                                            |

### Зв'язок з `templates`

**Семантичний slug-зв'язок, без FK constraint.** Причини (ADR-027 Рішення 1):

- Шаблони ідентифікуються `slug`'ом (а не uuid) у Python-worker'і: `templates/<slug>.py`. slug — primary identifier у коді.
- Не всі templates мусять бути у БД як рядки: вони можуть жити лише у seed/Python. FK constraint змусив би гарантувати DB-присутність.
- Цілісність перевіряється **Zod-валідатором seed'а** (`packages/types/src/products/`): `base_template_slug` має існувати у відомому списку templates; `user_editable_fields[]` мають бути ключами у `template.parameters_schema`.

```
products.base_template_slug ──semantic──> templates.slug (UNIQUE)
                            ──validator──> known template slugs
```

### Інваріанти (перевіряються у seed-валідаторі та API)

- `base_template_slug` ∈ відомий список templates.
- Кожне `user_editable_fields[i]` — валідний ключ у `template.parameters_schema` (cross-перевірка перед insert).
- `fixed_parameters` JSON-валідний; його ключі НЕ перетинаються з `user_editable_fields` (інакше product має дві джерела істини для одного поля → undefined behavior).
- `user_editable_fields` НЕ порожній (інакше product — це просто fixed export-template, не потребує studio-flow → seed-валідатор fail).
- `slug` — kebab-case ASCII, відповідає URL-pattern `[a-z][a-z0-9-]*`.

### Приклад seed-запису

```yaml
slug: perforated-panel-decorative
name: Декоративна перфо-панель
description: |
  Стильна декоративна перфо-панель для інтер'єру.
  Налаштуйте ширину, висоту і параметри сітки отворів.
base_template_slug: perforated_panel_square # новий base-шаблон, ADR-027 Рішення 6
fixed_parameters:
  thickness_mm: 1.5
  material_code: cold_rolled_steel
user_editable_fields:
  - width_mm
  - height_mm
  - hole_diameter_mm
  - pitch_x_mm
  - pitch_y_mm
  - margin_mm
preview_image_url: /product-previews/perforated-panel-decorative.png
use_cases:
  - "інтер'єр"
  - офіс
  - дім
is_published: true
```

```yaml
slug: wall-shelf-custom
name: Кастомна настінна полиця
description: |
  Полиця для дому або офісу з перфорованими боковинами
  і ребром жорсткості. Налаштуйте ширину, глибину і параметри перфорації.
base_template_slug: enclosed_shelf # новий base-шаблон, ADR-027 Рішення 5
fixed_parameters:
  thickness_mm: 2.0
  bend_radius_mm: 2.5
  material_code: cold_rolled_steel
  side_perforation:
    hole_diameter_mm: 6
    pitch_y_mm: 25
    margin_mm: 15
  stiffening_rib:
    height_mm: 20
user_editable_fields:
  - width_mm
  - depth_mm
  - material_code
  - side_perforation.hole_diameter_mm
  - side_perforation.pitch_x_mm
preview_image_url: /product-previews/wall-shelf-custom.png
use_cases:
  - дім
  - офіс
is_published: true
```

> Підтримка nested-полів у `user_editable_fields` (наприклад, `side_perforation.hole_diameter_mm`) — через dot-notation. AutoForm `visible_fields` filter резолвить nested через path-traversal. Якщо `side_perforation` як цілий об'єкт у `fixed_parameters` встановлений, а user редагує тільки одне sub-поле — merge відбувається на API-рівні через `resolveProductParams(fixed, userInput)` pure-helper.

### Майбутня еволюція (Phase 3.1 — composite, ADR-027 Рішення 7)

Композитні вироби додаються non-breaking через discriminator у `ProductSchema`:

```sql
ALTER TABLE products ADD COLUMN is_composite BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE products ADD COLUMN components JSONB NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE products ADD COLUMN assembly_instructions_url TEXT;
```

Для single products (Phase 3.0): `is_composite=false`, `components=[]`, `assembly_instructions_url=NULL`. Для composite (Phase 3.1): `components: ComponentSpec[]` з `{base_template_slug, fixed_parameters, count, position?}`. Existing single products не торкаються.

---
