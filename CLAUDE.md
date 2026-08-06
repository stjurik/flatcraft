# CLAUDE.md — головний контекст для Claude Code

> Цей файл — **ваш контракт з Claude Code**. Кожна сесія читає його першим. Тримайте його актуальним: коли змінюється архітектура, конвенція або ризик — оновлюйте.

## 0. Контракт виконавця (читати першим)

> Філософія виконання, а не список задач. Діє на КОЖНЕ завдання: чат,
> Claude Code, headless-run, GitHub Actions, суб-агент. Промпти її не
> переписують — вони посилаються рядком «Працюй за CLAUDE.md §0».

**Хто ставить завдання.** yurii — інженер-конструктор, не програміст. Він
**не оцінює реалізацію — він оцінює готовий продукт**. Це не побажання,
а обмеження приймання, з якого випливає решта.

1. **Приймання — очима на продукті.** Кожен PR/звіт містить «Як перевірити
   очима»: 5-10 тверджень, які yurii перевіряє натисканням у браузері або
   відкриттям файлу, без читання коду. Немає розділу — робота не завершена.
   «Тести зелені» приймання НЕ замінює: зелений тест доводить, що код робить
   те, що написав автор тесту, а не те, що потрібно yurii.
2. **Реалізацію перевіряє не автор.** ШІ-код рев'юїть інший агент (ADR-036:
   `agy`/Gemini або свіжа Claude-сесія); вердикт публікується ДОСЛІВНО.
   Розбіжність двох моделей цінніша за їхню згоду — обидві позиції лишаються
   видимими yurii. Мультиагентність — там, де потрібна **незалежність**
   (рев'ю, adversarial-кейси, звірка фактів), не заради кількості агентів.
3. **Verify-then-write.** Номери PR, статуси, вміст файлів, дати, API
   бібліотек — з тулів, не з пам'яті. **Вигадувати заборонено**: здогад,
   поданий як факт, — найдорожча помилка в цьому проєкті. Не знаєш — з'ясуй
   або запитай.
4. **Розвилка — опитування, не самодіяльність.** ≥2 життєздатних варіанти →
   таблиця «Опитування»: питання / варіанти / наслідок кожного / ★рекомендація /
   дефолт-при-мовчанні. Але питати — лише про **незворотне або те, що міняє
   контракт**. Дрібницю з очевидним дефолтом вирішуй сам і познач одним рядком:
   потік дрібних питань шкодить так само, як вигадки.
5. **Автоматизація замість повторення.** Ручна дія, зроблена двічі, стає
   скриптом, промптом у `docs/promts/` або пунктом чеклиста. Мануальні кроки
   yurii — ЛИШЕ у закріпленому issue «Черга yurii» (єдине джерело істини).
6. **Самовдосконалення важливіше за швидкість.** Фікс без регресійного тесту
   не зараховується. Помилка, що повторилась, — привід змінити процес
   (ADR/правило/гейт), а не «бути уважнішим наступного разу».
7. **Не дотискати.** STOP-тригер (червоний CI, зміна байтів снапшотів, потреба
   у забороненому шляху, суперечність з §7) → зупинка зі звітом. Обхідний шлях
   без згоди yurii гірший за незроблену роботу.
8. **Модель під задачу.** Ролі й маршрутизація — `docs/15` §0. Дорога модель
   на дешевій задачі — така сама помилка, як дешева на архітектурній.

**Гейти незмінні:** merge — yurii; обмеження §6 (міграції, залежності,
CLAUDE.md, infra) діють завжди, включно з автономними run'ами.

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

> §0 — як агент ВИКОНУЄ; §10 — як yurii ФОРМУЛЮЄ. Філософію переписувати
> у промпт не треба: достатньо рядка «Працюй за CLAUDE.md §0».

**Поганий промпт (junior typical):**

> "Зроби логін"

**Гарний промпт:**

> "Реалізуй email+password реєстрацію в `apps/api`. Використай Auth.js Credentials provider, Argon2id для хешу. Додай ендпоінти `POST /auth/register`, `POST /auth/login`, `POST /auth/logout`, `POST /auth/refresh`. Збережи юзера в `users` (вже в schema). Напиши Vitest для happy path і двох помилок (duplicate email, weak password). Оновити `docs/06_API_CONTRACT.md`."

Завжди вказуйте: **де** (apps/path), **що використати** (бібліотеки), **що повернути** (response shape), **які тести**, **який доку-файл оновити**.

## 11. Цикл розробки 2.0 (треки + ритми)

    1. Roadmap (`docs/02`) — п'ять треків-черг без дат (ADR-036). Беремо перший пункт черги відповідного треку.
    2. Одиниця роботи — run/PR за готовим промптом (`docs/promts/*`, `docs/15`); ролі й моделі — `docs/15` §0(Архітектор / Будівельник / Рев'юер /Розвідник).
    3. Гілка від свіжого `origin/main` (merge-base guard,`docs/16` §3 крок 0). TDD: тест → код → рефактор.
    4. Фінал run'у — draft PR: план у description + розділи «Опитування» і «Як перевірити очима». Мануальні кроки — ОБОВ'ЯЗКОВО у закріплений issue «Черга yurii» (джерело істини; PR-чеклист — дубль).
    5. Незалежне рев'ю AI-PR — Рев'юер (сильна Claude-модель, окрема сесія; Gemini — після перевірки доступу, ADR-036 §3).
    6. Merge — ЛИШЕ yurii (виняток — разова явна згода у конкретному run'і). Deploy — за `docs/08_DEPLOYMENT.md`.
    7. Ритми: неділя — digest ≤15 хв, кожен пункт → issue АБО «accepted noise» у digest-треді; 1-е число — huddle A4 (вхід: 4 digest + Roadmap; вихід: корекція черг треків).
    8. Закритий пункт черги = запис у `docs/13_PROGRESS_LOG.md` + ротація §13.

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
- AI bugfix flow (issue → тріаж → фікс → мультиагентне рев'ю): `docs/17_AI_BUGFIX_FLOW.md` (ADR-035)
- Open questions: `docs/00_OPEN_QUESTIONS.md` · відповіді: `docs/01_ANSWERED_QUESTIONS.md`
- Опитувальник з відповідями: `01_questionnaire_answers.md`

## 13. Поточний стан

> Повний журнал — `docs/13_PROGRESS_LOG.md`. Цей розділ — лише snapshot для контексту нових сесій. Тримайте його ≤ 2k chars.

**Де ми зараз (2026-08-04):** staging.hart.crimea.ua live, MVP feature-complete + **EN-версія (i18n Etap A, ADR-037)**: власні типізовані словники, `/en/*` дзеркала маркетингових поверхонь, hreflang/canonical + sitemap на 16 сторінок; студії лишаються UA — Etap B після Registry. **Master Run 8 — перший бойовий прогін мультиагентного конвеєра ADR-036**: agy (Gemini 3.1 Pro) як незалежний Рев'юер, метрика 2/2 підтверджених знахідок; 2 інциденти самовільного запису agy → правило git-status-після-виклику, курс на worktree-ізоляцію. Phase 3.4 (виробничий фідбек, R-01 mitigation 4) завершено. Телеметрія активна на staging з 2026-07-12 (Umami + Sentry + digest). Перфо-панель — ОДИН шаблон `perforated_panel` (ADR-031). Render-gate (ADR-026); DXF 2 шари (ADR-024); PDF з ізометрією (ADR-025). Discord IaC (ADR-023) чекає manual-setup. **ai-bugfix конвеєр (ADR-035) працює**: issue #84 пройшов увесь ланцюг тріаж→фікс→рев'ю→merge→staging без локальної сесії на код; трек T1 розблоковано. Наступний фокус — **Run 7 Етап 2** (лишились `z_bracket` — WIP-коміт `0dcc747` у `feat/migrate-z-bracket`, `wall_shelf`, `enclosed_shelf`) → публічний soft-launch.

**Останні 3 milestones:**

- **Master Run 10+11 — перший наскрізний прохід ai-bugfix конвеєра** (2026-08-03, ADR-035, трек T1): issue #84 (Telegram у футері) пройшов увесь ланцюг без локальної сесії на код — тріаж у CI (`30616535686`, перший `success` за історію) → `ai-approved` → Будівельник у CI (`30700893565`) → draft PR #97 → мультиагентне рев'ю (`agy` ✅, 6/7 кейсів прийнято) → merge `d4c81be` → staging. Ціна: **5 падінь тріажу, 4 спростовані гіпотези**; справжня причина — недійсне значення `CLAUDE_CODE_OAUTH_TOKEN` (`401 Invalid bearer token`), видиме лише після тимчасового `show_full_output` (PR #86, #94). Run 11 (PR #95) закрив дірку «зелений прогін без зміни стану issue» — крок `Verify issue reached a terminal state` + прибрано `show_full_output` з публічних логів. Run 12 (PR #98) — правдива черга T1: TD-01 закрито, `NODE_VERSION` 20→22/24 виділено окремим пунктом (Node 20 EOL 30.04.2026), TD-02 лишається наступним. Знахідка процесу: Будівельник у CI не має `node_modules`, тож «червоний до фікса» перевіряє рев'юер вручну (`ai-review-local.md` крок 2-bis).
- **Feature i18n Etap A — EN-версія платформи** (2026-07-18, ADR-037, Master Run 8): перший живий прогін конвеєра ADR-036 з `agy`/Gemini-Рев'юером. Власні типізовані словники (`apps/web/src/i18n/*`), middleware Accept-Language + функціональна `hart_locale` cookie (без PII, SameSite=Lax), `LocaleSwitcher` 44px, 6 нових `/en/*` сторінок; hreflang/canonical (`i18n/hreflang.ts`, x-default=uk) + `app/sitemap.ts` на всіх 16 локалізованих сторінках — follow-up за зауваженням agy. PR **#79** (3cbdc9e, Розвідник: 4 agy-скани, 0/32 розбіжностей), **#80** (0506f8a, ADR-037 + імплементація, e2e 138/138), **hreflang-follow-up** (bcd4552, +6 e2e). Вердикт конвеєра: 3✅/1⚠️; метрика agy-Рев'юера 2/2. Знахідки: `agy -p` не читає stdin (файлова передача); 2× самовільний запис agy → git-restore + правило «git status після кожного write-виклику agy». uk-URL/тексти незмінні; `/f/[exportId]` поза hreflang (noindex). Гілки `docs/i18n-inventory`, `feat/i18n-stage-a`, `fix/i18n-hreflang`.
- **Feature 3.4 — QR-фідбек з виробництва** (2026-07-17, ADR-032 §feedback, R-01 mitigation 4): замикає self-improvement loop — QR у PDF → мобільна форма `/f/{exportId}` → фідбек → digest бачить deviation-репорти → калібрування K-фактора. Два PR: **#69** (4a7d94d) — C4 UX-copy (Варіант 1 ★), таблиця `export_feedback` (FK на exports.id, drizzle-міграція за явною інструкцією), `POST /feedback/:exportId` (Zod, rate-limit 20/год/IP, 404 на невідомий export*id), подія `feedback_submitted` без PII (агрегати: outcome/has_deviation/has_comment/locale), digest-секція «Виробничий фідбек», UA+EN форма (мобільна-перша, 44px tap-target). **#75/issue #70** (34a2127) — QR раніше тримав непрацюючий fallback `flatcraft://<slug>/<article>`; тепер export_id (== job.id == exports.id) форвардиться api→cad-worker, `{BASE_URL}/f/{export_id}` підключено до всіх 6 `export*<tpl>\_pdf`. DXF без змін (ADR-024); PDF byte-снапшотів у репо нема — regen не знадобився. Тести: worker 339 pytest, api 67 unit, types 146, web 67 unit + 3 нові Playwright e2e. Гілки `feat/phase-3-4-qr-feedback`, `fix/issue-70`.
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

_Останнє оновлення: 2026-08-04. Коли архітектура змінюється — оновлюйте CLAUDE.md (§0-12) першим. Завершення фази — у `docs/13_PROGRESS_LOG.md` + ротація §13._
