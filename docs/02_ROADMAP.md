# 02. Roadmap — flatcraft

> Roadmap — це список **спринтів по 1–2 тижні**. Кожен спринт = одна користувацька цінність + критерії приймання + тести.
> Принципи: TDD, спочатку валідатор → потім UI, спочатку 1 шаблон end-to-end → потім решта.

## Стадії

| Стадія                                           | Терміни (соло-розробник, junior + Claude Code) | Мета                                                                                                       |
| ------------------------------------------------ | ---------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| **Phase 0. Setup**                               | 1 тиждень                                      | Локальне середовище, CI, перший «hello world» end-to-end                                                   |
| **Phase 1. CAD core**                            | 3 тижні                                        | Валідатор гибки + розгортка + експорт DXF одного шаблону (L-кронштейн)                                     |
| **Phase 2. UX MVP**                              | 3 тижні                                        | 3D-редактор + форма параметрів + експорт DXF/PDF + 5 шаблонів                                              |
| **Phase X.1. Beta-mode tweaks**                  | 1–2 дні ✅                                     | IP rate-limit + PDF «BETA» watermark + post-export ЗСУ-CTA + /about (ADR-020)                              |
| **Phase 3. Auth & Limits** _(v1.1, conditional)_ | 2 тижні                                        | Реєстрація, лічильник 10 безкоштовних, гість-режим — **активується лише при тригерах ADR-020**             |
| **Phase 4. Donations** _(v1.1, conditional)_     | 1 тиждень                                      | Monobank Banka link + ручне підтвердження + продовження ліміту — **активується лише при тригерах ADR-020** |
| **Phase 5. Hardening + Launch**                  | 2 тижні                                        | GDPR, Privacy Policy, Sentry, prod-deploy на Mirohost Cloud, домен, SSL                                    |
| **Total**                                        | ≈ 12 тижнів                                    | Public MVP                                                                                                 |

Після MVP — окремий roadmap у `docs/02_ROADMAP_v1.md` (поки не створюємо).

---

## Phase 0. Setup (1 тиждень)

**Definition of Done:** `pnpm dev` піднімає весь стек локально. CI на GitHub Actions проганяє lint+test на push.

- [x] **0.1.** Скелет монорепо (`apps/web`, `apps/api`, `workers/cad`, `packages/*`) — 2026-05-15
- [x] **0.2.** `docker-compose.yml`: Postgres + Redis + MinIO + Mailpit (web/api/cad — локально) — 2026-05-16
- [x] **0.3.** Drizzle init: 12 таблиць згідно docs/05, перша міграція, seed (7 матеріалів × 10 товщин + 5 шаблонів-placeholder) — 2026-05-16
- [x] **0.4.** Fastify hello-world з health-check (`/health`), pino logger з PII-redact, Zod-валідація env, fastify-type-provider-zod — 2026-05-16
- [x] **0.5.** Next.js 15 App Router + Tailwind, R3F куб (`dynamic ssr:false`), Playwright e2e — 2026-05-16
- [x] **0.6.** GitHub Actions CI: install/lint/typecheck/test/build/e2e з Postgres service — 2026-05-16
- [x] **0.7.** Pre-commit hook (lefthook): lint + typecheck + format на staged, test на pre-push — 2026-05-16
- [x] **0.8.** README.md з інструкцією «як запустити локально за 5 хвилин» — 2026-05-16

**Тести:** smoke-test, що health-check API повертає 200, web відкривається на `localhost:3000`.

---

## Phase 1. CAD core (3 тижні)

**Definition of Done:** з командного рядка можна запустити `cad-worker` із параметрами L-кронштейна → отримати валідний DXF, який відкривається у LibreCAD.

- [x] **1.1.** `packages/cad-engine/data/bend-machine-esi.yaml` — завантажено з `docs/07_BEND_MACHINE_SPEC.md` (Phase 0.1)
- [x] **1.2.** `packages/cad-engine/src/spec.ts` — Zod-завантажувач + 9 тестів — 2026-05-16
- [x] **1.3.** `packages/cad-engine/src/validators/` — sheet/bend/holes + 19 тестів — 2026-05-16
- [x] **1.4.** `packages/cad-engine/src/k-factor.ts` — base × multiplier(R/S) + 8 тестів — 2026-05-16
- [x] **1.5.** `workers/cad/flatcraft_cad/templates/l_bracket.py` — Pydantic + CadQuery + 16 тестів — 2026-05-16
- [x] **1.6.** `workers/cad/flatcraft_cad/unfold.py` — bend allowance + L-розгортка + 15 тестів — 2026-05-16
- [x] **1.7.** `workers/cad/flatcraft_cad/export/dxf.py` — 5 шарів (LASER_CUT/INNER_CUTS/BEND_LINES/BEND_TEXT/DIM) + детермінізм — 2026-05-16
- [x] **1.8.** Снепшоти DXF — 3 фікстури, байт-у-байт регресія через post-write нормалізацію — 2026-05-16

**Тести:** pytest з фікстурами для 3 розмірів L-кронштейна; перевіряємо, що валідатор кидає правильні помилки на занадто товсту/тонку заготовку, на закороткий полиць, на недозволений радіус.

---

## Phase 2. UX MVP (3 тижні)

**Definition of Done:** користувач відкриває сайт, вибирає шаблон, крутить повзунки, бачить 3D-прев'ю в реальному часі, скачує DXF + PDF.

- [x] **2.1.** Сторінка `/templates` — каталог шаблонів. API `GET /templates` (Fastify+drizzle, 3 integration + 10 schema), web page (server component, Playwright e2e). L-bracket опубліковано, решта 4 — приховані до Phase 2.10. — 2026-05-16
- [x] **2.2.** Сторінка `/templates/[slug]` — API `GET /templates/:slug` (Detail з defaultParameters), web Studio (controlled editor + R3F viewport з live ExtrudeGeometry). L-bracket — лише slug з повним flow до Phase 2.10. — 2026-05-16
- [x] **2.3.** `packages/ui/src/3d-viewport/` — LBracketScene + pure-builder buildLBracketShapeCommands (5 unit-тестів). apps/web bunny консумує через dynamic ssr:false. — 2026-05-16
- [x] **2.4.** `packages/ui/src/parameter-form/` — `introspectSchema(zodObject)` (13 unit) + AutoForm з NumberField/EnumField/LiteralField. L-bracket editor мігровано. Селектори матеріалу/товщини — окремо (Phase 3.5 / окремий MaterialPicker). — 2026-05-17
- [x] **2.5.** Live-валідація з підсвіченням обмежень — zodIssuesToFieldErrors (6 unit) + AutoForm errors prop (border-red + aria-invalid + inline `<ul>` під полем). 2 нові Playwright e2e. — 2026-05-17
- [x] **2.6.** Debounce 100мс на mesh-rebuild — `useDebouncedValue` у `@flatcraft/ui` (6 unit). OpenCascade.js bridge відкладено (ADR-013): three.js Shape + ExtrudeGeometry достатньо для MVP, точна геометрія — CadQuery server-side. — 2026-05-17
- [x] **2.7.** Кнопка Export — sync HTTP-flow (BullMQ async — Phase 2.8). Python FastAPI POST /export (6 pytest, 96% cov), Fastify POST /exports (5 unit з mock fetch), Web ExportButton (3 e2e з mock'ed API). L-bracket: web → api → cad-worker → S3 presigned URL. — 2026-05-17
- [x] **2.8.** Async export pipeline з SSE прогресом. API: in-memory JobStore (7 unit) + POST/GET/SSE /exports (6 нових unit). Web: EventSource у ExportButton + progress bar (2 нові e2e). BullMQ distributed — Phase 5. — 2026-05-17
- [x] **2.9.** PDF з розгорткою + bend table + BOM + QR через ReportLab (compute_bom pure-функція з 3 unit). /export повертає ExportResponse.artifacts.{dxf,pdf}. Ізометрія 3D — пропущено до Phase 5 (потребує WebGL→PNG pipeline). — 2026-05-18
- [x] **2.10.** Решта 4 шаблонів (Z-кронштейн, кутник, полиця, перфо-панель) — кожен як окремий PR. — 2026-05-18
  - [x] **2.10.a.** Z-кронштейн — Zod + Pydantic схеми, CadQuery builder, unfold (2 гиби), DXF/PDF з generic exporters, Studio/Editor/Viewport, ExportRequest discriminatedUnion, 3 e2e. — 2026-05-18
  - [x] **2.10.b.** Кутник (corner_angle) — auto-grid отворів (rows × cols × 2 полиці) замість ручних координат L-bracket. `_distribute` pure-функція, `Hole2D` додано до unfold, DXF/PDF малюють CIRCLE на INNER_CUTS, R3F рендерить cylinder-отвори для preview. 97 pytest (99% cov), 32 db tests, 4 нових e2e (19 разом). — 2026-05-18
  - [x] **2.10.c.** Полиця настінна (wall_shelf) — U-channel back+shelf+(optional)lip. front_lip=0 → 2 сегменти/1 гиб, ≥5 → 3 сегменти/2 гиби. Auto-grid mounting holes на back. Cross-field constraint "0 або ≥5" через `WallShelfParametersBaseSchema` + refine wrapper (base використовується у discriminatedUnion). 118 pytest (99% cov), 33 db tests, 4 нові e2e (23 разом). — 2026-05-18
  - [x] **2.10.d.** Перфо-панель (perforated_panel) — плоский лист без гибів, centered grid отворів за pitch_x/pitch_y/margin. Layout автоматичний: `n_cols = floor((length - 2*margin)/pitch) + 1`, eff_margin перераховується для симетрії. Reuse `_export_flat_dxf(holes, bend_lines=())` без модифікацій. Окремий PDF без bend table — натомість Hole grid summary. 137 pytest (99% cov), 34 db tests, 4 нові e2e (27 разом). — 2026-05-18
  - [x] **2.10.e (Hotfix).** Validator-bypass у export-pipeline + напрям згину. **P0:** Z-bracket t=5/R=2.5 проскочив експорт (матриця t=5 → R∈{4.0,5.0}), порушено CLAUDE.md §7 п.2. Root cause H1+H2: `validateBend` коректний, але викликався лише браузер-side; Fastify-export форвардив без matrix-перевірки, Python перевіряв радіус проти глобального набору. Фікс: серверний gate `apps/api` (ADR-019, 422 RFC 9457 `RADIUS_NOT_ALLOWED`) + Python parity-валідатор (`flatcraft_cad/validate`, той самий YAML). Property-based парітет fast-check+hypothesis ×1000. Напрям згину (`bend_direction`/`bends[]`, дефолт `down`) у моделі + PDF bend-table колонка ↓/↑ + DXF text + 30мм overlap-fix; редактори приховують поле (no UI/UX). ADR-019, R-12. 145 pytest, 254 TS unit. Гілка `hotfix/2-10-e-validator-and-bend-direction`. — 2026-06-03

**Phase 2 повністю закрита: 5 шаблонів end-to-end (web → api → cad-worker → S3).**

**Тести:** Playwright e2e — відкрити сторінку → змінити параметр → побачити оновлення 3D → клікнути Export → отримати DXF.

- [x] **2.11.** Design system foundation (ADR-016, `docs/10_DESIGN_SYSTEM.md`). Warm-industrial OKLCH-токени у `globals.css` (38 шт, light theme only), Tailwind 3.4 mapping з mobile-first breakpoints (xs 360 → xl), self-hosted Inter + JetBrains Mono через next/font/google, primitive `<Button>` (CVA з варіантом `zsu`), composite `<Logo>` / `<UkraineStripe>` / `<Footer>` у `@flatcraft/ui`, `/styleguide` (dev-only, 12 секцій, contrast-table з обчисленим `contrastRatio()`). TDD `contrastRatio` (10 unit, OKLCH→sRGB→WCAG), 6 Playwright e2e (3 viewports без console-errors + UkraineStripe 2px інваріант + tap-target ≥44px + dev-gate). R-02 переписано на progressive enhancement → Phase 2.14. — 2026-05-30

- [x] **2.12.a.** Editor form polish (ADR-017 group metadata + ADR-018 material_code strip). `GET /materials` endpoint (JOIN materials↔material_thicknesses, нержавійка без 10мм; 4 integration tests). `MaterialChoice` Zod-схема у `@flatcraft/types/domain/materials.ts`. AutoForm (`@flatcraft/ui/parameter-form`) розширено: `parseDescription()` helper читає Zod `.describe("group:G|label:L")` → `FieldDescriptor.group/label`, рендерить fieldset/legend секції з токенами Phase 2.11 (5 нових unit). `MaterialSection` (controlled material+thickness selects, перша секція форми). 5 шаблонів отримали `.describe()`-метадані з UA-групами. ExportRequest тепер вимагає `material_code` (3 нові unit), API strip'ить його перед cad-worker forward (1 новий unit). Студії підняли material+thickness у state, ExportButton переписано на `<Button>` primitive з токенами. JSON debug-блоки приховано за `IS_DEV`. 7 нових e2e (legends, default values, dynamic thickness options, request body intercept, 3 viewports). — 2026-05-31

- [x] **2.12.b.** Landing redesign (`docs/10_DESIGN_SYSTEM.md §7 Hero pattern`). Hero з headline «Креслення листового металу за 60 секунд», CTA на /templates, secondary anchor «Як це працює ↓». `HeroLoopDemo` — детермінований 16-сек цикл, що прокручує L-кронштейн через 4 фази (legA→legB→bend_radius→width), pure `nextDemoParams(tMs)` (12 unit, TDD), RAF driver з tick 100мс/200мс desktop/mobile, hover-пауза, `useReducedMotion` hook у `@flatcraft/ui` → статичний бракет при reduced-motion. Dynamic ssr:false з skeleton (no CLS). Секція «Як це працює» з 3 step-cards (LayoutGrid/Sliders/FileDown). Trust-row з 3 блоками (Gift / Heart→UNITED24 / Github→repo). `SiteLinks` (app-local, 3 колонки) у Footer через новий `linksSlot` prop. Placeholder сторінка `/soon` для майбутніх лінків. lucide-icons (Activity, Gift, Heart, Github, LayoutGrid, Sliders, LucideIcon type) додано у `@flatcraft/ui/icons.ts`. 12 нових Playwright e2e (hero structure, CTA navigation, anchor scroll, step-cards, trust-blocks, RAF canvas, prefers-reduced-motion caption, console-clean × 3 viewports, tap-targets ≥44px, /soon). Нуль регресій → 53/53 e2e ✓. og:image — TODO у Phase 2.16. — 2026-05-31

- [x] **2.13.** Каталог `/templates` redesign (`docs/10_DESIGN_SYSTEM.md §8 Card pattern`). Замість плоского zinc-grid'а — токенізовані cards у warm-industrial стилі: `<article>` wrapper з `shadow-md → shadow-lg` на hover, ДВА окремі link'и (clickable h3-title + explicit `<Button variant="default">` «Налаштувати →»), thumb-region `aspect-[4/3] bg-surface-sunken` з inline SVG-схемами. `TemplateThumb` dispatcher (6 unit, TDD) з 5 схематичними виробами (L-форма, Z-форма, L+grid holes, U-channel+mounts, rect+3×3 grid) + fallback `<Box>`. `stroke="currentColor"` дозволяє group-hover тоном з картки. Mini-hero на сторінці (warm bg + heading-h1), grid на `bg-surface-sunken`. Error/empty states — токенізовані; dev-hints (`pnpm db:seed`, `pnpm api dev`) під `IS_DEV`. Vitest jsx config: `esbuild.jsx = "automatic"` для тестів з JSX. 7 нових Playwright e2e (existing 5-cards тест збережено; +CTA navigation, title-link navigation, tap-targets ≥44, console-clean × 3 viewports). 5 старих «картка → деталь» тестів адаптовано: клік по `template-card-cta` замість всього card-wrapper. 59/59 e2e ✓. — 2026-05-31

- [x] **2.14.a.** Mobile-friendly studio + progressive 3D (R-02 mitigation, `docs/10_DESIGN_SYSTEM.md §9`). Pure `viewportQuality({isMobile, reduced})` helper у `@flatcraft/ui/lib/` (5 unit, TDD) з матрицею: desktop `dpr=[1,2]`/zoom/rotate/100ms/curve=12; mobile `dpr=[1,1.5]`/no-zoom (pinch conflict)/rotate/250ms/curve=8; reduced `dpr=[1,1]`/no-zoom/no-rotate/400ms/curve=6. `useIsMobile` hook у `@flatcraft/ui/hooks/` (matchMedia, SSR-safe). Застосовано до всіх 5 scenes (Canvas dpr cap + OrbitControls zoom/rotate) + 5 студій (adaptive debounce замість hardcoded 100). L-bracket scene також отримує `curveSegments` адаптивно. `<StudioPreviewAnchor>` (lg:hidden) — anchor «↓ Подивитися 3D-прев'ю» для швидкого скролу до `#studio-viewport`. Token cleanup у 5 viewport-wrappers (`zinc-* → bg-surface-sunken border-border`). 9 нових Playwright e2e на 360×640 + 1280×800 viewport (5 шаблонів × console-clean + scroll-to-anchor + tap-targets selects/export ≥44 + anchor lg:hidden). 68/68 e2e ✓ (нуль регресій). Round bend cross-section на 4 BoxGeometry-scenes (Z, corner_angle, wall_shelf) — окремий PR Phase 2.14.b. — 2026-06-01

- [x] **2.14.b.** Round-bend cross-section для Z-bracket і wall-shelf scenes. Аудит показав, що з 4 box-based scenes реально потребують rewrite **тільки 2**: corner_angle уже reuse'є `buildLBracketShapeCommands` (round bend є), perforated_panel — плоский лист без гибів. Нові pure shape-builders у `packages/ui/src/3d-viewport/geometry.ts`: `buildZBracketShapeCommands` (2 inner concave bends — bottom→middle і middle→top) і `buildWallShelfShapeCommands` (1 або 2 inner bends — back→shelf завжди; shelf→lip умовно при front_lip>0). 13 нових unit tests (TDD: command counts, control point coordinates, throws на invalid geometry). Обидві scene-обгортки переписано з 3×BoxGeometry union на один `ExtrudeGeometry+Shape` (як L-bracket). Wall-shelf scene зберігає mounting-hole cylinders, переcцентровані відносно нового bounding box. `curveSegments` адаптивний (з viewportQuality) — застосовується до всіх 3 ExtrudeGeometry-scenes тепер. 68/68 e2e ✓ (нуль регресій). — 2026-06-01

- [x] **2.16.a.** Open Graph image для лендінга (`apps/web/src/app/opengraph-image.tsx`). Next.js App Router file-convention — Next автоматично рендерить файл, додає `<meta property="og:image">` і `twitter:image` з повним набором атрибутів (width/height/type/alt). Дизайн 1200×630: warm-bg + wordmark `hart.crimea.ua` + headline «Креслення листового металу за 60 секунд.» + sub «Без CAD-навичок · DXF + PDF · 10 експортів/міс безкоштовно» + ember-stripe + схематичний L-bracket SVG праворуч + 4px UkraineStripe знизу. **Bundled Inter TTF** (Regular/SemiBold/Bold, OFL ліцензія) у `_og-fonts/` (private route з підкреслення, Satori не має вбудованих шрифтів і Cyrillic потребує explicitly bundled font). OG metadata у `layout.tsx`: `metadataBase`, `openGraph` (uk_UA locale, website type, siteName), `twitter` (summary_large_image). 3 нові Playwright e2e: PNG magic-bytes на `/opengraph-image`, OG/twitter meta-теги у `<head>`. 71/71 e2e ✓. — 2026-06-01

- [x] **2.16.b.** Реальні preview-PNG для каталога. `tools/scripts/generate-template-previews.ts` — Playwright headless Chromium (2× DPR) обходить 5 студій на локальному стеку, чекає R3F canvas, робить скріншот `[data-testid="<slug>-viewport"]` (з border + bg-surface-sunken — консистентно з карткою). 5 PNG у `apps/web/public/template-previews/` (~12-27KB кожен, 1280×720). `pnpm --filter @flatcraft/web preview:generate` — manual run при зміні geometry/colors. Seed (`packages/db/src/seed.ts`) розширено полем `previewImageUrl: "/template-previews/<slug>.png"` для всіх 5 шаблонів; upsert у `seedTemplates` уже синхронізує DB при re-deploy через api-entrypoint (ADR-015). **Schema relaxation:** `TemplateSummarySchema.previewImageUrl` — `z.string().url().nullable()` → `z.string().min(1).nullable()` (відносні шляхи `/template-previews/*` теж валідні для `<img src>`). Existing `templates.spec.ts` e2e оновлено: тепер очікує `<img src="/template-previews/<slug>.png">` замість inline SVG-thumb. SVG-thumb dispatcher лишається як fallback, якщо `previewImageUrl=null` (legacy/майбутні шаблони). — 2026-06-01

---

## Phase X.1. Beta-mode tweaks (завершено 2026-06-04)

**Контекст:** soft-launch без auth/donations (ADR-020). Готує продукт до публічного релізу за 1–2 дні замість 3 тижнів Phase 3+4.

- [x] **X.1.A.** IP-based rate-limit на `POST /exports`: 30/год/IP + burst-ban (50), глобально 100/хв лишається. 429 RFC 9457 з україномовним detail. `apps/api/src/plugins/rate-limit.ts`. Unit (config/builder) + integration (30 → 202, 31й → 429). — 2026-06-04
- [x] **X.1.B.** PDF footer watermark «BETA · feedback@hart.crimea.ua» на всіх 5 шаблонах. `_draw_beta_watermark` (7pt курсив #707070, 18pt від низу), прапор `BETA_WATERMARK` для вимкнення при v1.0. +3 pytest. — 2026-06-04
- [x] **X.1.C.** Post-export ЗСУ-CTA (`PostExportDonateNudge`) у success-стані ExportButton: Monobank банка + UNITED24, без auto-redirect/modal. 5 Playwright e2e. — 2026-06-04
- [x] **X.1.D.** Справжня `/about` (4 секції: hero, що це, безкоштовно-чому, підтримати ЗСУ, фідбек) замість `/soon`-заглушки. SiteLinks «Про проєкт» → /about. 6 Playwright e2e. — 2026-06-04
- [x] **X.1.E.** Документація: ADR-020, API contract §0 rate-limit + 🚧 v1.1-маркери на Auth/Account/Donations/Admin, Roadmap re-sequence, RISKS R-03. — 2026-06-04

---

## Phase 2.9.b. Drawing polish (завершено 2026-06-05)

**Контекст:** закриває 5 залишкових пунктів аудиту креслень (ADR-021). Інкрементальні правки рендерера + pure-модулі `export/layout/` і `export/dimensions.py`, кожен покритий юніт-тестами. Детермінізм збережено; perf ~48мс PDF (бюджет 5с).

- [x] **2.9.b.B.** Bend badges — номер гибу посеред лінії розгортки: PDF (коло Ø5мм + цифра) + DXF (midpoint `#N` TEXT на BEND_TEXT). Pure `place_bend_badges` (short-line leader, overlap avoidance). +11 pytest. — 2026-06-05
- [x] **2.9.b.C.** Габарит готового (зігнутого) виробу у header усіх 5 шаблонів. Pure `compute_finished_dimensions` + `format_dimensions`, єдина конвенція осей (X×Y профіль, Z=width; перфо Z=товщина). +16 pytest. — 2026-06-05
- [x] **2.9.b.D.** BOM UA-одиниці: маса г→кг, новий рядок «Площа фарбування (м²)». 5 дубльованих блоків → pure `bom_text_lines`. +6 pytest. — 2026-06-05
- [x] **2.9.b.E.** Auto-layout corner picker — pure `pick_annotation_corner` (4 кути, BR-fallback). BOM слідує за низом таблиці гибів. +12 pytest. — 2026-06-05
- [x] **2.9.b.F.** Ø-виноски отворів: PDF (виноска+«Ø8»), DXF (`add_diameter_dim` на шарі DIM_HOLES). `should_dim_individual_holes` cap=10 → перфо: один dim + «×N отворів». +10 pytest. — 2026-06-05
- [x] **2.9.b.docs.** ADR-021. Baseline 151 → 206 pytest. — 2026-06-05

---

## Phase 3. Auth & Limits (v1.1, conditional) — 2 тижні

> ⏸ **Відкладено (ADR-020).** Активується лише коли спрацюють тригери: >5 ботів/тиждень на CF WAF, або >3 unique users просять «зберегти draft». До того — soft-launch (Phase X.1).

**Definition of Done:** новий користувач реєструється email/Google, бачить лічильник «X з 10 безкоштовних на цей місяць», після ліміту — кнопка «розблокувати донатом».

- [ ] **3.1.** Auth.js Credentials provider + Google OAuth у `apps/api`
- [ ] **3.2.** Argon2id для паролів (`@node-rs/argon2`)
- [ ] **3.3.** JWT (15хв) + refresh cookie HttpOnly
- [ ] **3.4.** Rate-limit middleware (Fastify rate-limit): 100 req/min/IP, 5 export/хв/user
- [ ] **3.5.** Таблиця `usage_quota` (drizzle): підрахунок експортів по `user_id` + `month`
- [ ] **3.6.** Гість: дозвіл на 3D-редактор, заборона на `/exports` (HTTP 401 + UI підказка)
- [ ] **3.7.** Watermark на 3D-прев'ю для гостей
- [ ] **3.8.** Адмінка: список користувачів, лічильники, ручне розширення ліміту (для пілотів)

**Тести:** інтеграційні тести проти реальної Postgres у Docker — TDD сценарії: реєстрація, логін, логаут, перевищення rate-limit, перевищення monthly quota.

---

## Phase 4. Donations (v1.1, conditional) — 1 тиждень

> ⏸ **Відкладено (ADR-020).** Активується коли >$50/міс приходить на ЗСУ через банку. До того — почесна система: прямі лінки у post-export CTA і на /about, без unlock-flow.

**Definition of Done:** після ліміту користувач бачить кнопку «Розблокувати на місяць → 200 грн на ЗСУ», клікає → переходить на банку Monobank → завантажує квитанцію → адмін підтверджує → ліміт продовжено.

- [ ] **4.1.** Сторінка `/unlock` з кнопками «Monobank Banka» (link), «UNITED24» (link), «USDT» (адреса гаманця)
- [ ] **4.2.** Форма «я задонатив» (load receipt + email + amount) → `donation_claims` table
- [ ] **4.3.** Адмін-сторінка для верифікації claim (одна кнопка «Approve» → продовжує quota на 30 днів)
- [ ] **4.4.** Email-сповіщення про підтвердження (через Postmark або Resend)
- [ ] **4.5.** _v1.1:_ Monobank Acquiring webhook для автопідтвердження

**Тести:** unit на логіку продовження ліміту (timezone-safe, на 30 днів від моменту підтвердження).

---

## Phase 5. Hardening + Launch (2 тижні)

**Definition of Done:** домен `hart.crimea.ua`, SSL через Cloudflare, GDPR-compliance, Privacy/ToS опубліковані, Sentry прокладено, перші 10 живих юзерів.

- [ ] **5.1.** Sentry SDK у web + api + worker; `beforeSend` фільтр PII
- [ ] **5.2.** Plausible/Umami self-hosted або хмарний акаунт
- [ ] **5.3.** Cookie banner (мінімальний, GDPR-сумісний — наш власний компонент)
- [ ] **5.4.** Privacy Policy + ToS + Cookie Policy (UA + EN, шаблон у `legal/`)
- [ ] **5.5.** GDPR Data Subject Request endpoint: `/account/export-data`, `/account/delete`
- [x] **5.6.** Cloud-сервер + DNS + R2 — **код готовий** (Phase 5A: `infra/compose/docker-compose.prod.yml` + `Caddyfile` з CF Origin Cert, ADR-014). Сам сервер створює yurii за runbook'ом `docs/08_DEPLOYMENT.md` §0. — 2026-05-18
- [x] **5.7.** Ansible-плейбук — 6 ролей (base/docker/firewall/flatcraft/backups/monitoring) на Debian 12 (Phase 5C). `--syntax-check` і `ansible-lint --profile production` зелені у CI. — 2026-05-18
- [x] **5.8.** Backup-скрипт: cron 03:00 → `pg_dump -Fc` (docker exec з PGPASSWORD) → age encrypt → rclone у R2 `flatcraft-backups`. Recovery flow задокументовано (`docs/08_DEPLOYMENT.md` §5.5). — 2026-05-18 (hotfix 2026-05-22 на double-compression і auth)
- [x] **5.9.** Staging environment — CI/CD pipeline (`.github/workflows/release.yml` + `deploy-staging.yml`, Phase 5D) + runbook (`docs/08_DEPLOYMENT.md`, Phase 5E). **Перший реальний staging-deploy виконано й автоматизовано** (Phase 5F, 2026-05-28): стек живий на `staging.hart.crimea.ua`, повний CI-флоу `release.yml`→`deploy-staging.yml` провалідовано end-to-end; додано migrate+seed у entrypoint (ADR-015). — 2026-05-22 (deploy 2026-05-28)
- [ ] **5.10.** Production deploy + smoke tests + перші реальні замовлення з пілотним підрядником

---

## KPI MVP (через місяць після запуску)

- ≥ 10 унікальних користувачів зробили експорт DXF
- ≥ 50 успішних експортів без скарг на якість креслення
- ≥ 3 виробничі замовлення, виконані з нашого DXF без правок
- p95 export time < 5 c
- Zero PII у логах (sentry audit)
- Zero критичних security findings (npm audit / pip-audit)

---

## Tech-debt / Maintenance backlog

> Не блокує MVP, але варто закрити, коли дійдуть руки. Кожен пункт — короткий «що + чому».

- [ ] **TD-01.** Бампнути версії GitHub Actions (`actions/checkout@v4`, `docker/*`, `actions/setup-python@v5` тощо). **Чому:** CI кидає попередження — Node.js 20 actions deprecated, з 16 червня 2026 примусово Node.js 24, з 16 вересня 2026 Node.js 20 прибирають з runner'а. Поки лише warning, але дедлайн фіксований.
- [ ] **TD-02.** Унеможливити stale скомпільовані `*.js`/`*.js.map` поряд із `.ts` у `packages/*/src/`. **Чому:** vitest при `import "./foo.js"` резолвить буквальний `.js` і підхоплює stale-білд замість свіжого `.ts` — локальні прогони показують неправдиві результати (плутанина у Phase 2.16.b: тест «бачив» стару Zod-схему з `url()`, хоча `.ts` уже мав `min(1)`). Файли untracked (CI чистий), проблема лише локальна. Варіанти: lefthook/pre-commit guard, що падає на stray `src/**/*.js`; `clean`-крок у dev-командах; або гарантувати, що жоден `tsc` не запускається без `outDir: dist`.

---

## Що НЕ входить у MVP (post-launch)

- Калькулятор вартості
- Інтеграція з прайсом виробника (CSV/API)
- Телеграм-бот / Discord-бот для нотифікацій
- Маркетплейс кількох виробників
- Завантаження користувацьких STEP/STL
- Mobile app
- AI-помічник «опиши що тобі треба → отримай шаблон»
- Польська/німецька локалізація
- Власний платіжний шлюз
