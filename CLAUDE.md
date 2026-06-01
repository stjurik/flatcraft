# CLAUDE.md — головний контекст для Claude Code

> Цей файл — **ваш контракт з Claude Code**. Кожна сесія читає його першим. Тримайте його актуальним: коли змінюється архітектура, конвенція або ризик — оновлюйте.

## 1. Що це за проєкт

**Робоча назва:** `flatcraft` _(можна змінити; див. `docs/00_OPEN_QUESTIONS.md`)_

**Одне речення:** Веб-платформа, яка дозволяє користувачу без CAD-навичок параметрично налаштувати типовий виріб з листового металу (кронштейн, полиця, кутник, тощо) і безкоштовно скачати готові креслення (DXF + PDF + STEP) для замовлення на будь-якому виробництві лазерного різання та гибки.

**Бізнес-модель (соціальний характер):** до 10 експортів/місяць безкоштовно; далі — донат від 200 грн на ЗСУ (Monobank Banka або UNITED24) → +1 місяць безкоштовного користування. Платформа неприбуткова, без юрособи на старті.

**Цільова аудиторія:** DIY-ентузіасти, малий бізнес (меблі, HoReCa), архітектори, інженери-початківці. Україна → ЄС.

**Очікуване навантаження MVP:** 10 користувачів/день, 100 креслень/день. Одного сервера Mirohost Cloud (тариф MS21: 2 vCPU / 4 GB / 40 GB) достатньо. Див. ADR-011.

## 2. Принципи розробки

Ці принципи мають перевагу над зручністю та швидкістю. Якщо є компроміс — обираємо принцип.

1. **TDD з першого дня.** Жоден feature не мерджиться без тестів. Спочатку red, потім green, потім refactor.
2. **Type-safe end-to-end.** TypeScript strict, Zod-схеми спільні між frontend і backend через `packages/types`.
3. **Одне джерело істини для геометрії.** Параметри моделі живуть у базі (JSONB) і валідуються однією Zod-схемою на бекенді й фронтенді.
4. **CAD-операції детерміновані.** Один і той самий вхід → один і той самий DXF/PDF/STEP байт-у-байт. Це обов'язково для регресійних тестів.
5. **Junior-friendly.** Код пишеться так, щоб новий контриб'ютор зрозумів модуль за 30 хвилин. Без розумних абстракцій без потреби. Коментуємо _чому_, не _що_.
6. **Open Source MIT з першого коміту.** Ніяких приватних залежностей, секретів у репо чи конфіденційних даних.
7. **GDPR-by-design.** Мінімум персональних даних, чітка політика зберігання, обов'язкове видалення на запит.
8. **Документація = код.** ADR (Architecture Decision Record) на кожне нетривіальне рішення в `docs/03_DECISIONS.md`.

## 3. Архітектура (high-level)

```
[Browser]
  ├─ Next.js (SSR/CSR)
  │    ├─ react-three-fiber (3D viewport)
  │    ├─ OpenCascade.js (легка CAD-операція: parametric update, preview mesh)
  │    └─ Auth.js client
  │
  ├─→ Next.js API routes (BFF, тонкий шар)
  │
  └─→ Fastify API (Node.js, TypeScript)
         ├─ PostgreSQL (Drizzle ORM)
         ├─ Redis (cache + BullMQ queue)
         ├─ Cloudflare R2 (S3-compatible: DXF/PDF/STEP, thumbnails)
         └─→ CAD Worker (Python, FastAPI + CadQuery)
                ├─ heavy: розгортка з k-фактором, експорт DXF/PDF/STEP
                ├─ збереження артефактів у R2
                └─ повертає presigned URL → BullMQ → Fastify → клієнт
```

**Чому два мови (TS + Python):** OpenCascade.js надійний для preview, але важкі операції (точна розгортка, PDF з ізометрією, валідація колізій) на CadQuery (Python) — швидше, стабільніше, краще задокументовано.

**Як спілкуються:** Fastify ставить задачу в BullMQ, окремий Python-worker слухає Redis, виконує, кладе результат у R2, оновлює запис у Postgres. Frontend опитує статус через WebSocket (Server-Sent Events).

## 4. Структура монорепо

```
flatcraft/
├── apps/
│   ├── web/           # Next.js 15, App Router, react-three-fiber
│   └── api/           # Fastify + TypeScript
├── workers/
│   └── cad/           # Python 3.12 + FastAPI + CadQuery + BullMQ-Python
├── packages/
│   ├── cad-engine/    # TS bindings до OpenCascade.js + утиліти геометрії
│   ├── db/            # Drizzle schema + міграції + seed
│   ├── types/         # Zod-схеми, спільні DTO між web/api/worker
│   └── ui/            # shadcn/ui + кастомні компоненти (3D viewport, Wizard, BomTable)
├── infra/
│   ├── docker/        # Dockerfile-и
│   ├── compose/       # docker-compose.{dev,prod}.yml
│   └── ansible/       # налаштування Mirohost Cloud сервера + R2 + Cloudflare DNS
│                      # (Terraform не використовуємо — Mirohost не має провайдера; див. ADR-011)
├── docs/              # ADR, ризики, data model, API contract, bend-machine spec
└── tools/
    └── scripts/       # shell + node-скрипти (seed, lint, generate-types)
```

## 5. Конвенції коду

**TypeScript:**

- `strict: true`, `noUncheckedIndexedAccess: true`, `exactOptionalPropertyTypes: true`.
- Жодного `any` (тільки `unknown` з narrow-логікою).
- Імпорти абсолютні через `@flatcraft/*` (path mapping).
- Назви файлів: `kebab-case.ts`. React-компоненти: `PascalCase.tsx`.
- Експорти named, не default (виняток — Next.js page файли).

**Python (CAD worker):**

- Python 3.12, `mypy --strict`, `ruff` для лінту і форматування.
- Залежності через `uv` (швидкий аналог pip).
- Кожен handler — pure-функція з типізованим вхід-вихід.

**Тести:**

- Frontend: Vitest + React Testing Library + Playwright (e2e на ключовий happy path).
- Backend: Vitest + supertest. Інтеграційні тести проти реальної Postgres у Docker (testcontainers).
- CAD worker: pytest + pytest-cov. Снепшоти DXF (фіксований seed → фіксований байт-output).
- Покриття: цільове 80% по `src/`, але важливіше — мутаційне тестування на ключових модулях (Stryker для TS).

**Git:**

- Trunk-based: одна гілка `main`, feature-branches короткоживучі (≤ 2 дні).
- Conventional Commits: `feat:`, `fix:`, `refactor:`, `chore:`, `docs:`, `test:`.
- PR обов'язковий, навіть solo (для history). Squash merge.
- Pre-commit hook: `lefthook` → lint, type-check, test, форматування.

## 6. Що Claude Code _робить_ і _не робить_

✅ **Робить автоматично:**

- Створює feature-branch і робить commit після кожної логічної зміни.
- Запускає `pnpm test`/`pytest` після зміни. Не зупиняється, поки тести не зелені.
- Оновлює відповідну ADR у `docs/03_DECISIONS.md`, якщо рішення архітектурне.
- Додає типи у `packages/types`, якщо змінює API.

❌ **Не робить без явної згоди:**

- Не додає нові залежності top-level (тільки в межах існуючих apps/packages).
- Не змінює `docker-compose.yml` без узгодження.
- Не пише код у `infra/ansible/` без явного завдання.
- Не торкається `packages/db/migrations/` без явної інструкції — міграції створюються вручну через `drizzle-kit`.

## 7. CAD-обмеження (must-know для будь-якого CAD-завдання)

| Параметр                      | Значення MVP                                                                                                    |
| ----------------------------- | --------------------------------------------------------------------------------------------------------------- |
| Матеріали                     | сталь холоднокатана, сталь гарячекатана, оцинкована, нержавійка AISI 304/430, алюміній АМг3/5754, мідь, латунь  |
| Діапазон товщин               | 0.5 – 8 мм для всіх матеріалів                                                                                  |
| Макс. довжина гиба            | 3050 мм                                                                                                         |
| Макс. зусилля гибки           | 100 т                                                                                                           |
| Мін. ширина полиці після гиба | 7.5 мм                                                                                                          |
| Точність кута                 | ±0.25°                                                                                                          |
| Мін. внутрішній радіус гиба   | див. `docs/07_BEND_MACHINE_SPEC.md` (заповнюється окремо)                                                       |
| K-фактор                      | див. таблицю в `docs/07_BEND_MACHINE_SPEC.md`; default 0.4 для м'яких сталей, 0.33 для алюмінію, 0.45 для нержі |
| Стандарт креслень             | ISO/EN ISO 7200                                                                                                 |
| Допуски                       | ДСТУ ISO 2768-m                                                                                                 |

**Перевіряти при кожній зміні параметрів моделі:**

1. Товщина у дозволеному діапазоні.
2. Радіус гиба ≥ мін. для (матеріал, товщина).
3. Полиця після гиба ≥ 7.5 мм.
4. Габарит у площі заготовки ≤ 3050 × (макс. ширина листа з прайсу).
5. Перетинів геометрії немає (через CadQuery isValid).

Якщо будь-яка перевірка падає — у UI підсвічуємо червоним конкретне обмеження, експорт блокується.

## 8. Безпека і дані

- **Жодних PII у логах** (auto-redaction у pino + sentry beforeSend).
- **Парольний хеш** — Argon2id (через `@node-rs/argon2`).
- **Сесія** — JWT short-lived (15 хв) + refresh у HttpOnly Secure SameSite=Lax cookie.
- **CSRF** — double-submit cookie + same-site cookies.
- **Rate-limit** — глобальний 100 req/min/IP, на експорт — 5/хв/user.
- **Валідація вхідних даних** — лише Zod, ніяких ручних `if (!body.foo) throw`.
- **Секрети** — тільки через `.env` (не в коді), у dev — `.env.example` з плейсхолдерами.
- **Sentry без PII** — `beforeSend` фільтрує email/ip.

## 9. Performance budget

| Що                                     | Бюджет                                    |
| -------------------------------------- | ----------------------------------------- |
| First Contentful Paint (web)           | < 1.5 c на 4G                             |
| Time to Interactive (web)              | < 3.0 c                                   |
| Update параметра → перерахунок 3D mesh | < 200 мс (на browser-side OpenCascade.js) |
| Експорт DXF простого виробу            | < 3 c (worker → R2 → presigned URL)       |
| Експорт PDF простого виробу            | < 5 c                                     |
| API p95                                | < 200 мс (без CAD)                        |
| DB query p95                           | < 50 мс                                   |

## 10. Як просити Claude Code про роботу

**Поганий промпт (junior typical):**

> "Зроби логін"

**Гарний промпт:**

> "Реалізуй email+password реєстрацію в `apps/api`. Використай Auth.js Credentials provider, Argon2id для хешу. Додай ендпоінти `POST /auth/register`, `POST /auth/login`, `POST /auth/logout`, `POST /auth/refresh`. Збережи юзера в `users` (вже в schema). Напиши Vitest для happy path і двох помилок (duplicate email, weak password). Оновити `docs/06_API_CONTRACT.md`."

Завжди вказуйте: **де** (apps/path), **що використати** (бібліотеки), **що повернути** (response shape), **які тести**, **який доку-файл оновити**.

## 11. Цикл розробки (sprint loop)

1. Беремо найвищий пункт з `docs/02_ROADMAP.md`.
2. Створюємо issue в GitHub з критеріями приймання.
3. Branch `feat/<short-name>`.
4. TDD: тест → код → рефактор.
5. PR → автотести → code review (навіть soло — самоогляд через 12 годин на свіжу голову).
6. Merge → tag → deploy → перевіряємо на staging → продакшн.
7. Update Roadmap + DECISIONS, якщо щось змінилось.

## 12. Ключові посилання

- **Карта підпроєктів: `AGENTS.md`** — прочитай одразу після цього файлу. Claude Code НЕ вантажить його автоматично, але там опис кожного workspace, команди, структура.
- Roadmap: `docs/02_ROADMAP.md`
- Architecture Decision Records: `docs/03_DECISIONS.md`
- Risks: `docs/04_RISKS.md`
- Data model: `docs/05_DATA_MODEL.md`
- API contract: `docs/06_API_CONTRACT.md`
- Bend machine spec: `docs/07_BEND_MACHINE_SPEC.md`
- Deployment runbook: `docs/08_DEPLOYMENT.md`
- Staging preflight checklist (manual setup до Ansible): `docs/09_STAGING_PREFLIGHT.md`
- Design system: `docs/10_DESIGN_SYSTEM.md` (ADR-016)
- Open questions: `docs/00_OPEN_QUESTIONS.md` · відповіді: `docs/01_ANSWERED_QUESTIONS.md`
- Опитувальник з відповідями: `01_questionnaire_answers.md`

## 13. Поточний стан

- **Phase 0.1 завершено** (2026-05-15): скелет монорепо створено, `pnpm install` і `pnpm typecheck` зелені по всіх 10 workspace, git ініціалізовано.
- **Phase 0.2 завершено** (2026-05-16): `docker compose up -d` піднімає Postgres 16, Redis 7, MinIO + bucket init, Mailpit — усі healthy.
- **Phase 0.3 завершено** (2026-05-16): drizzle schema на 12 таблиць (`docs/05_DATA_MODEL.md`), перша міграція `0000_wandering_vapor.sql` застосована до живої БД, seed додав 7 матеріалів × 10 товщин (нержавійка 10мм виключена) + 5 шаблонів-placeholder. 27 unit-тестів зелені. UUID v4 наразі — ADR-012.
- **Phase 0.4 завершено** (2026-05-16): Fastify factory з ZodTypeProvider, GET /health, pino з PII-redact (auth headers, cookie, body.email, body.password, \*.refreshToken), env через Zod. 11 unit-тестів.
- **Phase 0.5 завершено** (2026-05-16): Next.js 15 App Router + Tailwind, R3F куб (v9, drei v10 — потребували bump через несумісність з React 19), `dynamic(ssr:false)` для три.js, Playwright e2e (2 тести). Куб обертається у браузері на :3000.
- **Phase 0.6–0.8 завершено** (2026-05-16): GitHub Actions CI (install → lint/typecheck/test/build → e2e з Postgres service), lefthook вже працює (pre-commit eslint/typecheck/prettier на staged + pre-push pnpm test), README з 5-min setup інструкцією.
- **Phase 0 повністю закрита.**
- **Phase 1 повністю закрита** (2026-05-16): CAD core готовий end-to-end.
  - cad-engine (TS): spec loader, validators (sheet/bend/holes), k-factor — 36 тестів.
  - workers/cad (Python 3.12 + CadQuery + ezdxf): L-bracket Pydantic+builder, unfold з K, DXF export з 5 шарами + детермінізм через post-write normalize — 41 pytest, 100% coverage.
  - L-bracket Zod-схема у packages/types (9 тестів) — спільний контракт між web/api/worker.
  - CLI: `cd workers/cad && uv run pytest` — повний цикл.
- **Phase 2.1 завершено** (2026-05-16): `GET /templates` (Fastify + drizzle, integration через postgres) + web сторінка `/templates` з grid карток (Next.js server component + Tailwind). L-bracket — єдиний опублікований; решта 4 приховані до Phase 2.10. Seed змінено на `onConflictDoUpdate`, щоб переключення `is_published` відбивалося. Playwright тепер запускає api+web webServer масивом, CI postgres service гарантує live БД у e2e.
- **Phase 2.2 завершено** (2026-05-16): `GET /templates/:slug` (Detail з defaultParameters), web `/templates/[slug]` зі студією: controlled-editor параметрів (live Zod-validation) + R3F viewport з ExtrudeGeometry-mesh, що live-оновлюється при зміні параметрів. Thickness — поки фіксовано 2.0мм (UI-вибір — Phase 2.4). 8 Playwright e2e, 26 db/types unit, 4 api integration.
- **Phase 2.3 завершено** (2026-05-16): R3F-сцена і pure-builder перенесено у `@flatcraft/ui`. peerDeps оновлено на R3F v9 + drei v10 (React 19). apps/web консумує `LBracketScene` через `dynamic(ssr:false)`.
- **Phase 2.4 завершено** (2026-05-17): `packages/ui/parameter-form/` — pure `introspectSchema(zodObject) → FieldDescriptor[]` (13 unit) + AutoForm React-компонент. L-bracket editor мігровано з ручних inputs на AutoForm; testIds збереглися, e2e зелені. Holes (array) поки не підтримується generic'ом — рендериться окремим renderField override (повноцінний holes-editor у Phase 2.7).
- **Phase 2.5 завершено** (2026-05-17): `zodIssuesToFieldErrors` (6 unit) + AutoForm errors prop. Невалідні поля: border-red + aria-invalid + inline `<ul>` під полем; data-invalid="true" на label для e2e. Editor wrapper передає Zod issues у згрупованому вигляді. 9 e2e зелені.
- **Phase 2.6 завершено** (2026-05-17): debounce 100мс на mesh-rebuild через `useDebouncedValue` (6 unit на pure createDebouncer). OpenCascade.js bridge відкладено — ADR-013: three.js Shape + ExtrudeGeometry достатньо для MVP, точна геометрія — CadQuery server-side.
- **Phase 2.7 завершено** (2026-05-17): sync Export pipeline web → api → cad-worker → S3 presigned URL. Python FastAPI /export (boto3 + moto тести, 6 pytest 96% cov), Fastify POST /exports з CORS + Zod-валідація обох directions (5 unit з mock fetch), Web ExportButton з idle/loading/success/error станами (3 e2e).
- **Phase 2.8 завершено** (2026-05-17): async export з SSE прогресом. API: in-memory `JobStore` з pub/sub (7 unit), POST /exports → 202+jobId, GET /:id, GET /:id/events (SSE через `reply.raw.write`). Web: `subscribeExportEvents` через EventSource, ExportButton показує progress bar 0..100%, при done/failed закриває source. BullMQ distributed — Phase 5.
- **Phase 2.9 завершено** (2026-05-18): PDF export через ReportLab — header, розгортка з bend line, bend table, BOM, QR-код. `compute_bom` pure-функція (3 unit з аналітичними числами). /export тепер повертає `artifacts.{dxf,pdf}` (breaking — синхронізовано web/api/python). Ізометрія 3D пропущена до Phase 5 (потребує WebGL→PNG pipeline).
- **Phase 2.10.a завершено** (2026-05-18): Z-кронштейн end-to-end. Z-bracket Zod (7 unit) + Pydantic, CadQuery builder з 3 секцій (74 pytest, 99% cov), unfold з 2 гибами `L = flat_b + BA + flat_m + BA + flat_t`, generic `_export_flat_dxf(bend_lines_mm: tuple[float, ...])` для повторного використання L/Z, `_draw_unfold_generic` + `_draw_z_bracket_bend_table` у PDF. `ExportRequestSchema → z.discriminatedUnion("template_slug")` (тепер l_bracket | z_bracket payload). Web: ZBracketScene (3 BoxGeometry у group), ZBracketStudio/Editor/Viewport, ExportButton перероблено на `request: ExportRequest` (template-agnostic). 3 нові Playwright e2e (15 разом). Seed: z_bracket → isPublished=true з `Z_BRACKET_DEFAULT_PARAMETERS`.
- **Phase 2.10.b завершено** (2026-05-18): corner_angle (підсилювальний кутник з auto-grid отворів). Геометрія = L-bracket, але holes генеруються з `hole_rows × hole_cols × hole_margin` замість ручних координат — типовий меблевий кутник "купив і прикрутив". `_distribute(n, lo, hi, margin)` pure-функція (4 unit) у unfold.py. `Hole2D` dataclass — спільна для майбутніх perfo-шаблонів. `_export_flat_dxf` приймає `holes: tuple[Hole2D, ...]` → CIRCLE entities на INNER_CUTS layer. `_draw_unfold_generic` рендерить червоні кружечки у PDF. CornerAngleScene reuse'є `buildLBracketShapeCommands` + малює CylinderGeometry для кожного отвору (axis ‖ Y для B, ‖ X для A після rotate). discriminatedUnion розширено третім варіантом. Seed: corner_angle → isPublished=true. 97 pytest (99% cov, +23 нових), 32 db tests, 4 нові e2e (19 разом).
- **Phase 2.10.c завершено** (2026-05-18): wall_shelf U-channel (back + shelf + optional front_lip). 3 сегменти, 2 гиби в одну сторону, з підтримкою front_lip=0 (тоді 2 сегменти, 1 гиб — вироджена форма). Auto-grid mounting holes на back-секції (для дюбелів). Pydantic `_lip_zero_or_min5` validator + Zod `WallShelfParametersBaseSchema` (plain) + `WallShelfParametersSchema` (refined) — base йде у `discriminatedUnion` (вимагає ZodObject), refined — у редактор. Reuse `_export_flat_dxf(holes)` + `_draw_unfold_generic` без модифікацій. R3F: 2-3 BoxGeometry + cylinder mounting holes (axis ‖ X через rotate Z). 118 pytest (99% cov, +21 нових), 33 db tests, 4 нові e2e (23 разом).
- **Phase 2.10.d завершено** (2026-05-18): perforated_panel — плоский лист з centered grid отворів за pitch'ом. Принципово відрізняється від решти Phase 2.10: НЕ має гибів. Layout автоматичний: `n_cols = floor((length-2*margin)/pitch_x) + 1`, eff_margin перераховується для симетрії. Web/Python обчислюють однаково. Reuse `_export_flat_dxf(holes, bend_lines=())` без модифікацій — generic exporter довів свою архітектурну вартість на 4-му шаблоні. PDF без bend table — натомість Hole grid summary. 3D: BoxGeometry + cylinder overlay з cap'ом 500 отворів (поза cap'ом — лише box, точна геометрія у DXF). 137 pytest (99% cov, +19 нових), 34 db tests, 4 нові e2e (27 разом).
- **Phase 2 повністю закрита**: 5 шаблонів end-to-end.
- **Phase 2.11 завершено** (2026-05-30): фундамент design system (ADR-016, `docs/10_DESIGN_SYSTEM.md`). Warm-industrial OKLCH-токени у `apps/web/src/app/globals.css` (~38 шт, **light-only**, без .dark), Tailwind 3.4 mapping з mobile-first breakpoints (`xs: 360 → xl`), self-hosted Inter + JetBrains Mono через next/font/google (subset latin+cyrillic). `@flatcraft/ui` доповнено: `primitives/` (Button з CVA + 6 варіантами incl. `zsu`, Dialog re-export), `components/` (Logo, UkraineStripe, Footer), `lib/` (contrastRatio + cn), `icons.ts` (lucide re-export — apps/web не тягне власних UI-deps). Сторінка `/styleguide` під `(dev)/`-group, `notFound()` коли `NEXT_PUBLIC_ENV !== "dev"`, 12 секцій + contrast-table з inline-обчисленим WCAG ratio. TDD `contrastRatio` (10 unit, OKLCH→Linear sRGB→Luminance), 6 нових Playwright e2e (3 viewports console-clean + UkraineStripe 2px + tap-target ≥44 + dev-gate). **R-02 переписано** на progressive enhancement (mobile = спрощена 3D-сцена без HDR/shadows + touch-first форми, повноцінне редагування — інваріант) → впровадження у Phase 2.14. Існуючі екрани (`/`, `/templates`, `/templates/[slug]`) тимчасово візуально неконсистентні (zinc/emerald), адаптація — Phase 2.12+ окремими PR'ами.
- **Phase 2.12.a завершено** (2026-05-31): editor form polish — групування + матеріал + cleanup zinc/emerald (ADR-017, ADR-018, `docs/10_DESIGN_SYSTEM.md §6.2`). **API:** новий `GET /materials` (JOIN materials↔material_thicknesses, нержавійка без 10мм, 4 integration tests); ExportRequest тепер вимагає `material_code` (3 нові unit), API strip'ить його перед cad-worker forward (ADR-018: Python `extra="forbid"` лишається недоторканим). **Types:** `MaterialChoice` Zod-схема у `@flatcraft/types/domain/materials.ts`. **UI:** AutoForm (`@flatcraft/ui/parameter-form`) розширено — `parseDescription()` читає Zod `.describe("group:G|label:L")` → `FieldDescriptor.group/label` (ADR-017), рендерить fieldset/legend секції з токенами Phase 2.11 (+5 unit). Новий `MaterialSection` (controlled material+thickness selects, перша секція форми). **Schemas:** 5 шаблонів отримали `.describe()` з UA-групами (Полиця A/B, Гиб, Отвори тощо). **Web:** студії підняли material+thickness у state, передають у ExportRequest; ExportButton переписано на `<Button>` primitive (`bg-emerald-700` → `bg-primary`); `<details>Параметри (JSON)</details>` сховано за `IS_DEV`. **Tests:** 7 нових Playwright e2e (legends всіх груп, default cold_rolled_steel+2.0мм, dynamic thickness options, request body intercept material_code, 3 viewports console-clean), нуль регресій у 37 існуючих → разом 44/44 ✓.
- **Phase 2.12.b завершено** (2026-05-31): landing redesign (`docs/10_DESIGN_SYSTEM.md §7 Hero pattern`). **Hero:** headline «Креслення листового металу за 60 секунд», primary CTA на `/templates`, secondary anchor «Як це працює ↓». Замість статичного `<SpinningCube>` — **HeroLoopDemo**: pure `nextDemoParams(tMs)` (12 unit, TDD) детермінований 16-сек цикл через 4 фази (legA 50→200 → legB 50→200 → bend_radius RADII step → width 100→300), RAF driver з tick 100мс desktop / 200мс mobile (matchMedia), hover-пауза через `useRef`. Новий `useReducedMotion` hook у `@flatcraft/ui/hooks` (matchMedia, SSR-safe) — при `prefers-reduced-motion: reduce` НЕ запускає RAF, рендерить статичний бракет + caption. Dynamic ssr:false wrapper із skeleton (no CLS). **«Як це працює»:** 3 step-cards (LayoutGrid → Sliders → FileDown). **Trust-row:** 3 блоки — `10 експортів/міс безкоштовно`, `Heart→UNITED24`, `Github→github.com/stjurik/flatcraft`. **SiteLinks** (app-local, 3 колонки: Продукт / Спільнота / Юридичне) у Footer через новий `linksSlot` prop (`@flatcraft/ui` Footer розширено). Placeholder сторінка `/soon` для майбутніх лінків. lucide-icons (Activity, Gift, Heart, Github, LayoutGrid, Sliders + `LucideIcon` type) додано у `@flatcraft/ui/icons.ts`. **Tests:** 12 нових Playwright e2e (hero structure, CTA navigation, anchor scroll, step-cards, trust-blocks, RAF canvas, reduced-motion caption, console-clean × 3 viewports, tap-targets ≥44, `/soon`); знадобився `page.emulateMedia({reducedMotion:'reduce'})` замість `test.use({reducedMotion})` (1.48 не doходить до matchMedia). 53/53 e2e ✓ (нуль регресій). og:image — TODO у Phase 2.16 (мало бути 1200×630 PNG з логотипом і headline).
- **Phase 2.13 завершено** (2026-05-31): каталог `/templates` redesign (`docs/10_DESIGN_SYSTEM.md §8 Card pattern`). **TemplateCard переписано:** `<article>` wrapper з `shadow-md → shadow-lg` на hover (без вкладених `<a>`), ДВА окремі link'и — clickable h3-title + explicit `<Button variant="default">` «Налаштувати →» (a11y-correct, обидва клавіатурно-навігабельні). Thumb-region `aspect-[4/3] bg-surface-sunken` з inline SVG-схемами. **`TemplateThumb` dispatcher** (`apps/web/src/components/template-thumb.tsx`, 6 unit TDD): 5 schematic-SVG (L-форма, Z-форма, L+holes-grid, U-channel+mounts, rect+3×3 grid) + fallback `<Box>`. `stroke="currentColor"` дозволяє `group-hover` тоном з картки. **Page /templates:** mini-hero на warm `bg-bg`, grid на `bg-surface-sunken`, error/empty states токенізовані; dev-hints (`pnpm db:seed`, `pnpm api dev`) під `IS_DEV` gate. **Vitest fix:** додано `esbuild.jsx = "automatic"` у `apps/web/vitest.config.ts` (без цього JSX-тести падали `React is not defined` — base tsconfig має `jsx:"preserve"` для Next, але vitest використовує esbuild напряму). **Tests:** 6 нових unit (template-thumb dispatcher), 7 нових Playwright e2e (existing 5-cards тест збережено; +CTA navigation, title-link navigation, tap-targets ≥44, console-clean × 3 viewports). 5 старих «картка → деталь» тестів (template-detail, corner-angle, z-bracket, wall-shelf, perforated-panel) адаптовано: тепер клікають `template-card-cta` замість всього card-wrapper. **59/59 e2e ✓** (нуль регресій). Реальні preview-PNG — TODO у Phase 2.16.
- **Phase 2.14.a завершено** (2026-06-01): mobile-friendly studio + progressive 3D (R-02 mitigation, `docs/10_DESIGN_SYSTEM.md §9`). **Pure helper** `viewportQuality({isMobile, reduced})` у `@flatcraft/ui/lib/viewport-quality.ts` (5 unit, TDD) з адаптивною матрицею: desktop `dpr=[1,2]`/zoom/rotate/100ms/curve=12; mobile `dpr=[1,1.5]`/**no-zoom** (pinch-конфлікт із браузером)/rotate/250ms/curve=8; reduced `dpr=[1,1]`/no-zoom/no-rotate/400ms/curve=6 (reduced має пріоритет над mobile). **Новий хук** `useIsMobile` у `@flatcraft/ui/hooks/` — matchMedia `(max-width: 767px)`, SSR-safe, mirror `useReducedMotion`. **Apply у 5 scenes:** Canvas `dpr={[...quality.dpr]}` (spread бо R3F Dpr type не приймає readonly tuple), OrbitControls `enableZoom`/`enableRotate` per quality; L-bracket ExtrudeGeometry отримує `curveSegments` адаптивно. **Apply у 5 студіях:** `useDebouncedValue(parameters, quality.debounceMs)` замість раніше hardcoded 100. **`<StudioPreviewAnchor>`** (`apps/web/src/components/studio-preview-anchor.tsx`) — anchor «↓ Подивитися 3D-прев'ю» з `lg:hidden`, скролить до `#studio-viewport`. **Token cleanup у 5 viewport-wrappers**: `border-zinc-800 bg-zinc-950/60` → `border-border bg-surface-sunken`; loading-state теж токенізовано. **Tests:** 5 нових unit (viewport-quality), 9 нових Playwright e2e (5 шаблонів × console-clean + scroll-to-anchor + tap-targets selects/export ≥44 + anchor lg:hidden). **68/68 e2e ✓** (нуль регресій).
- **Phase 2.14.b завершено** (2026-06-01): round-bend cross-section для Z-bracket і wall-shelf scenes. **Аудит scope:** з попередньо запланованих 3 scenes реально потребували rewrite **тільки 2** — corner_angle уже reuse'є `buildLBracketShapeCommands` (round bend був з Phase 2.10.b), perforated_panel — плоский лист без гибів. **Нові pure shape-builders** у `packages/ui/src/3d-viewport/geometry.ts`: `buildZBracketShapeCommands` (2 inner concave bends — bottom→middle і middle→top, 11 ShapeCommand) і `buildWallShelfShapeCommands` (1 або 2 inner bends умовно по front_lip — back→shelf завжди, shelf→lip опціонально). **13 нових unit-тестів** (TDD: command counts, control-point coords, throws на invalid). **Сцени переписано:** `z-bracket-scene.tsx` і `wall-shelf-scene.tsx` тепер `ExtrudeGeometry+Shape` (як L-bracket), bounding-box centering. Wall-shelf зберігає mounting-hole cylinders (переcцентровані під новий bounding box). `curveSegments` тепер адаптивний у всіх 3 ExtrudeGeometry-scenes. **68/68 e2e ✓** (нуль регресій — testIDs незмінні, геометрія візуально точніша). Python CadQuery server-side лишається на BoxGeometry-union — точна DXF-геометрія не страждає (3D preview і unfold можуть розходитись; виправлення server-side — окрема задача post-MVP).
- **Phase 2.16.a завершено** (2026-06-01): Open Graph image для лендінга через Next.js App Router file-convention (`apps/web/src/app/opengraph-image.tsx`). Next автоматично рендерить файл і додає `<meta property="og:image">` + `twitter:image` з повним набором атрибутів (width/height/type/alt — з module-level exports `alt`, `size`, `contentType`). **Дизайн 1200×630:** warm-bg + wordmark «hart.crimea.ua» (Inter SemiBold + Regular з opacity) + headline «Креслення листового металу за 60 секунд.» (Inter Bold 68px) + sub-line «Без CAD-навичок · DXF + PDF · 10 експортів/міс безкоштовно» + ember-stripe + схематичний L-bracket SVG у white card праворуч (репродукує стиль `<TemplateThumb>`) + 4px UkraineStripe знизу. **Bundled Inter TTF** (Regular/SemiBold/Bold, OFL 1.1, ~410KB кожен) у `apps/web/src/app/_og-fonts/` — приватний route (підкреслення-префікс), читається через `readFileSync` на server-side render. Satori не має вбудованих шрифтів; Cyrillic потребує explicitly bundled font. **Metadata у `layout.tsx`:** `metadataBase`, `openGraph` (uk*UA locale, type=website, siteName), `twitter` (card=summary_large_image). НЕ задаємо `openGraph.images` явно — Next додає сам з opengraph-image.tsx (інакше було б дублювання). **Tests:** 3 нові Playwright e2e — PNG magic-bytes (0x89PNG) + content-type на `/opengraph-image`, повний набір og:* і twitter:\_ meta-тегів у `<head>` сторінки `/`. **71/71 e2e ✓** (нуль регресій). Phase 2.16.b (реальні preview-PNG для каталога через R3F→canvas snapshot pipeline) — окремий PR, не блокує MVP.
- **Phase 2.16.b завершено** (2026-06-01): реальні preview-PNG для каталога — R3F screenshot pipeline. **Pipeline:** `tools/scripts/generate-template-previews.ts` — Playwright headless Chromium (2× DPR, 1280×800) обходить 5 студій на локальному стеку, чекає R3F canvas (15s timeout + 800ms для frame), робить screenshot `[data-testid="<slug>-viewport"]` (з border-border + bg-surface-sunken — консистентно з карткою). 5 PNG у `apps/web/public/template-previews/` (12-27KB кожен, 1280×720). `pnpm --filter @flatcraft/web preview:generate` — manual rerun при зміні геометрії/кольорів. **Seed** (`packages/db/src/seed.ts`): `TemplateSeed` розширено полем `previewImageUrl: "/template-previews/<slug>.png"`; upsert у `seedTemplates` синхронізує DB при re-deploy через api-entrypoint (ADR-015). **Schema relaxation у `@flatcraft/types`:** `TemplateSummarySchema.previewImageUrl` — `z.string().url().nullable()` → `z.string().min(1).nullable()` (relative paths `/template-previews/*` валідні для `<img src>`). **TemplateCard** уже мав ternary `previewImageUrl ? <img> : <TemplateThumb>` (Phase 2.13) — тепер рендериться `<img>` для всіх 5 шаблонів; SVG-thumb лишається fallback для legacy/майбутніх записів з `previewImageUrl=null`. **Tests:** existing `templates.spec.ts` адаптовано — тепер очікує `<img>` з `src` match'ить `/template-previews/<slug>.png`. **71/71 e2e ✓**. **Gotcha:** виявлено baseUrl regression у dev — після зміни Zod-schema у `@flatcraft/types`, потрібно rebuild types (`pnpm --filter @flatcraft/types build`) ПЕРЕД rebuild web, бо apps/web споживає dist через workspace-link. Локальний `pnpm build` у apps/web без попереднього `types:build` отримує stale Zod з `url()` — runtime 500 на parse() з API response.
- **Phase 5 INFRASTRUCTURE (паралельний трек, in progress, 2026-05-18..22):**
  - **5A (2026-05-18)** — `infra/compose/docker-compose.prod.yml` + `Caddyfile` + `.env.prod.example`: 6-сервісний staging-стек (postgres/redis/cad-worker/api/web/caddy) з internal+web мережами, mem_limits (worker 1.5g), healthcheck на всіх, Caddy з CF Origin Cert (ADR-014). CI job `compose-validate` (docker compose config + caddy adapt).
  - **5B (2026-05-18)** — prod Dockerfiles review + smoke build. Fix: `cad-worker.Dockerfile` CMD → `uvicorn flatcraft_cad.server:app`; `--ignore-scripts` у `pnpm install/deploy` (lefthook потребує git, якого нема у alpine); `next.config.ts` += `output: "standalone"`; OCI labels у всіх трьох. `.dockerignore` створено. Smoke: api 317MB, web 303MB, cad-worker 1.96GB; cad-worker boot ~13с.
  - **5C (2026-05-18)** — Ansible playbook + 6 ролей (base/docker/firewall/flatcraft/backups/monitoring) для Debian 12 на Mirohost MS21. Кожна роль має `README.md` з «що + чому». Backups: pg_dump (-Fc) → age encrypt → rclone у R2 (cron 03:00). Monitoring: bash + Discord webhook (state-tracked, не спамить) + weekly image prune. CI job `ansible-validate` (syntax-check + ansible-lint profile "production").
  - **5D (2026-05-18)** — GH Actions: `release.yml` (push tags v*.*._ або workflow_dispatch → builds 3 GHCR пакети `flatcraft-<service>` з tag matrix sha/staging/v_/latest), `deploy-staging.yml` (manual workflow_dispatch → SSH + ansible --tags deploy + smoke curl). Image-naming aligned: `ghcr.io/<owner>/flatcraft-<service>`. Vault commitable (encrypted); lefthook check `$ANSIBLE_VAULT` header.
  - **5 hotfix (2026-05-22)** — backup.sh: прибрав зайвий `gzip` (pg_dump -Fc вже стискає), додав explicit `PGPASSWORD` через `sh -c`. `.gitignore` inline-comment ламав pattern для `inventory.staging.ini` — реальний файл з origin IP був готовий потрапити у commit; перевірка `git check-ignore` тепер OK.
  - **5E (2026-05-22)** — `docs/08_DEPLOYMENT.md` runbook. 6 розділів (preflight/setup/first deploy/regular deploy/incidents/secret rotation), кожен крок із `✓ Verify:` блоком. Покриває: Mirohost order, CF DNS+R2+Origin Cert, WAF, secrets, Ansible flow, rollback по sha, restore з R2 backup, OOM diagnostics.
  - **5F (2026-05-28)** — перший реальний staging deploy виконано + автоматизовано через GitHub. Стек живий на `staging.hart.crimea.ua` / `api-staging.hart.crimea.ua`. Ключове: deploy-флоу не застосовував міграції → `GET /templates` 500. Фікс — **migrate+seed у entrypoint api-контейнера** (ADR-015): `init-prod.js` (явний `runMigrations`+`runSeed`, не `isMain` — симлінк `pnpm deploy`), db-build копіює `.sql` у `dist`, `ENTRYPOINT` в `api.Dockerfile`. `group_vars/all.yml` тепер трекається (CI `vars_files` його вимагає). Повний CI-флоу провалідовано end-to-end: `release.yml` (workflow_dispatch → `:staging` образи) → `deploy-staging.yml` (ansible `--tags deploy` + smoke). GH secrets (SSH/vault/host) налаштовані; deploy-SSH-ключ перевипущено (старий у GH secret був CRLF-corrupt → `libcrypto`).
  - **5G (2026-05-29)** — добивання хвостів 5F + перша пост-5F web-зміна через повний deploy-флоу. Дописано **R-11** у `docs/04_RISKS.md` (single-server staging/prod: host/disk/OOM downtime — ризики тепер R-09→R-10→R-11). `deploy_authorized_keys` узгоджено з фактичними ключами на сервері (`deploy@flatcraft-staging` + `deploy@flatcraft-ci`); `ssh_allowed_ips: 0.0.0.0/0` лишено **навмисно на staging** (deploy з динамічних GH Actions runner-IP, auth лише по ключу) — задокументовано inline. Web: hero-CTA «Переглянути шаблони →» на головній → `/templates` (`apps/web/src/app/page.tsx` + e2e). Прокатано end-to-end через `release.yml` → `deploy-staging.yml` (обидва success, smoke зелений), CTA живий на `staging.hart.crimea.ua`. **Авто-деплой staging увімкнено**: `release.yml` тепер тригериться на push у `main` (пушить `:staging`), а `deploy-staging.yml` — через `workflow_run` (after "Release images" success на main). Тобто кожен merge у main сам їде на staging; ручний `workflow_dispatch` лишився для довільного тегу. 7 застарілих гілок `feat/phase-5-*` видалено (контент давно в main; мердж відкотив би роботу) — `main` тепер єдине джерело істини.
  - **Не зроблено ще:** production deploy (Roadmap 5.10); звузити `ssh_allowed_ips` з `0.0.0.0/0` у `all.yml` перед production (на staging — свідоме рішення, див. 5G).
- Розробка ведеться у WSL Ubuntu-24.04, каталог `~/hart` (native ext4). Хостинг продакшну — Mirohost Cloud (ADR-011).
- Bootstrap-скрипт `setup.sh` у корені — одноразовий, для відтворення середовища з нуля.

---

_Останнє оновлення: 2026-06-01. Коли архітектура змінюється — оновлюйте цей файл першим, потім код._
