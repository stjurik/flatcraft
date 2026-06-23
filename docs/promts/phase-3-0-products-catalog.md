[Phase 3.0 — Products catalog: новий тип «Виріб» + 2 перші вироби]

КОНТЕКСТ

- ОБОВ'ЯЗКОВО прочитай перед стартом: CLAUDE.md (§1-13), AGENTS.md, docs/02_ROADMAP.md, docs/13_PROGRESS_LOG.md, всі ADR:
  - ADR-013 (CAD: ExtrudeGeometry+Shape, OpenCascade.js відкладено)
  - ADR-017 (group metadata у Zod `.describe()`)
  - ADR-019 (server-side validation як інваріант)
  - ADR-022 (client matrix validation)
  - ADR-024 (production-grade DXF: 2 шари)
  - ADR-025 (PDF ізометрія)
  - ADR-026 (R3F render-gate + ErrorBoundary)
- Read: packages/types/src/templates/_, packages/db/src/schema.ts, packages/db/src/seed.ts,
  workers/cad/flatcraft_cad/templates/, workers/cad/flatcraft_cad/export/,
  apps/web/src/app/templates/, apps/web/src/components/_-studio.tsx,
  packages/ui/src/parameter-form/, packages/ui/src/3d-viewport/.

- Бізнес-мета: розширити каталог від «деталей» до «готових виробів» — UX-shift від
  інженерного інструменту до сервісу для DIY/малого бізнесу. Підвищити reach аудиторії 5-10×.

- Дві перші вироби заявлені користувачем (yurii):
  1. **Декоративна перфо-панель** — extension існуючого `perforated_panel`:
     - Ширина 100-1000мм, крок 50мм
     - Висота 100-1000мм, крок 50мм
     - Форма отвору: круг або квадрат (нове)
     - Розмір отвору 3-20мм, крок 1мм
     - Pitch між отворами, крок 1мм
     - Глибина (товщина) 10-30мм, крок 5мм
  2. **Кастомна настінна полиця** — новий базовий шаблон `enclosed_shelf`:
     - Ширина 300-1000мм, крок 10мм
     - Глибина=Висота 100-300мм, крок 10мм (один спільний параметр)
     - Перфоровані бокові стінки
     - Ребро жорсткості по передньому краю дна

- Перші релізи — РЕНДЕРИ (не реальні фото). Reuse R3F screenshot pipeline з Phase 2.16.b.

МЕТА

1. Каталог `/templates` стає двомодовим (Вироби | Деталі) через segmented toggle.
2. Нова сутність `product` у domain — preset базового шаблону з restricted user-editable fields.
3. Studio component переробляється на `mode: "product" | "part"` prop. Один компонент,
   два flow. AutoForm отримує опційний `visible_fields` prop.
4. Новий базовий шаблон `enclosed_shelf` з опціональними features (перфорація сторін,
   ребро жорсткості).
5. Розширення `perforated_panel` на `hole_shape: 'circle' | 'square'` (backward-compatible).
6. 2 опубліковані вироби з рендер-превью у каталозі.
7. Архітектура open/closed: додавання 3-го виробу = лише новий запис у seed + новий
   render PNG. Жодних змін у компонентах студії/форми/router.

ОБМЕЖЕННЯ

- TDD throughout: failing tests першими у кожному PR.
- ВСІ існуючі інваріанти не порушуються:
  - ADR-019/022: server+client validation parity для всіх нових features
  - ADR-024: DXF 2 шари (LASER_CUT + BEND_LINES), нуль TEXT/DIMENSION
  - ADR-026: render-gate + ErrorBoundary працюють для нових шаблонів
  - Determinism (CLAUDE.md §2.4): нові експорти byte-identical для фіксованих params
- Backward compat: всі 5 існуючих part-templates працюють без змін.
- БЕЗ нових залежностей у root; додавання deps лише у відповідному workspace.
- Conventional Commits, окремий PR на кожен з 8 sub-блоків нижче (НЕ один мега-PR).
- Squash merge.
- НЕ запускай `pnpm discord:apply` (manual-only, ADR-023).
- НЕ міняй CAD bend-machine YAML (single source of truth).

АРХІТЕКТУРНІ РІШЕННЯ (lock in перед кодом)

1. **products** — нова drizzle table, окрема від `templates`:

```sql
   products (
     id UUID PRIMARY KEY,
     slug TEXT UNIQUE NOT NULL,                  -- 'wall-shelf-custom'
     name TEXT NOT NULL,                          -- 'Кастомна настінна полиця'
     description TEXT,
     base_template_slug TEXT NOT NULL,            -- 'enclosed_shelf' (FK semantic)
     fixed_parameters JSONB NOT NULL DEFAULT '{}',-- {thickness: 2, has_perforation: true}
     user_editable_fields TEXT[] NOT NULL,        -- ['width_mm', 'depth_mm', 'material_code']
     preview_image_url TEXT,                      -- '/product-previews/wall-shelf-custom.png'
     use_cases TEXT[] DEFAULT '{}',               -- ['дім', 'офіс'] — для майбутньої фільтрації
     is_published BOOLEAN NOT NULL DEFAULT FALSE,
     created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
     updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
   )
```

Без foreign key до templates — слабка прив'язка через slug (templates можуть жити
у seed/code, не у БД).

2. **URL routing**:
   - `/templates` — каталог з toggle (`?tab=products|parts`, default products), показує обидва
     типи карток
   - `/templates/[slug]` — KEEP існуюче, parts only
   - `/products/[slug]` — NEW, products only
   - Каталог робить 2 паралельні fetch'и (`/templates` і `/products` API) на server-side;
     toggle перемикає видимість, не робить додаткових round-trip

3. **Studio component** (refactor existing 5 `*-studio.tsx`):
   - Extract спільний контейнер `<TemplateStudio mode={"part"|"product"} ...>` у `apps/web/src/components/`
   - У part-mode: повна форма, всі поля редаговані (поточна поведінка)
   - У product-mode:
     - Resolved params = `{...product.fixed_parameters, ...userInput}` (через pure
       `resolveProductParams` функцію — testable)
     - AutoForm рендерить ТІЛЬКИ `product.user_editable_fields` (новий `visible_fields` prop)
     - Header показує `product.name` замість шаблону
     - Експорт відправляє resolved params

4. **AutoForm visible_fields**:
   - Новий optional prop у `packages/ui/src/parameter-form/auto-form.tsx`:
     `visible_fields?: string[]`
   - Якщо undefined — рендерить всі поля (current behavior)
   - Якщо set — рендерить ТІЛЬКИ ті, у тому ж порядку groups з ADR-017
   - Тести: 5+ unit на фільтрацію (subset, empty, unknown field — silently ignore)

5. **enclosed_shelf** — новий базовий шаблон, додається через ту ж послідовність як інші:
   - Zod schema у `packages/types/src/templates/enclosed-shelf.ts`
   - Pydantic у `workers/cad/flatcraft_cad/templates/enclosed_shelf.py`
   - CadQuery builder: 4-сегментна розгортка (back + bottom + 2 sides), bend lines 90° UP,
     плюс опційне 5-те ребро (front rib на bottom)
   - Геометрія: depth_mm — це водночас висота back AND розмір кожної боковини
     (квадратні бокові стінки)
   - Опційні features через optional fields:

```ts
     side_perforation: { hole_diameter_mm, pitch_x_mm, pitch_y_mm, margin_mm } | null
     stiffening_rib: { height_mm: number } | null
```

- Server validators: profile (legA, legB analogues), bend matrix, sheet bounds
- R3F scene: extend buildLBracketShapeCommands pattern для 4-стороннього enclosure

6. **perforated_panel** extension:
   - Add `hole_shape: 'circle' | 'square'` у Zod/Pydantic, default `'circle'` (backward compat)
   - CadQuery: square holes через `.rect(size, size).cutThruAll()`
   - DXF: square cuts як `LWPOLYLINE` 4 vertices, той самий шар LASER_CUT color 5
   - PDF: square callouts замість Ø
   - R3F: BoxGeometry overlay для square holes (як current cylinder для circles)

7. **Product preview generation**:
   - Reuse `tools/scripts/generate-template-previews.ts` (Phase 2.16.b)
   - Розширити: skip products, окремий script для product-renderings
   - Або: extend existing script на products через slug-prefix-detection
   - Renderings зберігаються у `apps/web/public/product-previews/<slug>.png`

ДЕЛІВЕРАБЛИ (8 PR, послідовно, кожен мерджимо після review yurii)

PR 1: docs/phase-3-architecture

- `docs/03_DECISIONS.md` — ADR-027 «Products як preset базового шаблону»:
  контекст (UX-shift від інструменту до сервісу), рішення (окрема таблиця, окремий URL,
  shared Studio через mode prop), розглянуті альтернативи (products як discriminated type
  у templates — відкинуто; окрема студія UI — відкинуто), наслідки.
- `docs/02_ROADMAP.md` — Phase 3.0 з 8 sub-PR'ами як checklist.
- `docs/05_DATA_MODEL.md` — додати products table schema.
- НЕ створювати міграцію drizzle тут (CLAUDE.md §6: міграції — explicit instruction PR-2).
- Manual review pause перед PR 2.

PR 2: feat/products-data-model

- Drizzle schema: `products` table у `packages/db/src/schema.ts`.
- Міграція через `pnpm db:generate` → `0001_<auto>.sql` (commit як є).
- Zod schemas у `packages/types/src/products/`:
  - `ProductSummary` (для каталог-листингу): slug, name, base_template_slug,
    preview_image_url, use_cases, is_published
  - `ProductDetail` (для studio): + fixed_parameters, user_editable_fields, description
- Seed structure: `packages/db/src/seed-products.ts` з прикладом 1 placeholder products
  (не опублікований, тільки для unit tests).
- Pure helpers у `@flatcraft/types`: `resolveProductParams(fixed, userInput)`,
  `filterSchemaByVisibleFields(schema, fields)` — обидва pure-функції з 8+ unit кожна.
- API: `GET /products` (list, public) + `GET /products/:slug` (detail, public) у
  `apps/api/src/routes/products.ts`. Reuse pattern з templates routes.
- Tests: db tests (insert, query, FK-semantic), types tests (Zod parse), api integration
  (GET /products повертає masked schema, не fixed_parameters у summary).

PR 3: feat/catalog-toggle

- `apps/web/src/app/templates/page.tsx`:
  - Server-side parallel fetch `/templates` + `/products`
  - Query param `?tab=products|parts` (default `products`)
  - Header «Каталог» + subtitle + segmented toggle
- Новий primitive `<SegmentedControl>` у `packages/ui/src/primitives/` (CVA pattern, reuse Button styles):
  - 2-4 items, controlled (value, onChange), tabler icons
  - 5+ unit tests
- Product card component (app-local):
  - aspect-[4/3] thumb з `<img src={product.preview_image_url}>` або placeholder
  - title, «На основі: {base_template.name}», "Налаштувати →" link
- Reuse existing TemplateCard для parts (no changes)
- Tests: 6+ Playwright e2e
  - Default opens with Вироби tab active
  - URL ?tab=parts switches active state
  - Click product card → /products/:slug (404 для невпровадженого — placeholder для PR 6-8)
  - Click part card → /templates/:slug (existing flow)
  - Tap targets ≥ 44pt
  - 3 viewports console-clean

PR 4: refactor/studio-mode-prop

- Extract `<TemplateStudio mode="part"|"product" ...>` у `apps/web/src/components/template-studio.tsx`:
  - Спільний layout: header, form column, viewport column, export button
  - У part-mode: рендерить existing AutoForm з повним schema
  - У product-mode: рендерить AutoForm з `visible_fields={product.user_editable_fields}`
  - Pure `resolveProductParams` на change → merged params → state → viewport + export
- Refactor 5 existing `*-studio.tsx` → використовують `TemplateStudio mode="part"`.
- AutoForm у `@flatcraft/ui/parameter-form`: новий prop `visible_fields?: string[]`.
- Tests:
  - 5+ unit AutoForm visible_fields (subset, empty array → no fields, unknown name → skip)
  - 4 Playwright e2e (по одному на існуючий шаблон): part-mode unchanged regression check
  - 1 unit на `resolveProductParams` (fast-check property: idempotent merge)
- НЕ створює нових /products/\* routes — це PR 6-8.

PR 5: feat/perforated-panel-square-holes

- Zod: додати `hole_shape: z.enum(['circle', 'square']).default('circle').describe(...)`
- Pydantic: те ж.
- CadQuery builder: condition на shape → cylinder vs box cutting.
- DXF export: square holes → 4-vertex LWPOLYLINE на LASER_CUT color 5.
- PDF unfold: square callouts → `□ {size}` замість `Ø {size}`.
- R3F scene: BoxGeometry overlay для square (current cylinder для circle).
- Validation: жодних нових constraints (квадратний отвір розміром 3-20мм — той же sheet
  і hole margin валідатор).
- Tests:
  - 4 Zod/Pydantic parse tests (round-trip circle, square, default circle, invalid value)
  - 6 cad-engine validator tests
  - 4 cadquery builder snapshot tests
  - 2 DXF integration (count entities + verify LASER_CUT color 5)
  - 2 PDF integration (callout text format)
  - 3 R3F scene unit (visual: square overlay rendered)
  - Determinism: byte-identical DXF/PDF для фіксованих params
- Backward compat: всі existing tests з circle defaults — green без змін.

PR 6: feat/product-decorative-perforated-panel

- Seed: `Декоративна перфо-панель` як product:
  - slug: 'perforated-panel-decorative'
  - base_template_slug: 'perforated_panel'
  - fixed_parameters: {hole_shape: 'square'} (default для декоративної)
  - user_editable_fields: ['width_mm', 'height_mm', 'hole_shape', 'hole_diameter_mm',
    'pitch_x_mm', 'pitch_y_mm', 'material_code']
  - description: «Стильна декоративна панель для інтер'єру. Налаштуйте розмір,
    форму отворів і матеріал.»
  - use_cases: ['інтер'єр', 'офіс', 'дім']
  - is_published: true
- Render PNG через generate-product-previews.ts (новий script або extension PR 7):
  - Опційно у цьому PR — placeholder PNG прийнятний, real generation у PR 8.
- `/products/perforated-panel-decorative` route: рендерить `<TemplateStudio mode="product"
product={...} baseTemplate={perforated_panel} />`
- 3 Playwright e2e:
  - Catalog → click product → studio loads з preset hole_shape=square
  - Adjust width → 3D preview updates → export
  - Перевір DXF response містить square cuts на LASER_CUT
- НЕ блокує PR 7, паралелізуй якщо хочеш.

PR 7: feat/enclosed-shelf-template

- Zod schema `packages/types/src/templates/enclosed-shelf.ts`:
  - width_mm: 300-1000, step 10 (через .multipleOf(10))
  - depth_mm: 100-300, step 10 (один параметр = висота=глибина boxes)
  - thickness_mm, bend_radius_mm, material_code: standard
  - side_perforation: optional object {hole_diameter_mm, pitch_x_mm, pitch_y_mm, margin_mm}
  - stiffening_rib: optional object {height_mm} (число flange-висоти)
  - groups: «Розміри», «Гиб», «Перфорація бокових стінок», «Ребро жорсткості»
- Pydantic mirror.
- CadQuery builder: 4-сегментна розгортка (back + bottom + left + right),
  3 bend lines 90° UP; опційно front flange на bottom як 4-й гиб (для stiffening rib);
  опційно перфо grid на side панелях.
- Server validators:
  - validateProfile: legs (back/bottom/sides) >= thickness + radius
  - validateBend: matrix check (повторне використання existing)
  - validateSheet: bounding box <= max sheet (3050 × 1500)
  - validateHoles: margin checks для перфо
- Render у R3F: extend pattern з wall_shelf-scene, додати left+right side BoxGeometry,
  conditional rib BoxGeometry, conditional cylinder overlay для perf grid на sides.
- DXF/PDF: reuse generic exporters з підтримкою 3-4 bend lines.
- Tests:
  - 8 Zod tests (boundary, multipleOf, optional features parse)
  - 10 cad-engine validators (включаючи property fast-check 200 iter)
  - 12 pytest для builder + unfold + DXF + PDF
  - 6 R3F scene unit (geometry commands count, перфорація conditional)
  - 4 server integration: full /export повертає valid artifacts.{dxf,pdf}
  - 2 hypothesis property (server validator parity)
  - Determinism byte-identical для фіксованих params
- Шаблон не публікується у каталозі (it's a base template, не product) — додай
  `is_published: false` у seed templates.

PR 8: feat/product-custom-wall-shelf

- Seed: `Кастомна настінна полиця`:
  - slug: 'wall-shelf-custom'
  - base_template_slug: 'enclosed_shelf'
  - fixed_parameters: {
    thickness_mm: 2,
    bend_radius_mm: 2.5,
    side_perforation: {hole_diameter_mm: 6, pitch_x_mm: 25, pitch_y_mm: 25, margin_mm: 15},
    stiffening_rib: {height_mm: 20},
    }
  - user_editable_fields: ['width_mm', 'depth_mm', 'material_code',
    'side_perforation.hole_diameter_mm', 'side_perforation.pitch_x_mm']
  - description: «Полиця для дому або офісу з перфорованими боковинами і ребром
    жорсткості. Налаштуйте ширину, глибину і параметри перфорації.»
  - use_cases: ['дім', 'офіс']
  - is_published: true
- `/products/wall-shelf-custom` route.
- Render PNG generation script:
  - `tools/scripts/generate-product-previews.ts` (новий, у Phase 2.16.b style)
  - Reuse Playwright headless Chromium, screenshot viewport з border-border + bg-surface-sunken
  - Розмір 1280×720, зберігати у `apps/web/public/product-previews/<slug>.png`
  - Запускати manual `pnpm --filter @flatcraft/web product-preview:generate`
- Згенеруй PNG для обох products (decorative perfo + custom shelf).
- 4 Playwright e2e:
  - Catalog → click product → studio loads
  - Adjust width 600→800 → 3D updates → export
  - Toggle perforation off (через user_editable_fields доступ) → export без perforation
  - Server returns valid DXF з 2 шарами + PDF з ізометрією
- Manual smoke check: рендерити PDF, переконатись, що ізометрія показує всі 4 сторони
  - ребро жорсткості коректно.

PR 9 (final): docs/phase-3-progress-log

- `docs/13_PROGRESS_LOG.md` — повний запис «Phase 3.0 завершено (YYYY-MM-DD)»:
  підсумок всіх 8 PR, нові ADR-027, кількість тестів до/після, посилання на гілки.
- CLAUDE.md §13 — ротуй «Останні 3 milestones», додай Phase 3.0 нагору.
- Manual smoke на staging: відвідай /templates, перемкнись на Вироби, клікни обидва
  продукти, переконайся, що рендериться і експортується.

ТЕСТИ — підсумковий target

- pytest 249 → ~290-310 (включаючи enclosed_shelf, square holes, product validators)
- cad-engine TS 63 → ~85 (нові validators + parity)
- ui TS 70 → ~90 (visible_fields, segmented control, product card)
- web TS 47 → ~70
- api TS 35 → ~50 (products routes + product-mode export)
- Playwright e2e 92 → ~115 (toggle, 2 products full-flow)
- existing 249 pytest + 92 e2e — green throughout усіх 8 PR (regression-guard)

ДОКУМЕНТАЦІЯ — обов'язково

- ADR-027 у PR 1
- `docs/05_DATA_MODEL.md` оновлення у PR 2
- `docs/06_API_CONTRACT.md` — нові endpoints /products у PR 2
- `docs/02_ROADMAP.md` — Phase 3.0 чеклист у PR 1, статус-updates у кожному PR
- `docs/13_PROGRESS_LOG.md` — фінальний запис у PR 9
- CLAUDE.md §13 ротація у PR 9
- НЕ редагуй CLAUDE.md §1-12 без явної інструкції yurii (CLAUDE.md §6).

ПОЧАТОК

1. Покажи ПЛАН: підтверди розуміння 8 PR'ів послідовно, які саме файли торкатимеш у
   кожному PR, який order я очікую (PR 1 → 2 → 3 → 4 → 5 → 6 || 7 || 8 → 9 де ||
   позначає можливі паралельні гілки), 7 ризиків (наприклад: ADR-017 group metadata
   при product-mode фільтрації; depth=height одного значення у Zod-schema; backward-compat
   для perforated_panel при додаванні hole_shape; Pydantic serialization для optional
   nested objects; R3F scene memo invalidation; визначення «square hole» у DXF як
   LWPOLYLINE 4 vertices vs RECTANGLE entity — який CAM розуміє; перевірка determinism
   при фіксованому seed для square holes generation order).
2. Дочекайся OK від yurii перед стартом PR 1.
3. Кожен PR — окрема гілка `feat/...` або `docs/...`, окремий commit-stream, окремий
   `gh pr create --fill` у кінці.
4. Між PR — манulla yurii review pause (НЕ continue automatically); якщо вже OK на план,
   можеш batch'ити PR 6+7+8 у паралель, але mark їх як WIP до review.
5. У PR 9 manual smoke на staging — yurii перевіряє наживо.
