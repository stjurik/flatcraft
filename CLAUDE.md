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
- Pre-commit hook: `lefthook` (`lefthook.yml`). На staged-файлах: ESLint + `tsc` + `prettier --check` (TS/JS/JSON/MD/YAML); для `workers/cad/**/*.py` — `ruff check` (lint), `ruff format --check` (формат, `python-format`-хук — парність з CI), `mypy --strict`. Pre-push: `pnpm test`. **Важливо:** `ruff format` для Python ганяється і локально, і в CI — форматуй Python через `uv run ruff format` перед commit, інакше `python-format` (і CI `ruff format --check .`) впаде.

## 6. Що Claude Code _робить_ і _не робить_

✅ **Робить автоматично:**

- Створює feature-branch і робить commit після кожної логічної зміни.
- Запускає `pnpm test`/`pytest` після зміни. Не зупиняється, поки тести не зелені.
- Оновлює відповідну ADR у `docs/03_DECISIONS.md`, якщо рішення архітектурне.
- Додає типи у `packages/types`, якщо змінює API.
- При завершенні фази оновлює `docs/13_PROGRESS_LOG.md` (новий запис нагору) і ротує `CLAUDE.md §13` «Останні 3 milestones» (replace, not append).

❌ **Не робить без явної згоди:**

- Не додає нові залежності top-level (тільки в межах існуючих apps/packages).
- Не змінює `docker-compose.yml` без узгодження.
- Не пише код у `infra/ansible/` без явного завдання.
- Не торкається `packages/db/migrations/` без явної інструкції — міграції створюються вручну через `drizzle-kit`.
- НЕ запускає `pnpm discord:apply` без explicit instruction — це manual-only команда, що пише у live Discord-спільноту (ADR-023). `discord:snapshot`/`discord:diff` — read-only, безпечні.

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
6. Напрям згину (UP/DOWN) задано для кожного гибу — рендериться на креслі **текстом `UP`/`DOWN`** у колонці «Напрям» bend-table і поряд з callout на розгортці (дефолт `down`; Z-кронштейн — `[down, up]`; Hotfix 2.10.e, ADR-019). У DXF напряму НЕ рендеримо (ADR-024) — лише у PDF.

**DXF-інваріант (ADR-024):** експортований DXF має **рівно 2 виробничі шари** — `LASER_CUT` (ACI 7; outer ByLayer + отвори `CIRCLE` explicit color 5) і `BEND_LINES` (ACI 3, dashed). **Жодного `TEXT`/`DIMENSION` entity** (CAM-noise → ризик вторсировини). Текст/розміри/напрям/номери — тільки у PDF. Службові `0`/`Defpoints` ezdxf не дає видалити — лишаються порожніми.

Якщо будь-яка перевірка падає — у UI підсвічуємо червоним конкретне обмеження, **і експорт блокується серверно** (ADR-019: Fastify-gate `POST /exports` + Python parity-валідатор; клієнтська валідація — лише UX, недостатня).

**Render-gate інваріант (ADR-026):** у viewport'ах студій 3D-сцена (R3F `<Canvas>`) рендериться **ЛИШЕ при геометрично валідних параметрах** — `validateProfile` (`packages/cad-engine/src/validators/profile.ts`, паритет з assertion'ами `packages/ui/src/3d-viewport/geometry.ts`) гейтить рендер; при issues показуємо `InvalidParametersFallback` замість сцени. Будь-який uncaught error усередині R3F-піддерева ловиться `R3FErrorBoundary` (backstop, ніколи не white-screen). Той самий `validateProfile` — у формі (банер + блок експорту), Fastify-gate (`validateExportProfile`) і Python worker (`validate/profile.py` → 422).

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
- **Прогрес-журнал: `docs/13_PROGRESS_LOG.md`** — повна історія завершених фаз і хотфіксів.
- Roadmap: `docs/02_ROADMAP.md`
- Architecture Decision Records: `docs/03_DECISIONS.md`
- Risks: `docs/04_RISKS.md`
- Data model: `docs/05_DATA_MODEL.md`
- API contract: `docs/06_API_CONTRACT.md`
- Bend machine spec: `docs/07_BEND_MACHINE_SPEC.md`
- Deployment runbook: `docs/08_DEPLOYMENT.md`
- Staging preflight checklist (manual setup до Ansible): `docs/09_STAGING_PREFLIGHT.md`
- Discord config (community-сервер як IaC): `infra/discord/` + ADR-023; manual-кроки — `infra/discord/MANUAL_SETUP.md`
- Design system: `docs/10_DESIGN_SYSTEM.md` (ADR-016)
- Observability (телеметрія, events, digest): `docs/11_OBSERVABILITY.md` (ADR-032)
- Template Registry contract: `docs/12_TEMPLATE_CONTRACT.md` (ADR-033)
- Стратегія еволюції архітектури (registry/process/feedback): `docs/14_ARCHITECTURE_EVOLUTION.md`
- Бібліотека LLM-промптів і маршрутизація по моделях: `docs/15_LLM_PROMPTS.md`
- Автономні запуски (headless, guard-правила): `docs/16_AUTONOMOUS_RUNS.md`
- Open questions: `docs/00_OPEN_QUESTIONS.md` · відповіді: `docs/01_ANSWERED_QUESTIONS.md`
- Опитувальник з відповідями: `01_questionnaire_answers.md`

## 13. Поточний стан

> Повний журнал — `docs/13_PROGRESS_LOG.md`. Цей розділ — лише snapshot для контексту нових сесій. Тримайте його ≤ 2k chars.

**Де ми зараз (2026-07-17):** staging.hart.crimea.ua live, MVP feature-complete. Master run 4-5 закрили docs-борг: ADR-027 відновлено, Roadmap синхронізовано з фактом (секції Phase 3.0/3.1/3.2/3.4), 4 stale-PR (#28-#31) закрито. **Phase 3.4 (виробничий фідбек, ADR-032 §feedback) завершено** — форма `/f/{exportId}` + `POST /feedback` (PR #69) + реальний QR-permalink у PDF замість fallback-схеми (PR #75/issue #70) — R-01 mitigation 4 закрито. **Телеметрія активована на staging 2026-07-12** (Umami live + Sentry env + digest-webhook; PR #63/#65, hotfix #71-#72); недільний digest-acceptance — 2026-07-19. Перфо-панель — ОДИН шаблон `perforated_panel` (`hole_shape`, ADR-031). Render-gate проти крашу R3F (ADR-026); DXF production-grade (2 шари, ADR-024); PDF з ізометрією (ADR-025). Discord IaC (ADR-023) чекає manual-setup. Наступний фокус — публічний soft-launch.

**Останні 3 milestones:**

- **Feature 3.4 — QR-фідбек з виробництва** (2026-07-17, ADR-032 §feedback, R-01 mitigation 4): замикає self-improvement loop — QR у PDF → мобільна форма `/f/{exportId}` → фідбек → digest бачить deviation-репорти → калібрування K-фактора. Два PR: **#69** (4a7d94d) — C4 UX-copy (Варіант 1 ★), таблиця `export_feedback` (FK на exports.id, drizzle-міграція за явною інструкцією), `POST /feedback/:exportId` (Zod, rate-limit 20/год/IP, 404 на невідомий export*id), подія `feedback_submitted` без PII (агрегати: outcome/has_deviation/has_comment/locale), digest-секція «Виробничий фідбек», UA+EN форма (мобільна-перша, 44px tap-target). **#75/issue #70** (34a2127) — QR раніше тримав непрацюючий fallback `flatcraft://<slug>/<article>`; тепер export_id (== job.id == exports.id) форвардиться api→cad-worker, `{BASE_URL}/f/{export_id}` підключено до всіх 6 `export*<tpl>\_pdf`. DXF без змін (ADR-024); PDF byte-снапшотів у репо нема — regen не знадобився. Тести: worker 339 pytest, api 67 unit, types 146, web 67 unit + 3 нові Playwright e2e. Гілки `feat/phase-3-4-qr-feedback`, `fix/issue-70`.
- **Feature 3.3 — Observability foundation** (2026-07-06, ADR-032): 6 PR перед soft-launch. (1) docs-gate ADR-032 + docs/11; (2) Postgres `events` (Zod-payload'и) + persist `exports` (nullable user/draft, session\*hash з добовим salt); (3) Sentry ×3 web/api/worker з `beforeSend` PII; (4) pure `buildDigest` → Discord webhook (cron нд 18:00); (5) воронка **Umami self-hosted** (vendor-нейтральний `track`, GDPR fail-closed) + web-vitals; (6) цей progress-log. Стек мінімальний (без Prometheus/Grafana/OTel). Аналітика — Umami (окрема БД у наявному Postgres; Plausible відхилено — ClickHouse RAM). PR #54-#58. Міграцію events/exports генерує yurii вручну. Активацію виконано 2026-07-12 (Phase 3.3-B: PR #63/#65 + vault env; hotfix #71-#72).
- **Feature 3.2 — Уніфікація перфо-панелі в один шаблон (hole_shape)** (2026-06-26, ADR-031): злито `perforated_panel` + `perforated_panel_square` у ОДИН ребристий монтажний лоток `perforated_panel`, де форма отвору — параметр `hole_shape` (circle|square); єдина гілка — рендер отвору. Розмір отвору — єдиний `hole_size_mm` (прибрано `hole_diameter_mm` + `syncHoleKeys`). Ребра рендеряться **вниз** (worker `-z`, 3D-сцена `-Y`; узгоджено з `direction='down'`). Видалено по всьому стеку: `perforated_panel_square.py`, `-square.ts`, square-сцену, viewport, shim `perforation-shape.ts`; slug прибирається з БД (`RETIRED_TEMPLATE_SLUGS`). Продукт «Декоративна перфо-панель» → base `perforated_panel` + `fixed hole_shape=square` + `userEditableFields += rib_height_mm`. Toggle круг/квадрат тепер редагує параметр (не свопає slug). DXF/PDF снапшоти перегенеровано; байт-детермінізм збережено. worker 332 pytest / types 134 / cad-engine 71 / ui 96 / web 54 / api 37 / db 51. Гілка `feat/perfo-unify-hole-shape`.

**Інваріанти (must-not-break):**

- У viewport'ах студій сцена R3F рендериться ЛИШЕ при валідних параметрах (`validateProfile` render-gate); будь-який uncaught error у R3F ловиться `R3FErrorBoundary` (ADR-026). `validateProfile` — паритет з assertion'ами `geometry.ts` (клієнт render-gate/банер + Fastify-gate + Python worker).
- PDF/DXF експорт — байт-у-байт детермінований (CLAUDE.md §2.4). Ізометрія (ADR-025) теж: HLR-проєкція + дискретизація детерміновані, геометрія — чиста функція params. `export/isometric.py` головний entry імпортує `OCP.*` напряму (scoped mypy-override).
- Серверна валідація `bend_radius` через cad-engine у Fastify + Python parity (ADR-019). Клієнтська матрична валідація (ADR-022) — лише UX, не замінює серверну.
- `events` — без PII (жодного email/IP); `session_hash` з добовим salt (ADR-032).
- Single source of truth для bend-матриці: `packages/cad-engine/data/bend-machine-esi.yaml`. `bakedSpec` (`src/generated/baked-spec.ts`) — похідний snapshot, регенерується у `prebuild`; не редагувати руками.
- Головний entry `@flatcraft/cad-engine` browser-safe (без `node:*`); fs-loader — лише через subpath `/node`.
- Розробка у WSL Ubuntu-24.04 / `~/hart` (native ext4), не на /mnt/c.
- Hosting: Mirohost Cloud MS21 (ADR-011), single-server staging/prod (R-11).

**Як додати новий запис:** додати ПОВНИЙ опис у `docs/13_PROGRESS_LOG.md` нагору, ОНОВИТИ список «Останні 3 milestones» вище (видалити найстаріший, додати новий зверху). Не append — replace.

---

_Останнє оновлення: 2026-07-17. Коли архітектура змінюється — оновлюйте CLAUDE.md (§1-12) першим. Завершення фази — у `docs/13_PROGRESS_LOG.md` + ротація §13._
