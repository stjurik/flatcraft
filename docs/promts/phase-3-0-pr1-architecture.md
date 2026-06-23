[Phase 3.0 — PR 1: Architecture validation (ADR-027 + Roadmap + Data Model preview)]

КОНТЕКСТ

- ОБОВ'ЯЗКОВО прочитай: CLAUDE.md (§1-13), AGENTS.md, docs/02_ROADMAP.md,
  docs/03_DECISIONS.md, docs/05_DATA_MODEL.md, docs/06_API_CONTRACT.md,
  docs/13_PROGRESS_LOG.md.
- Read ВСІ ADR (013-026) — це фундамент, на якому Phase 3.0 будується. Особливо:
  ADR-013 (CAD: ExtrudeGeometry+Shape), ADR-017 (group metadata у Zod `.describe()`),
  ADR-019 (server validation як інваріант), ADR-022 (client matrix validation),
  ADR-024 (DXF 2 шари), ADR-026 (R3F render-gate).
- Read existing schemas щоб розуміти patterns: packages/types/src/templates/_,
  packages/db/src/schema.ts, apps/web/src/components/_-studio.tsx.

- Контекст бізнес-рішення: yurii (founder) затвердив додавання нової entity «Виріб» —
  preset базового шаблону з restricted user-editable fields. Каталог `/templates` стає
  двомодовим. Два перші вироби (специфіковано окремо у Phase 3.0 master prompt): декоративна
  перфо-панель і кастомна настінна полиця. Цей PR — ДЕФІНІЦІЯ архітектури, без коду.

МЕТА
Зафіксувати 7 архітектурних рішень у ADR-027 у форматі «варіант → альтернативи → вибір
з обґрунтуванням → наслідки», оновити Roadmap із 8-PR checklist, додати preview змін
у Data Model і API Contract — щоб подальші 8 sub-PR'ів виконувалися детерміновано.

ОБМЕЖЕННЯ

- ЦЕ DOCS-ONLY PR. Жодних змін у `packages/`, `apps/`, `workers/`, `infra/`, `tools/`.
- НЕ створювати міграцію Drizzle (CLAUDE.md §6).
- НЕ додавати Zod-схеми.
- НЕ додавати тестів (нема коду — нема що тестувати).
- НЕ редагувати CLAUDE.md §1-12 без explicit instruction.
- НЕ ротувати CLAUDE.md §13 і не додавати запис у `docs/13_PROGRESS_LOG.md` —
  це робиться в PR 9 (за завершенням всієї Phase 3.0).
- Conventional Commits, окрема гілка `docs/phase-3-architecture`.
- Один PR з 3-5 commit'ами (по logical section).

ДЕЛІВЕРАБЛИ

A. ADR-027 у `docs/03_DECISIONS.md` — «Products як preset базового шаблону»

Структура секцій:

**Контекст.** Шифт UX від CAD-інструменту до сервісу. До цього 5 шаблонів = деталі для
інженерної аудиторії. Додаємо «вироби» для DIY/малого бізнесу. Дві перші вироби:
декоративна перфо-панель і кастомна настінна полиця (специфікації — окремо).

**7 рішень, кожне з ALT/CHOICE/RATIONALE/CONSEQUENCES:**

1.  **Сутність `products` як окрема drizzle-таблиця vs продовження `templates`**
    з discriminator-колонкою `type`. ВИБІР: окрема таблиця.
    Обґрунтуй через: семантичні відмінності (photo vs SVG; preset vs full schema),
    ризик зростання templates до 50+ полів з опційними `nullable`, легша еволюція
    products у майбутньому (наприклад, composite products).

2.  **URL routing — `/products/[slug]` vs `/templates/[slug]`** для виробів.
    ВИБІР: окремий `/products/[slug]`.
    Обґрунтуй: SEO (Google розрізнятиме deliverable-категорії), shareability
    («ось мангал, який я зробив» — URL читабельний), bookmarkability. Каталог-URL
    залишається `/templates` (з ?tab=products|parts) — це umbrella-page.

3.  **Studio component — shared з mode prop vs два окремі studio**.
    ВИБІР: shared `<TemplateStudio mode="part"|"product" ...>`.
    Обґрунтуй: економія коду, гарантія UX consistency, простота тестування.
    Trade-off: трошки більше складності у єдиному компоненті.

4.  **AutoForm розширення — `visible_fields` prop vs preprocess schema**.
    ВИБІР: prop-based (`visible_fields?: string[]`).
    Обґрунтуй: pure data transformation, без mutation Zod-схеми, легше дебажити,
    legacy AutoForm (без prop) працює без змін.

5.  **enclosed_shelf — новий базовий шаблон vs extension `wall_shelf`**.
    ВИБІР: новий шаблон.
    Обґрунтуй: wall_shelf — це U-channel (3 сегменти, 1-2 гиби); enclosed_shelf —
    4-сегментний box (back + bottom + 2 sides) з опційним 5-м гибом (rib). Геометрично
    різні. Намагання впихнути усе у wall_shelf зробило б його неможливо складним
    (8+ опційних об'єктних полів).

6.  **perforated_panel square holes — extension vs новий шаблон**.
    ВИБІР: extension через `hole_shape: 'circle' | 'square'` (default `'circle'`).
    Обґрунтуй: backward-compat існуючих entries; різниця лише у одному параметрі
    cutting (cylinder vs box); сам же layout/dxf/pdf — ідентичні. Окремий шаблон —
    overkill.

7.  **Composite products (наприклад, майбутній мангал з 4 перфо + 2 кутника) — у scope
    Phase 3.0 чи відкладено**. ВИБІР: відкладено до Phase 3.1.
    Обґрунтуй: 2 перші вироби — single-base-template. Composite потребує: BOM
    агрегацію, ZIP-export з кількома DXF/PDF, інструкцію монтажу як окремий артефакт,
    assembly preview у 3D. Це окрема архітектурна робота — не блокує MVP.

**Наслідки.** Список того, що зміниться в кожному з: data model, API, UI, тести,
виробничий процес додавання нових продуктів (3-й вирід = тільки seed entry + render
PNG, без code changes).

**Альтернативи, які активно відкинуті.** Окремий розділ з 3-4 варіантами, які
ми НЕ обрали і чому (corner cases для майбутнього rethink).

B. `docs/02_ROADMAP.md` — нова секція **«Phase 3.0 — Products Catalog»**:

- Резюме (1 абзац): мета, обсяг, target completion ~3.5 тижні.
- 8-PR checklist з status badge для кожного:

```
     - [ ] PR 1 docs/phase-3-architecture (цей PR)
     - [ ] PR 2 feat/products-data-model
     - [ ] PR 3 feat/catalog-toggle
     - [ ] PR 4 refactor/studio-mode-prop
     - [ ] PR 5 feat/perforated-panel-square-holes
     - [ ] PR 6 feat/product-decorative-perforated-panel
     - [ ] PR 7 feat/enclosed-shelf-template
     - [ ] PR 8 feat/product-custom-wall-shelf
     - [ ] PR 9 docs/phase-3-progress-log (фінальне зведення)
```

- Для кожного PR — 1-2 рядки опису що робить, на чому базується (попередні PR).
- Target completion (наприклад, 2026-07-15) — узгодж з yurii перед commit.

C. `docs/05_DATA_MODEL.md` — нова секція **«Products (Phase 3.0)»**:

- Опис таблиці `products` (SQL preview, без drizzle TS):

```sql
     CREATE TABLE products (
       id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
       slug TEXT UNIQUE NOT NULL,
       name TEXT NOT NULL,
       description TEXT,
       base_template_slug TEXT NOT NULL,
       fixed_parameters JSONB NOT NULL DEFAULT '{}',
       user_editable_fields TEXT[] NOT NULL,
       preview_image_url TEXT,
       use_cases TEXT[] DEFAULT '{}',
       is_published BOOLEAN NOT NULL DEFAULT FALSE,
       created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
       updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
     );
     CREATE INDEX products_published_idx ON products(is_published) WHERE is_published;
```

- Опис кожного поля: тип, призначення, приклади.
- Зв'язок з `templates`: семантичний (через slug), без FK constraint (templates можуть
  бути у seed/code, не у БД).
- Приклад seed-запису (yaml/json):

```json
{
  "slug": "perforated-panel-decorative",
  "name": "Декоративна перфо-панель",
  "base_template_slug": "perforated_panel",
  "fixed_parameters": { "hole_shape": "square" },
  "user_editable_fields": [
    "width_mm",
    "height_mm",
    "hole_diameter_mm",
    "pitch_x_mm",
    "pitch_y_mm",
    "material_code"
  ],
  "use_cases": ["інтер'єр", "офіс", "дім"],
  "is_published": true
}
```

D. `docs/06_API_CONTRACT.md` — нова секція **«Products endpoints (Phase 3.0)»**:

- `GET /products` — list з фільтрами `?is_published=true&use_case=дім`
- `GET /products/:slug` — detail з resolved base_template fields
- `POST /v1/exports` — добавити підтримку product-mode (через `product_slug` в body,
  server резолвує fixed_parameters перед forwardом у CAD worker)
- 3 типові помилки: 404 product not found, 422 unsupported base_template, 422 invalid
  user input проти базової схеми.
- НЕ описуй authentication/quota — це v1.1+ (ADR-020).
- Як і раніше — `🚧 v1.1+ planned` маркер для майбутніх extensions.

E. ПЛАН РИЗИКІВ (у PR description, не у файлах):

У PR description після `gh pr create` додай розділ **Risks identified for review**:
список 7 архітектурних ризиків, які мають бути перевірені перед стартом PR 2:

1.  ADR-017 group metadata з product-mode фільтрацією (`visible_fields` пропускає
    `group:`-описи невидимих полів — UX-сюрприз?)
2.  depth=height як один Zod-параметр vs два дзеркальних поля (form UX: один input
    зрозуміліший, але API має приймати обидва значення для backward compat?)
3.  perforated_panel hole_shape default='circle' migration path (наявні дані у seed
    БЕЗ shape — drizzle migration must work without manual data fix)
4.  enclosed_shelf optional nested objects (side_perforation, stiffening_rib) — Pydantic
    serialization при null у Python: `model_dump(exclude_none=True)` працює для PostgreSQL
    JSONB і не порушує snapshot determinism?
5.  R3F scene memo invalidation для нового шаблону з conditional features (rib on/off
    → useMemo deps array changes?)
6.  Square holes у DXF: LWPOLYLINE 4 vertices vs RECTANGLE entity — Lantek/SigmaNest
    які саме розуміють (треба перевірити specs виробників перед PR 5)?
7.  determinism для square holes generation order: чи Python-set ordering впливає на
    byte-identical DXF? (Hash-randomization seed має бути зафіксований у тестах.)

Кожний ризик — це питання, на яке треба знайти відповідь під час PR 2-8. Якщо yurii
бачить unanswered ризик — це сигнал зупинитися і обговорити.

ТЕСТИ

- Цей PR — docs-only, без тестів.
- Перевірити, що `pnpm typecheck` + `pnpm test` + `pytest` досі зелені (бо нічого не
  змінювали в коді, але переконатись що markdown-changes не зламали якісь CI lint-кроки —
  наприклад, prettier для md, lefthook).

ПОЧАТОК

1. Покажи ПЛАН: підтверди, що готовий написати:
   - ADR-027 з 7 рішеннями (кожне у форматі ALT/CHOICE/RATIONALE/CONSEQUENCES) +
     розділом «Альтернативи, які активно відкинуті»
   - Roadmap Phase 3.0 з 8-PR checklist
   - Data Model preview для products
   - API Contract preview для /products
   - PR description з 7 ризиками для review
2. Підтверди формат секцій ADR — ти заплануй структуру (заголовки, нумерацію) і покажи
   ПЕРЕД написанням.
3. Дочекайся OK від yurii.
4. Виконуй у 3-5 окремих commit'ах (по файлу або logical group). Кожен — Conventional
   Commits message.
5. `gh pr create --fill` з PR description включаючи Risks розділ.
6. STOP. НЕ переходь до PR 2 без OK від yurii. Цей PR — gate.
