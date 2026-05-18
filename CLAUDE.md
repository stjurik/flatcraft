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
- **Phase 2 повністю закрита**: 5 шаблонів end-to-end. **Наступне — Phase 3**: Auth & Limits (Auth.js, donation gate, monthly counter).
- Розробка ведеться у WSL Ubuntu-24.04, каталог `~/hart` (native ext4). Хостинг продакшну — Mirohost Cloud (ADR-011).
- Bootstrap-скрипт `setup.sh` у корені — одноразовий, для відтворення середовища з нуля.

---

_Останнє оновлення: 2026-05-15. Коли архітектура змінюється — оновлюйте цей файл першим, потім код._
