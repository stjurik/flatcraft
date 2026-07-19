# 03. Architecture Decision Records (ADR)

> Кожне нетривіальне технічне рішення фіксуємо тут. Коротко: контекст → рішення → наслідки → альтернативи. Якщо рішення скасовано — статус `Superseded by ADR-N`.

## Індекс

> Підтримується кожним новим ADR (додати рядок при створенні). Джерело дат — заголовок `**Статус:**` у самому записі; де його нема — позначено «дата не зафіксована» (не вигадувати).

| №       | Назва                                                                              | Статус                                                          | Дата                |
| ------- | ---------------------------------------------------------------------------------- | --------------------------------------------------------------- | ------------------- |
| ADR-001 | Монорепо на pnpm + Turborepo                                                       | Accepted                                                        | 2026-05-08          |
| ADR-002 | Two-language CAD pipeline (TS + Python)                                            | Accepted                                                        | 2026-05-08          |
| ADR-003 | Drizzle ORM, не Prisma                                                             | Accepted                                                        | 2026-05-08          |
| ADR-004 | BullMQ для черги CAD-задач                                                         | Accepted                                                        | 2026-05-08          |
| ADR-005 | Single VPS на DigitalOcean для MVP                                                 | Superseded by ADR-011                                           | 2026-05-08          |
| ADR-006 | GDPR-by-design з першого дня                                                       | Accepted                                                        | 2026-05-08          |
| ADR-007 | Auth.js (NextAuth) для автентифікації                                              | Accepted                                                        | 2026-05-08          |
| ADR-008 | Cloudflare R2 для long-term storage                                                | Accepted                                                        | 2026-05-08          |
| ADR-009 | TDD з першого дня, цільове покриття 80%                                            | Accepted                                                        | 2026-05-08          |
| ADR-010 | Логування — pino з redact, без structured stack у консоль                          | Accepted                                                        | 2026-05-08          |
| ADR-011 | Mirohost Cloud замість DigitalOcean                                                | Accepted (supersedes ADR-005)                                   | 2026-05-14          |
| ADR-012 | UUID v4 у схемі, v7 — окремою міграцією після Postgres 18                          | Accepted                                                        | 2026-05-16          |
| ADR-013 | Browser-side preview через three.js Shape, OpenCascade.js відкладено               | Accepted                                                        | 2026-05-17          |
| ADR-014 | Caddy + Cloudflare Origin Certificate замість Let's Encrypt                        | Accepted                                                        | 2026-05-22          |
| ADR-015 | Drizzle міграції + seed у entrypoint api-контейнера                                | Accepted                                                        | 2026-05-28          |
| ADR-016 | Visual design system — warm industrial, single light theme, mobile-first           | Accepted                                                        | 2026-05-30          |
| ADR-017 | Group metadata у Zod через `.describe("group:G\|label:L")`                         | Accepted                                                        | 2026-05-30          |
| ADR-018 | `material_code` доставляється до API, але обрізається перед cad-worker'ом          | Accepted                                                        | 2026-05-30          |
| ADR-019 | Server-side validation як інваріант export-pipeline                                | Accepted                                                        | дата не зафіксована |
| ADR-020 | Soft-launch без auth/donations (Phase 3+4 → v1.1 conditional)                      | Accepted                                                        | 2026-06-04          |
| ADR-021 | Drawing polish — auto-layout corner picker + єдина конвенція осей + UA-одиниці BOM | Accepted                                                        | 2026-06-05          |
| ADR-022 | Клієнтська валідація матриці гибу через bake'ed snapshot                           | Accepted                                                        | 2026-06-08          |
| ADR-023 | Discord як infrastructure-as-code — декларативний TS-config + idempotent reconcile | Accepted                                                        | 2026-06-11          |
| ADR-024 | Production-grade DXF — рівно 2 шари + color-coded cut paths                        | Accepted                                                        | 2026-06-15          |
| ADR-025 | Ізометрія у PDF через OCC hidden-line-removal (вектор, детермінований)             | Accepted                                                        | 2026-06-16          |
| ADR-026 | R3F render-gate + ErrorBoundary як defense-in-depth проти крашу на invalid params  | Accepted                                                        | 2026-06-16          |
| ADR-027 | Products як preset базового шаблону                                                | Accepted (відновлено housekeeping 2026-07-17, джерело — PR #28) | 2026-06-22          |
| ADR-028 | Валідація перфорації (pitch > розмір отвору) як окремий gate                       | Accepted                                                        | 2026-06-24          |
| ADR-029 | Клієнтський перемикач форми отвору над двома шаблонами (без злиття)                | Superseded by ADR-031                                           | 2026-06-26          |
| ADR-030 | Перфо-монтажна панель — ребриста (4 фланці + кутові отвори), не опційно            | Accepted (розширено ADR-031)                                    | 2026-06-25          |
| ADR-031 | Уніфікація перфо-панелі в ОДИН параметричний шаблон (форма отвору — параметр)      | Accepted (supersedes ADR-029, розширює ADR-030)                 | 2026-06-26          |
| ADR-032 | Observability & self-improvement loop                                              | Accepted                                                        | 2026-07-05          |
| ADR-033 | Template Registry contract — єдиний реєстр шаблонів + conformance-suite            | Proposed                                                        | 2026-07-13          |
| ADR-034 | Manufacturing process layer                                                        | Зарезервовано (run A3 не запущено, `docs/15` §A3)               | —                   |
| ADR-035 | AI bugfix flow v2 — issue → тріаж → фікс (Actions) → локальне мультиагентне рев'ю  | Accepted                                                        | 2026-07-19          |
| ADR-036 | Модель розробки 2.0 — треки, ритми, мультиагентний конвеєр                         | Accepted                                                        | 2026-07-18          |
| ADR-037 | i18n-архітектура — власні словники + `/en/*` routing (Etap A)                      | Accepted                                                        | 2026-07-20          |

---

## ADR-001: Монорепо на pnpm + Turborepo

**Статус:** Accepted (2026-05-08)

**Контекст:** Розробляємо одночасно frontend (Next.js), backend (Fastify), CAD-engine (TypeScript), CAD-worker (Python), спільні типи. Solo-розробник, junior-рівень. Треба мінімізувати context-switching і зберегти єдиний source-of-truth для типів.

**Рішення:** pnpm workspaces + Turborepo. Один `package.json` на корені, окремі для кожного workspace. Python (`workers/cad`) живе в тому ж репо, але з власним `pyproject.toml` і `uv` для залежностей.

**Наслідки:**

- ✅ Спільні типи (`packages/types`) перевикористовуються між web і api без публікації npm-пакета.
- ✅ Один `git push` оновлює і фронт, і бек атомарно.
- ✅ Turbo кешує `lint`/`build`/`test` між запусками (швидкий CI).
- ❌ Junior-розробник стикнеться з нюансами pnpm workspace (не страшно, бо `pnpm install` робить все автоматично).

**Альтернативи:** Lerna (застарілий), Nx (надмірно потужний, learning curve), полирепо (багато overhead для solo).

---

## ADR-002: Two-language CAD pipeline (TS + Python)

**Статус:** Accepted (2026-05-08)

**Контекст:** Потрібно одночасно (а) живий 3D-прев'ю в браузері з відкликом <200мс, (б) точна розгортка з K-фактором + експорт DXF/PDF/STEP. OpenCascade.js працює в браузері, але важкі операції повільні і нестабільні. CadQuery (Python wrapper над OpenCascade) — стабільний, добре документований, основний інструмент open-source CAD.

**Рішення:** OpenCascade.js на frontend (preview-mesh, миттєвий feedback) + Python CadQuery на сервері (фінальна геометрія, розгортка, експорт).

**Наслідки:**

- ✅ UX швидкий, server-side обчислення детерміновані і легко тестуються.
- ✅ Python-екосистема краще для CAD-обчислень.
- ❌ Два мови у проєкті — додатковий інструментарій (uv, pytest, mypy) поряд з pnpm/vitest.
- ❌ Junior-розробнику складніше переключатися; компенсуємо детальною документацією у `workers/cad/README.md`.

**Альтернативи:** OpenCascade.js end-to-end (повільно для важких операцій), Manifold (нова бібліотека, мало документації), власний solver (немає сенсу).

---

## ADR-003: Drizzle ORM, не Prisma

**Статус:** Accepted (2026-05-08)

**Контекст:** Потрібен ORM для PostgreSQL з типобезпекою, міграціями, JSON-полями. Альтернативи: Prisma, Drizzle, Kysely.

**Рішення:** Drizzle ORM.

**Наслідки:**

- ✅ Тонкий рантайм (не запускає окремий Node-процес як Prisma).
- ✅ SQL-first DSL, явна композиція запитів.
- ✅ Кращий контроль над JSONB і складними індексами (потрібно для зберігання `model_parameters` як JSON).
- ❌ Менша екосистема, ніж у Prisma; деякі фічі ще emerging.
- ✅ Junior-friendly: прямі SQL-вирази, легко налагоджувати в `psql`.

**Альтернативи:** Prisma (важкий рантайм, схема в окремому DSL), Kysely (тільки query-builder, немає міграцій з коробки).

---

## ADR-004: BullMQ для черги CAD-задач

**Статус:** Accepted (2026-05-08)

**Контекст:** Експорт DXF/PDF — секунди (1–5 c для простих виробів), але блокує API-thread. Потрібна черга, фронт має бачити прогрес.

**Рішення:** Redis + BullMQ. Fastify ставить job → Python-worker (через `bullmq-py`) виконує → пише результат у Postgres + R2 → фронт отримує SSE.

**Наслідки:**

- ✅ Простий setup, Redis вже потрібен для rate-limit і session cache.
- ✅ Retry-логіка з коробки.
- ❌ Python-клієнт BullMQ менш активний за TS — якщо буде неприємно, перейдемо на власний invariant через Redis Streams.

**Альтернативи:** RabbitMQ (overkill), AWS SQS (vendor lock-in, не self-hosted), власна черга через Postgres NOTIFY (simple але без retry).

---

## ADR-005: Single VPS на DigitalOcean для MVP

**Статус:** ~~Accepted (2026-05-08)~~ — **Superseded by ADR-011 (2026-05-14)**

> ⚠️ Це рішення скасовано. Замовник перейшов на Mirohost Cloud (український хостинг, дата-центр у Києві). Актуальне рішення — ADR-011. Текст нижче лишаємо для історії.

**Контекст:** 10 user/day, 100 drawings/day. Треба дешево, GDPR-compliant, легко-deploy. Замовник обрав DigitalOcean (не Hetzner).

**Рішення:** один droplet `s-2vcpu-4gb` (~$24/міс) у регіоні `fra1` (Frankfurt, EU GDPR). На ньому крутиться: docker-compose stack — Postgres + Redis + MinIO + web + api + cad-worker. R2 (Cloudflare) для long-term storage DXF/PDF/STEP. Cloudflare DNS + проксі для SSL.

**Наслідки:**

- ✅ Дешево, зрозуміло, відтворювано.
- ✅ Single-point-of-failure прийнятний для MVP (Privacy Policy має застереження «best-effort uptime, no SLA»).
- ❌ Якщо завантаження вирасте 10×, треба буде розбивати: Postgres → DO Managed DB; Worker → окремий droplet або Kubernetes.
- ❌ Backup-стратегія — щоденний `pg_dump` → R2 (см. Phase 5 у Roadmap).

**Альтернативи:** Hetzner (дешевше, але замовник проти), AWS (overkill для масштабу), Cloudflare Workers + D1 (cool, але D1 ще обмежений).

---

## ADR-006: GDPR-by-design з першого дня

**Статус:** Accepted (2026-05-08)

**Контекст:** Аудиторія включає ЄС. Без GDPR-compliance ризикуємо штраф навіть як хобі-проєкт.

**Рішення:**

- Збираємо мінімум PII: тільки email + опційно ім'я (для імені на креслі).
- IP-адреса використовується тільки для rate-limit, не зберігається довше 24 годин.
- Усі логи без PII (pino redact + sentry beforeSend).
- Cookie banner мінімальний (тільки function-essential cookies без consent, аналітика — лише після opt-in).
- DSR endpoints: `/account/export-data` (JSON dump) і `/account/delete` (soft-delete з 30-day grace period).
- Privacy Policy + ToS + Cookie Policy у `legal/`, UA + EN.

**Наслідки:**

- ✅ Можемо легально приймати ЄС-користувачів.
- ❌ Додаткова робота на Phase 5 (~3 дні).

**Альтернативи:** Geo-блокування ЄС (втрачаємо аудиторію), повний consent-management — overkill.

---

## ADR-007: Auth.js (NextAuth) для автентифікації

**Статус:** Accepted (2026-05-08)

**Контекст:** Email+password, Google OAuth. Сесії, JWT, refresh, CSRF.

**Рішення:** Auth.js v5 (поки бета, але стабільний для нашого scope) для Next.js, Fastify консумує JWT, який видає Auth.js.

**Наслідки:**

- ✅ Готова логіка OAuth, CSRF, JWT.
- ✅ Open-source, без vendor lock-in.
- ❌ Бета-версія — слідкуємо за breaking changes у release notes.

**Альтернативи:** Clerk (vendor lock-in, платний), власна реалізація (overkill для MVP), Supabase Auth (потягне ще одну залежність).

---

## ADR-008: Cloudflare R2 для long-term storage

**Статус:** Accepted (2026-05-08)

**Контекст:** Зберігаємо DXF/PDF/STEP/3D-thumbnails. У середньому 100 файлів/день × 4 формати × ~200 KB = ~80 MB/день. За рік ~30 GB.

**Рішення:** Cloudflare R2 (S3-compatible API). Локально в dev — MinIO у docker-compose.

**Наслідки:**

- ✅ Egress безкоштовний (велика економія).
- ✅ S3-compatible — переносимо на AWS S3 за 5 хвилин якщо потрібно.
- ✅ EU-юрисдикція (CF EU) — артефакти й бекапи фізично поза Україною, що дає resilience для київського ДЦ.
- ❌ Cloudflare акаунт обов'язковий (вже потрібен для DNS).
- ⚠️ **Після ADR-011 R2 — не «бажано», а обов'язково:** на сервері Mirohost Cloud MS21 лише 40 ГБ диска, локально тримати зростаючі DXF/PDF/STEP не можна. Self-hosted MinIO лишається тільки для dev.

**Альтернативи:** AWS S3 (egress дорогий), self-hosted MinIO у prod (на 40-ГБ диску не поміститься — відкинуто), Backblaze B2 (можлива заміна, якщо CF не влаштує).

---

## ADR-009: TDD з першого дня, цільове покриття 80%

**Статус:** Accepted (2026-05-08)

**Контекст:** CAD-обчислення — найгірший клас помилок: «непомітно неправильно», виробник зробить криве замовлення. Треба регресійні снепшоти.

**Рішення:**

- Кожна нова фіча → спочатку red test, потім green code, потім refactor.
- CAD-engine: snapshot-тести (фіксований seed → фіксований DXF byte-output).
- Cтек тестів: Vitest (TS), pytest (Python), Playwright (e2e), supertest (API integration).
- 80% line coverage — необхідна умова, але не достатня. Mutation testing (Stryker) на ключових модулях `cad-engine`, `validators`, `unfold`.

**Наслідки:**

- ✅ Безпечні рефакторинги.
- ✅ Документація через тести.
- ❌ Phase 1–2 повільніші на 30%; компенсується менше багами на Phase 5.

---

## ADR-010: Логування — pino з redact, без structured stack у консоль

**Статус:** Accepted (2026-05-08)

**Контекст:** Простий setup для одного сервера, треба збирати JSON-логи + redact PII.

**Рішення:**

- Pino у Fastify і CAD-worker (через `python-json-logger`).
- Redact: `req.headers.authorization`, `req.body.password`, `*.email` → `[REDACTED]`.
- У dev — pino-pretty.
- У prod — JSON-файли у `/var/log/flatcraft/`, ротація через `logrotate`.
- Sentry для exceptions (з `beforeSend` фільтром).

**Наслідки:** Доки масштабу немає — без ELK/Loki. Якщо потрібно буде, додамо в Phase 5.

---

## ADR-011: Mirohost Cloud замість DigitalOcean

**Статус:** Accepted (2026-05-14) — _supersedes ADR-005_

**Контекст:** ADR-005 фіксував один droplet на DigitalOcean (Frankfurt). Замовник вирішив перейти на **Mirohost** — найбільший український хостинг-провайдер — з міркувань: український бізнес, оплата у грн, підтримка українською, дата-центр у Києві. Конкретний тариф обрано після перевірки лінійки продуктів Mirohost (shared-хостинг непридатний — лише PHP/MySQL без Docker і root; eVPS не дає явного root; Cloud — дає).

**Рішення:** **Mirohost Cloud, тариф MS21 — 2 vCPU / 4 GB RAM / 40 GB SSD**, дата-центр Київ («EU-IEV-1»). Продукт Cloud надає root-доступ → ставимо Docker самостійно. На сервері — той самий docker-compose stack, що планувався: Postgres + Redis + web + api + cad-worker.

Похідні рішення, що випливають із характеристик MS21:

1. **Артефакти (DXF/PDF/STEP/thumbnails) і бекапи → Cloudflare R2, обов'язково.** 40 ГБ диска не вмістить зростаючі файли (~80 МБ/день, ~30 ГБ/рік). Self-hosted MinIO лишається тільки для dev. Це посилює ADR-008.
2. **CAD-worker concurrency = 1** (макс. 2) і обов'язковий swap — 4 ГБ RAM на весь стек із CadQuery/OpenCascade тіснувато.
3. **Без Terraform.** Mirohost не має Terraform-провайдера. Інфраструктуру (сервер) створює замовник вручну в панелі Mirohost; усе налаштування (Docker, docker-compose, .env, systemd, backups, firewall) — через **Ansible** на вже наявному сервері. Каталог `infra/terraform/` з репо прибираємо.
4. **Cloudflare лишається попереду** як DNS + проксі + SSL + WAF (геоблок RU/BY). З українським origin-сервером це навіть цінніше: ховає реальний IP, додає DDoS-захист.

**Наслідки:**

- ✅ Український провайдер, оплата у грн, підтримка українською — узгоджено з соціальним характером проєкту.
- ✅ Root + Docker → архітектура (ADR-001..004) не змінюється, лише цільова машина.
- ✅ Cloudflare R2 для бекапів поза Україною = resilience, якщо київський ДЦ постраждає.
- ⚠️ **GDPR: дані фізично в Україні.** Україна поки не має повного adequacy decision від ЄС → формально «третя країна». Не блокер, але вимагає: (а) формулювання у Privacy Policy про розташування даних і використання Standard Contractual Clauses; (б) явної згоди користувача. Див. ADR-006 і `docs/04_RISKS.md` (R-04, R-05).
- ⚠️ 4 ГБ RAM — робочий мінімум. Перший крок масштабування — апгрейд тарифу Cloud по RAM.
- ⚠️ 40 ГБ диск — треба моніторинг disk usage з алертом; усе «важке» виносимо в R2.
- ❌ Немає Terraform-відтворюваності інфри — компенсуємо Ansible-плейбуком + документованою інструкцією створення сервера.

**Альтернативи:**

- DigitalOcean (ADR-005) — скасовано рішенням замовника.
- Mirohost shared-хостинг (тарифи Міні/Сайт/Портал) — **непридатний**: лише PHP/MySQL, без Docker, без root, без PostgreSQL/Redis/Node/Python.
- Mirohost eVPS — дешевше за Cloud, але сторінка продукту не гарантує root + Docker; ризиковано.
- Hetzner — дешевший і в ЄС-юрисдикції, але замовник свідомо обрав українського провайдера.

---

## ADR-012: UUID v4 у схемі, v7 — окремою міграцією після Postgres 18

**Статус:** Accepted (2026-05-16)

**Контекст:** `docs/05_DATA_MODEL.md` §1 декларує `uuid v7` як id-тип для всіх таблиць (sortable + unique, краще для btree-індексів на `(user_id, created_at)`). Реалізація з drizzle 0.36 / Postgres 16-alpine: нативного `gen_uuid_v7()` нема до Postgres 18; pg-uuidv7 extension не входить у офіційний образ і вимагає окремої збірки.

**Рішення:** Phase 0.3 використовує `gen_random_uuid()` (uuid v4) як default для всіх PK. Перехід на v7 — окрема міграція коли (а) Mirohost дасть Postgres 18, або (б) додамо `uuid-ossp`/`pg-uuidv7` extension у image. Зміна default не ламає existing рядки — старі v4-id залишаться валідні uuid-и.

**Наслідки:**

- ✅ Phase 0.3 не блокується відсутністю v7 generator.
- ✅ Зміна на v7 — це лише `ALTER TABLE … ALTER COLUMN id SET DEFAULT uuid_v7()`, без backfill.
- ⚠️ Втрачаємо timestamp-sortability id-шників (нерелевантно для MVP — індекси на `created_at` і так є).
- ❌ ER-діаграма у doc/05 говорить «uuid v7» — формально невідповідність; виправимо після переходу.

**Альтернативи:**

- pg-uuidv7 extension зараз: окрема збірка image, ризик блокування на Mirohost.
- JS-generator uuid v7 у застосунку (через `uuid` npm): додаткова залежність, не використовує DB-default → треба ставити id вручну при insert у кожному місці.
- Чекати Postgres 18 у LTS: фіксує MVP на 2026Q4, неприпустимо.

---

## ADR-013: Browser-side preview через three.js Shape, OpenCascade.js відкладено

**Статус:** Accepted (2026-05-17)

**Контекст:** ADR-002 і roadmap Phase 2.6 закладали OpenCascade.js на frontend для preview-mesh. Реальне впровадження зіткнулось з:

- Bundle ~20 MB WASM (важко для FCP, потребує async loader + UI fallback).
- API OpenCascade.js (beta) — TopoDS_Shape → mesh потребує okt-bridge коду + buffer-marshalling.
- MVP-шаблони (L-bracket Phase 2; Z, кутник, полиця, перфо-панель Phase 2.10) геометрично прості — extrude 2D-профілю достатньо.
- Phase 1 уже дає точну геометрію через server-side CadQuery (workers/cad) — це авторитетне джерело для DXF/STEP. Browser preview — для UX feedback, не для виробничих файлів.

**Рішення:** Phase 2.6 — використовуємо `three.js Shape + ExtrudeGeometry` для browser preview (`packages/ui/src/3d-viewport/`). Шару параметрів додаємо `useDebouncedValue(100мс)` для уникнення re-build mesh на кожен keystroke (CLAUDE.md §9 поріг). OpenCascade.js — відкладено до фази, коли реально знадобиться:

- Boolean-операції (вирізи з користувацькими отворами поза template-grid).
- Імпорт STEP/STL для custom-моделей.
- Точна validation колізій у браузері (зараз — CadQuery server-side через export-черги).

**Наслідки:**

- ✅ Phase 2 закривається без heavy WASM. FCP лишається <1.5c (CLAUDE.md §9).
- ✅ `@flatcraft/cad-engine` peerDep `opencascade.js` залишається опційним — bridge-файл додамо коли підемо у post-MVP.
- ✅ Pure `buildLBracketShapeCommands` (packages/ui) тестується без WebGL/WASM.
- ⚠️ AGENTS.md і docs/03 (ADR-002) згадують OpenCascade.js як архітектурну частину — апдейтнуто посиланням на цей ADR.
- ❌ Якщо знадобиться precise validation у браузері до Phase 4 — повертаємось і вкладаємось в OpenCascade.js bridge. Імовірність: низька (server-side флоу через CadQuery уже покриває).

**Альтернативи:**

- Опускати OpenCascade.js повністю — ризик, якщо коли-небудь захочемо STEP-imports. Відкидаємо: peerDep лишаємо.
- Build OpenCascade.js bridge у Phase 2.6 одразу — overengineering без use-case.
- Replicad / Manifold — інші open-source CAD-libs; той же розмір/складність WASM. Не виграш.

---

## ADR-014: Caddy + Cloudflare Origin Certificate замість Let's Encrypt

**Статус:** Accepted (2026-05-22)

**Контекст:** Phase 5A потребує reverse-proxy + TLS термінацію на staging.hart.crimea.ua перед api/web контейнерами. Cloudflare уже стоїть як proxy (DNS + WAF + DDoS, ADR-011), отже handshake клієнт↔CF робить сам CF. Залишається TLS на segment CF↔origin (Mirohost server).

Варіанти TLS на origin:

1. **Let's Encrypt через ACME** — традиційний путь. Caddy має `auto_https` з вбудованим ACME клієнтом. Потребує: (а) port 80 відкритим world-wide (HTTP-01) АБО (б) DNS-01 challenge через DNS provider API plugin. У нас port 80 закритий від усього крім CF IP-ranges (UFW), тож HTTP-01 не пройде. DNS-01 — додавати CF DNS plugin у Caddy build (custom image або xcaddy). Renew кожні 60 днів + автоматизація.

2. **Cloudflare Origin Certificate** — CF випускає cert на 15 років, підписаний CF Origin CA. CF приймає його при `Full (strict)` mode (на edge-↔origin segment). НЕ valid'ний для прямого підключення з браузера (бо browser не довіряє CF Origin CA), що влаштовує — пряме підключення в обхід CF ми навмисно блокуємо UFW'ом.

**Рішення:** Cloudflare Origin Certificate + Caddy з `auto_https off`. Cert + key монтуються у `/etc/caddy/cf-origin/` (Ansible flatcraft role з vault). Caddy має 2 директиви `tls /path/to/cert.pem /path/to/key.pem` (одна для `staging.hart.crimea.ua`, одна для `api-staging.hart.crimea.ua`).

**Наслідки:**

- ✅ Жодних ACME плагінів, build-time complexity, DNS-API tokens у production.
- ✅ Cert живе 15 років — renew-логіка не існує. У worst case ротація — одна команда (ADR-014 не міняється).
- ✅ Port 80 НЕ потрібен від world; UFW allow тільки 80/443 від CF IPs.
- ✅ Caddyfile тривіальний (40 рядків з security headers), без auto_https complexity.
- ⚠ Залежимо від Cloudflare (lock-in на TLS termination). Якщо CF колись зникне → треба швидко перейти на LE з DNS-01. Mitigation: cert chain зберігається у vault'і; перехід — додати ACME-блок у Caddyfile + `auto_https on`.
- ⚠ Direct connection до origin IP (в обхід CF) видасть CF Origin Cert, який браузер не довіряє — користувачі побачать "Not trusted" попередження. Це фіча, не баг: ми навмисно ховаємо origin IP (DNS proxied + UFW from CF only).
- ❌ Якщо випадково розкриєш origin IP — публічно про це сигналізує (browser warning ≈ "ваш сайт відкрито в обхід CF"). У staging — це швидко помітно, у production — ніч страшна.

**Альтернативи:**

- Let's Encrypt HTTP-01 — потребує port 80 worldwide → губимо UFW-захист origin'у. Відкидаємо.
- Let's Encrypt DNS-01 з CF API plugin — custom Caddy build з xcaddy АБО окремий cert-bot контейнер. Складніше, ще один token у vault, renew logic. Прийнятно, але overengineering для одного staging.
- nginx + certbot — як попереднє, ще й окремий сервіс. Caddy одним конфігом вирішує те саме.
- HAProxy + manual cert — досвід вимагає більше; для одного origin'у не виправдано.

---

## ADR-015: Drizzle міграції + seed у entrypoint api-контейнера

**Статус:** Accepted (2026-05-28)

**Контекст:** Prod-стек (`docker-compose.prod.yml`) піднімав api з порожньою БД — deploy-флоу (Ansible `--tags deploy`) ніколи не застосовував міграції чи seed, тож `GET /templates` падав `500 relation "templates" does not exist`. Треба детерміновано довести БД до актуальної схеми + довідкових даних при кожному деплої, без ручних кроків на сервері. Обмеження: prod api-образ — slim standalone (`pnpm deploy --prod`), без `drizzle-kit`/`tsx`; `@flatcraft/db` лінкується симлінком у `.pnpm`.

**Рішення:** `api-entrypoint.sh` запускає `node node_modules/@flatcraft/db/dist/init-prod.js` (явний виклик `runMigrations()` + `runSeed()`) перед `exec node dist/server.js`. Два супутні фікси: (1) `@flatcraft/db` build копіює `src/migrations/*.sql` у `dist` (tsc їх не бере); (2) `init-prod.ts` викликає експортовані функції напряму, бо `isMain`-перевірка (`import.meta.url === file://${argv[1]}`) під симлінком `pnpm deploy` мовчки = false.

**Наслідки:**

- ✅ Self-healing: будь-який deploy (CI чи ручний) сам приводить БД у потрібний стан; нуль ручних кроків.
- ✅ Seed ідемпотентний (`onConflictDoNothing` / `onConflictDoUpdate`) — безпечно на кожен boot; помилка migrate/seed → `set -e` → контейнер падає (healthcheck не пройде) = fail loud, а не напівпорожня БД.
- ⚠ Seed біжить на кожен рестарт api — для статичних довідників (матеріали/шаблони) ок; якщо колись seed стане важким, винести у окремий one-shot job (`service_completed_successfully`).
- ⚠ При кількох репліках api майбутній distributed-сценарій потребує advisory-lock на міграції (зараз 1 репліка — не проблема).

**Альтернативи:**

- Окремий one-shot `migrate`-сервіс у compose (`depends_on: service_completed_successfully`) — чистіше розділення, але більше чіпає compose; обрали entrypoint за мінімальну зміну і відповідність наміру в `migrate.ts`.
- Ручний `psql < .sql` + `seed.js` на сервері — не відтворювано, поза git-флоу. Відкинуто.

---

## ADR-016: Visual design system — warm industrial, single light theme, mobile-first

**Статус:** Accepted (2026-05-30)

**Контекст:** Phase 2 закрила 5 шаблонів end-to-end (`templates` + `studio`), але UI лишався на дефолтних Tailwind-класах (`bg-zinc-950 text-zinc-100`, `bg-emerald-700`) без власних токенів, шрифтів і брендингу. Перед Phase 3 (Auth & Limits) і подальшою адаптацією екранів потрібна **єдина дизайн-мова**: палітра, типографіка, motion, breakpoint-стратегія. Цільова аудиторія — DIY-люди у майстерні/гаражі, які часто заходять з телефону → mobile-first не «бонус», а інваріант (це переписує R-02 у `docs/04_RISKS.md`).

**Рішення:**

1. **Палітра** — **warm industrial**, OKLCH-токени у `apps/web/src/app/globals.css`:
   - bg: off-white з теплим відтінком (`oklch(0.985 0.005 80)`) — «креслярський папір», не чисто-білий.
   - fg: warm-charcoal (`oklch(0.22 0.015 50)`) — теплий, не чорний.
   - primary: ember/амбра (`oklch(0.66 0.17 50)`) — асоціація з розпеченим металом.
   - Окремо: surface-sunken/muted, accent (стримане синьо-сіре для secondary CTA), feedback (success/warning/danger/info × DEFAULT/foreground/surface), border/ring, UA-flag і ЗСУ-button (як hex, бо точність державних кольорів важлива).
2. **Тема — тільки світла.** Без `.dark`, без перемикача. Цільовий контекст — майстерня зі змішаним освітленням, де light-on-bg працює стабільніше.
3. **Типографіка** — Inter (sans + display через `tracking-tight`) + JetBrains Mono (code). Self-hosted через `next/font/google`, subset latin+cyrillic — без runtime-CDN, без CLS.
4. **Mobile-first** — у `tailwind.config.ts` додано `xs: 360px` як baseline, дефолтні утиліти = small viewport, breakpoints `sm/md/lg/xl` розширюють. Tap target `--tap-target-min: 44px` (WCAG 2.5.5 Enhanced) застосовано до всіх інтерактивів через `<Button>` primitive.
5. **Бренд** — wordmark `<Logo>` («hart» semibold + «.crimea.ua» 60% opacity, без іконки). 2px `<UkraineStripe>` над футером. `<Button variant="zsu">` лише для donate-CTA у `<Footer>`.
6. **OKLCH у Tailwind 3.4** — формат токенів `L C H` (без обгортки) + helper `oklch(var(--token) / <alpha-value>)` у config. Перцептуально-рівномірний колір-простір дає **однаковий візуальний відскок** на hover для будь-якого відтінку.
7. **/styleguide** — внутрішня сторінка (`apps/web/src/app/(dev)/styleguide/`), доступна лише з `NEXT_PUBLIC_ENV=dev` (інакше `notFound()`). 12 секцій + контраст-таблиця з обчисленим `contrastRatio()` для кожного токена. На production-build стає 404.
8. **prefers-reduced-motion** — глобальний `@media` reset у `globals.css` знімає декоративні анімації; це default, не opt-in.

**Тригери перегляду:**

- Замовний бренд-логотип / повний візуальний ребрендинг.
- Аналітика з реальних користувачів показує, що desktop важливіший за mobile (тоді переоцінюємо breakpoints і density).
- Скарги на читання у темній обстановці (тоді відкриваємо dark mode як другу тему).

**Наслідки:**

- ✅ Єдиний фундамент для Phase 2.12+ (адаптація реальних екранів) і Phase 3 (Auth pages).
- ✅ Контраст і tap-target перевіряються інваріантно у Playwright — регресії помічаються одразу.
- ✅ `@flatcraft/ui` отримав `primitives/` (Button + Dialog re-export) і `components/` (Logo, UkraineStripe, Footer) — підготовка до Phase 2.15.
- ✅ ADR-016 + `docs/10_DESIGN_SYSTEM.md` — повний документ, новий контриб'ютор підіймається за 30 хв.
- ⚠ Існуючі екрани (`/`, `/templates`, `/templates/[slug]`) **тимчасово візуально неконсистентні** — досі використовують `zinc-950 emerald-700`. Свідомий PR-scope; адаптація — Phase 2.12+ окремими PR'ами.
- ⚠ OKLCH рендериться у всіх сучасних браузерах (Safari 15.4+, Chrome 111+, Firefox 113+). У старіших — fallback до системних кольорів (зрозуміла деградація, не критична).
- ❌ Жодного dark mode до тригера перегляду.

**Альтернативи:**

- **shadcn/ui дефолтні токени** — холодний сіро-синій zinc, не warm. Не передає industrial-характер.
- **Dark mode як default** — частина DIY-аудиторії працює у яскравій майстерні; light-on-bg універсальніший.
- **HSL замість OKLCH** — повсюди підтримується, але hover-shifts стають нерівномірними між відтінками (червоний темнішає сильніше, ніж жовтий при тому ж `−10% L`). OKLCH дає стабільнішу візуальну метрику.
- **CSS-in-JS (Stitches, Vanilla Extract)** — overkill для статичної токен-системи; додає bundle і build-step.
- **Окремий Storybook** — ще один тулчейн і CI-job; `/styleguide` всередині app робить те саме без витрат.

---

## ADR-017: Group metadata у Zod через `.describe("group:G|label:L")`

**Статус:** Accepted (2026-05-30)

**Контекст:** Phase 2.12 потребує згрупованих секцій у редакторі (Полиця A, Полиця B, Гиб, Отвори тощо) замість плоского grid'а. AutoForm (Phase 2.4) — generic, інтроспектує `ZodObject.shape` у плоский список `FieldDescriptor`. Треба домен-знання (яке поле в яку секцію) донести з пакета `@flatcraft/types` (де живуть схеми) до пакета `@flatcraft/ui` (де живе AutoForm), **не вводячи новий канал** і не дублюючи map на стороні UI.

Розглянуті механізми:

1. Окремий map у кожному `XEditor.tsx` (`groups: { legA_mm: "Полиця A", ... }`) — дублювання, легко розсинхронізувати з полями схеми.
2. Розширити Zod-схему власною обгорткою (`groupedNumber(20, 500, "Полиця A")`) — нова DSL, ламає сумісність з generic `safeParse`.
3. `.describe(text)` — нативний Zod API, зберігає метадані у `_def.description` і не впливає на валідацію. Парсимо як `key:value|key:value` (простий і недо-розширюваний формат).

**Рішення:** `.describe("group:<Назва секції>|label:<Лейбл>")` на полях. `schema-inspector` парсить description через pure-helper `parseDescription` і кладе у `FieldDescriptor.group` / `.label`. AutoForm рендерить групи як `<fieldset><legend>...</legend>`, незгруповані поля потрапляють у дефолтну секцію «Загальне» внизу. Як fallback (для legacy / зовнішніх схем) залишаємо два props на AutoForm: `groups?: Record<name, string>` і `labels?: Record<name, string>`.

**Тригер перегляду:** якщо групувань стане >3 рівнів вкладеності або потрібні умовні групи (наприклад, «приховати секцію X, якщо Y=0») — переходимо на JSON-schema annotations через `superRefine` або власну окрему `FieldRegistry` поза Zod. Phase 2.12 цього не потребує.

**Наслідки:**

- ✅ Метадані живуть **поряд з валідацією** — змінив `legA_mm` → одразу видно і обмеження, і групу/лейбл.
- ✅ `parseDescription` — pure helper з 3 unit-тестами; інтегрується у `introspectSchema` без зміни сигнатури `AutoFormProps`.
- ✅ Зворотна сумісність: схеми без `.describe()` рендеряться як раніше (поля → «Загальне»).
- ⚠ Формат key:value — це наш стрінговий «протокол». Якщо забути крапку чи лапку — поле тихо опиниться у «Загальне». Перевірка — тест на parseDescription + e2e на наявність очікуваних legends.
- ⚠ `_def.description` офіційно публічне API Zod 3.x; у Zod 4.x signature може помінятись — мігруємо разом з апгрейдом.
- ❌ i18n: один опис = одна мова (українська). Для en-локалі — або другий describe-namespace, або вертатись до зовнішнього map (Phase post-MVP).

**Альтернативи:**

- `JSON-schema annotations`: важче, generic, але вимагає side-table maintenance.
- Окремий `meta` ZodObject поряд із Schema: дублювання списку полів.
- `superRefine` + symbol-keyed metadata: тонко, але невидимо у devtools і не серіалізується у zod-to-openapi (важливо post-MVP).

---

## ADR-018: `material_code` доставляється до API, але обрізається перед cad-worker'ом

**Статус:** Accepted (2026-05-30)

**Контекст:** Phase 2.12 додає селектор матеріалу до студії — користувач обирає матеріал перед експортом, і це значення має потрапити у потенційний `drafts`-store, історію експортів, ліміти за матеріалами тощо (Phase 3+). Поточний flow Phase 2.7–2.10: `web → POST /exports → cad-worker /export → DXF/PDF`, БЕЗ persistence draft'а. Python `ExportRequest` має `ConfigDict(extra="forbid")` — будь-яке нове поле = 400.

Два сторони контракту:

1. **Web ↔ API:** має бути повний payload з `material_code` — щоб API міг логувати, а пізніше зберігати у `model_drafts`/`usage_quota` (Phase 3+).
2. **API ↔ cad-worker:** cad-worker малює геометрію, матеріал НЕ впливає на DXF (k-фактор та layer-структуру міняє тільки товщина; матеріал відображається лише у PDF header — Phase 2.9, але це поле не передається у поточному імплементі). Тож material_code тут лишній шум.

**Рішення:**

1. `ExportRequestSchema` (`packages/types/src/domain/export.ts`): додати **обов'язкове** `material_code: z.string().min(1)` до всіх 5 варіантів discriminatedUnion.
2. `apps/api/src/routes/exports.ts:runJob`: destructure-нути `{ material_code: _materialCode, ...cadBody }` і форвардити cad-worker'у тільки `cadBody`. Pino-лог фіксує `material_code` (без PII-конфлікту — це довідник).
3. Python cad-worker і його Pydantic `ExportRequest` лишаються незмінними (`extra="forbid"` зберігається).

**Тригер перегляду:** коли з'явиться `drafts`-persistence (Phase 3+ — POST /v1/drafts створює запис, експорт стартує з draft_id) — material_code природньо переїде у `model_drafts`-таблицю, а ExportRequest до cad-worker'а може отримати materials.density для розрахунку маси у PDF (Phase 2.9 BOM). Тоді ADR-018 superseded.

**Наслідки:**

- ✅ Один цикл деплою: web-форма вже шле material_code; як тільки drafts з'являться, бекенд починає його зберігати без зміни клієнта.
- ✅ Python untouched — нульовий ризик регресій у CAD-pipeline.
- ✅ E2E може робити assert на тіло POST /exports (не лише на UI state).
- ⚠ Поле здається «магічно зникаючим» між web і cad-worker. Документую коментарем у `runJob` і у `exports.ts`.
- ⚠ Pino-лог пише `material_code` — не PII, але треба переконатись, що не у redact-list (за дефолтом не пише).
- ❌ Невелика дисимметрія API/CAD-схем. Поки що економічно виправдано: уникаємо роботи у Python без use-case.

**Альтернативи:**

- **A. Pydantic `extra="allow"` або явне `material_code: str = ""`** — змушує мене лізти у workers/cad без причини; цей пакет — окремий пайплайн (uv/mypy/pytest), додатковий обхід CI.
- **C. Не додавати у ExportRequest, а тримати лише у studio state** — e2e тоді перевіряє лише UI state, не request body; цінність тесту падає, а коли почнемо drafts — все одно треба буде розширити схему.

---

## ADR-019: Server-side validation як інваріант export-pipeline

**Контекст:** Hotfix 2.10.e. Клієнтська валідація (`cad-engine validateBend` у браузері) — це **лише UX**: підсвічення невалідних полів у редакторі. Вона тривіально обходиться (вимкнений JS, прямий `curl` до API, майбутній BullMQ-producer). До фіксу серверний шлях експорту НЕ викликав жодного matrix-валідатора: Fastify `POST /exports` перевіряв тільки Zod-shape і форвардив у cad-worker; Python перевіряв радіус проти глобального набору, не проти thickness-матриці. Результат — R-12: Z-bracket t=5/R=2.5 експортувався попри заборону матриці.

**Рішення:** Валідація гиба проти `bend-machine-esi.yaml` стає **обов'язковим серверним інваріантом на двох рівнях**:

1. **Fastify gate** (`apps/api/src/lib/validate-export.ts`, `validateExportBends`) — викликає той самий cad-engine `validateBend` ПЕРЕД створенням job / forward у воркер. Помилки → `422` RFC 9457 з `errors[].code` (`RADIUS_NOT_ALLOWED` тощо). Жоден артефакт не створюється, quota не витрачається.
2. **Python parity** (`workers/cad/flatcraft_cad/validate/bend.py`) — читає той самий YAML і відмовляє на старті `/export`-handler ДО будь-якої CAD-операції. Остання лінія оборони (defense-in-depth), якщо API-gate обійдено.

Паритет TS+Python гарантується property-based тестами (fast-check + hypothesis, 1000 ітерацій, спільний oracle, один YAML).

**Тригер перегляду:** коли експорт стане BullMQ-distributed (Phase 5+) — основна валідація має жити **в API** (fail-fast перед чергою), а не лише у воркері, інакше invalid-jobs їдять quota і ресурси worker'а. Python-валідатор лишається як safety-net.

**Наслідки:**

- ✅ Інваріант безпеки відновлено: неможливі деталі не можна експортувати через будь-який серверний шлях.
- ✅ `apps/api` тепер залежить від `@flatcraft/cad-engine` (workspace) — спільне джерело істини TS-валідації.
- ✅ Помилки у форматі RFC 9457 (`docs/06 §0`) — клієнт може показати конкретне поле/код.
- ⚠ Подвійна валідація (API + worker) — навмисна (defense-in-depth), не дублювання-помилка.
- ⚠ Python воркер не має `material_code` (ADR-018 strip) — material-group перевірка лишається в API-gate; воркер валідує матеріало-незалежні radius/thickness/angle.

**Альтернативи:**

- **Тільки клієнт** — статус-кво, що й спричинив P0-баг. Відхилено.
- **Тільки worker** — воркер не має контексту quota і стартує важку CAD-операцію перш ніж відмовити; бажано fail-fast в API. Worker лишається додатковою лінією, не єдиною.

---

## ADR-020: Soft-launch без auth/donations (Phase 3+4 → v1.1 conditional)

**Статус:** Accepted (2026-06-04)

**Контекст:** Phase 3 (Auth) і Phase 4 (Donations) — це ~3 тижні роботи на автентифікацію (Auth.js, JWT, OAuth, quota) і монетизацію (donation-claims, unlock-flow). Product-market fit ще не валідовано: жоден реальний користувач не пройшов повний цикл. Будувати персоналізацію й anti-abuse-інфраструктуру перед першим зовнішнім фідбеком — це інвестиція наосліп.

**Рішення:** Пропускаємо Phase 3 і Phase 4 у MVP-релізі. Замість них — **Phase X.1 (1–2 дні)**, що готує продукт до публічного soft-launch'у без auth:

1. **IP-based rate-limit** на `POST /exports` — 30/год/IP + burst-ban (50). Захист від abuse, толерантний до NAT. Плагін `global: false` (точково, лише browser-direct маршрути): глобальний per-IP ліміт несумісний із SSR (web робить server-side fetch до API з однієї IP контейнера → throttl'ив би усіх). Глобальний flood-захист — на Cloudflare WAF.
2. **PDF watermark «BETA»** — footer кожної сторінки, знижує репутаційний ризик ранніх геометричних помилок.
3. **Post-export ЗСУ-CTA** — ненав'язливе нагадування про підтримку ЗСУ у success-стані експорту (без блокування).
4. **Справжня `/about`** — оголошення моделі: BETA, безкоштовно для всіх, донати на ЗСУ — почесна система.

Модель: «безкоштовно для всіх, донати на ЗСУ — почесна система, без блокування експорту».

**Наслідки:**

- ✅ Швидший public launch (днів замість тижнів).
- ✅ Сильніший меседж «безкоштовно для всіх» — без paywall, без реєстрації.
- ✗ Нема персоналізації (нема «моїх чернеток»; drafts поки не зберігаються).
- ✗ Нема quota → потенційний abuse. Mitigation: IP rate-limit (цей ADR) + Cloudflare WAF (country block + CF rate-limit як другий рубіж, керується у dashboard).
- ⚠ Endpoints `/v1/auth/*`, `/v1/account/*`, `/v1/donations/*`, `/v1/admin/*` і таблиці `users`/`oauth_accounts`/`sessions`/`donation_claims`/`usage_quota` лишаються у `docs/06_API_CONTRACT.md` / `docs/05_DATA_MODEL.md` як `v1.1+ planned` — не реалізовані, але спроєктовані.

**Тригери перегляду (активують Phase 3/4 з v1.1):**

- **>5 ботів/тиждень** на Cloudflare WAF Analytics → Phase 3 (auth для quota).
- **Discord/email-фідбек «хочу зберегти свій draft»** від >3 unique users → Phase 3.
- **>$50/міс** приходить на ЗСУ через банку → Phase 4 (auto-acknowledge donate-flow).

**Альтернативи:** повна Phase 3+4 одразу — відхилено як overinvestment перед PMF.

---

## ADR-021: Drawing polish — auto-layout corner picker + єдина конвенція осей + UA-одиниці BOM

**Статус:** Accepted (2026-06-05)

**Контекст:** Аудит креслень виявив 5 залишкових пунктів (Phase 2.9.b): номери гибів лише у callout збоку (не на лінії), у header лише габарит розгортки (не готового виробу), BOM у грамах без площі фарбування, ризик накладок розмірних блоків на геометрію, відсутні Ø-виноски на отворах. Рендерер (ReportLab/ezdxf, ADR-013) — фіксований двоколонковий layout, переписувати який поза межами фази.

**Рішення:** Інкрементальні правки `_draw_*` функцій + 3 нові pure-модулі під `export/layout/` і `export/dimensions.py`, кожен покритий юніт-тестами окремо від рендерингу (детермінізм, CLAUDE.md §2.4):

1. **Bend badges** (`layout/bend_badges.py`): коло з номером гибу посеред лінії розгортки (PDF) + midpoint `#N` TEXT на BEND_TEXT (DXF) — на додачу до повного callout.
2. **Finished dimensions** (`dimensions.py`): габарит ЗІГНУТОЇ деталі у header. **Єдина консистентна конвенція осей** для всіх 5 шаблонів: X×Y = силует профілю, Z = довжина лінії гибу (`width`); перфо-панель плоска → Z = товщина. Свідомо відходимо від змішаних осей у початковому ТЗ (там L-bracket мав `z=thickness`, що ігнорує реальний extrude-розмір `width`) — консистентність важливіша й коректніша.
3. **BOM UA-одиниці**: маса г→кг, новий рядок «Площа фарбування (м²)» (2× заготовки). Лейбли вже були українські (DejaVuSans підтримує кирилицю) — переклад не потрібен. 5 дубльованих inline-блоків винесено у pure `bom_text_lines`.
4. **Auto-layout corner picker** (`layout/corner_picker.py`): pure `pick_annotation_corner` обирає кут аркуша з найбільшим вільним прямокутником під блок анотації (BR-fallback). Вживається контейнерно: BOM позиціонується під фактичним низом таблиці гибів (слідує за нею при 2 гибах). Повний 4-кутовий relocation — для майбутнього multi-page layout.
5. **Hole Ø-dims** (`layout/hole_dims.py`): `should_dim_individual_holes(count, cap=10)` — dim на кожен отвір (≤cap) або один зразковий + «×N отворів» (перфо). PDF — виноска+«Ø8»; DXF — `add_diameter_dim` на новому шарі DIM_HOLES.

**Наслідки:**

- ✅ Креслення ближче до ISO 7200: однозначні гиби, повний BOM, габарит готового виробу, Ø-callouts.
- ✅ Локалізація UA для оператора лазерного різання.
- ✅ Детермінізм збережено; perf далеко в межах бюджету (PDF ~48мс, перфо-117-отворів ~95мс проти 5с; R-021 не потрібен).
- ⚠ Габарит готового виробу — орієнтир (зовнішні довжини полиць, нехтуємо поправкою на товщину/радіус ≤ thickness). Документовано у docstring `dimensions.py`.
- ⚠ Corner picker реалізований повноцінно (12 тестів), але двоколонковий layout не дає вільних кутів аркуша → contained-вживання (BOM під таблицею). Повна цінність розкриється з multi-page.

**Альтернативи:** (а) Номер гибу лише у callout — відхилено, оператор дивиться на лінію. (б) DIMENSION на кожен з сотень отворів перфо — відхилено (роздуває DXF, нечитабельно) → cap 10. (в) pdftotext для тест-асертів — недоступний у env → pypdf (екстрактує кирилицю/×/Ø).

---

## ADR-022: Клієнтська валідація матриці гибу через bake'ed snapshot

**Статус:** Accepted (2026-06-08)

**Контекст:** На staging виявлено баг (Hotfix 2.9.c): corner_angle з t=5мм/R=2.5мм показував у студії зелений банер «Параметри валідні», хоч матриця для t=5 дозволяє лише R∈{4.0, 5.0}. Причина — накопичений розрив: Zod-схема шаблону перевіряє лише `bend_radius_mm ∈ глобальний enum {1, 2.5, 4, 5}`, не звіряючись із залежністю (матеріал, товщина) → (допустимі радіуси). Сервер цю матричну перевірку робить (ADR-019, `validateExportBends` через cad-engine), клієнт — ні. Додатково: при долітанні 422 з сервера `createExport` ігнорував тіло і кидав generic «API 422: експорт не вдався», ховаючи дружній `detail`.

ADR-019 (серверна валідація як інваріант) лишається в силі — клієнтська перевірка її **доповнює**, не замінює. Проблема суто інженерна: матриця живе у `bend-machine-esi.yaml`, який читається через `node:fs`; браузер до нього доступу не має, а дублювати матрицю руками — порушення single-source.

**Рішення:**

1. **Bake YAML→TS на prebuild.** `tools/scripts/bake-bend-matrix.ts` читає `bend-machine-esi.yaml`, валідує тією ж `loadSpec` Zod-схемою і запікає типізований `packages/cad-engine/src/generated/baked-spec.ts` (`export const bakedSpec: BendMachineSpec`). Запускається у `prebuild` cad-engine; файл також комічений (тести зелені без build-кроку). YAML лишається ЄДИНИМ джерелом — `bakedSpec` завжди похідний.
2. **Browser-safe split cad-engine.** `node:fs`-loader (`loadSpecFromFile`) винесено у `spec-node.ts` (subpath `@flatcraft/cad-engine/node`); головний entry лишається без `node:*` (тест-скан графа гарантує). Інакше Next тягне `node:fs` у клієнтський бандл.
3. **Одна реалізація матричної валідації.** `validateExportBends`/`bendInputFor`/Problem-маппінг перенесено з `apps/api` у `@flatcraft/cad-engine` (`validators/export-gate.ts`, приймає spec параметром). Сервер і браузер ділять ОДНУ функцію; api re-експортує. Web кличе її через `bakedSpec` (`apps/web/src/lib/bend-matrix.ts`).
4. **UI gate.** 4 редактори (l/z/corner/wall) рахують `matrixIssues` (useMemo) і показують червоний банер із матричним повідомленням замість зеленого; студії блокують кнопку (`disabled={!isValid || matrixIssues.length > 0}`). `createExport` парсить RFC 9457 (`detail` → `errors[].message` → generic).

**Наслідки:**

- ✅ Невалідна (матеріал, товщина, радіус) ловиться у студії ДО запиту — конкретне повідомлення, кнопка disabled.
- ✅ Single source of truth збережено: один YAML, baked snapshot, одна функція валідації на клієнт+сервер.
- ✅ cad-engine тепер безпечно імпортується у браузер (subpath `/node` ізолює `node:fs`).
- ⚠ `bakedSpec` — snapshot на момент build. Свіжість гарантують `prebuild` + turbo `^build` перед typecheck/test/build у CI. Зміна YAML без rebuild → застарілий клієнтський snapshot (сервер усе одно перевіряє актуальний YAML — fail-safe).
- ⚠ Радіус — спільне поле шаблону (`bend_radius_mm`), не per-bend; сценарій «невалідний саме 2-й гиб» непредставний у моделі.

**Альтернативи:** (а) Дублювати матрицю у клієнтський код руками — відхилено (порушує single-source, дрейф). (б) Тримати валідацію лише на сервері — відхилено: погана UX (помилка лише після кліку), хоч безпеково достатньо. (в) Запікати у `dist/*.json` і імпортувати JSON — відхилено на користь типізованого `.ts` (повний type-check, без resolveJsonModule/copy-фрагільності). (г) Окремий легкий валідатор лише радіуса на клієнті — відхилено, перевикористання `validateExportBends` точніше і без дрейфу.

---

## ADR-023: Discord як infrastructure-as-code — декларативний TS-config + idempotent reconcile

**Статус:** Accepted (2026-06-11)

**Контекст:** Soft-launch (ADR-020) потребує публічного каналу зворотного зв'язку. Обрано Discord community-сервер (структуровані forum-канали з тегами bug/feature, gated-категорії за інтересами). Сервер, налаштований кліками у UI, недокументований і дрейфує: ніхто не пам'ятає, чому канал має такий permission-overwrite, а відновити структуру після помилки нічим. Прецедент декларативної інфри у репо вже є — `infra/ansible/` для Mirohost (ADR-011). Обмеження Discord API: створення application/bot/сервера, Community-фіча (ToS-wizard), Onboarding і Welcome Screen НЕ автоматизуються — лишаються ручними.

**Рішення:** Standalone workspace `infra/discord/` (`@flatcraft/discord-tools`: discord.js v14, zod, vitest; без нових root-залежностей). Config — єдине джерело істини у `config/*.ts` (12 ролей 3-axis таксономії authority/selfid/interest, 7 категорій, 19 каналів з permission-overwrites), валідується Zod при імпорті + крос-файлова перевірка цілісності. Три idempotent-скрипти: `snapshot` (read-only pull → `docs/discord-config/`), `diff` (dry-run для PR-review), `apply` (reconcile). Архітектурні інваріанти:

1. **`apply` ніколи не видаляє.** Orphan'и (є у Discord, нема у config) лише попереджаються — рішення за людиною.
2. **`apply` тільки вручну з машини** (`pnpm discord:apply`). У CI — лише read-only snapshot (weekly cron + dispatch), який авто-комітить doc при drift'і.
3. **Pure-ядро без discord.js-моків:** diff/permissions/markdown/apply-оркестратор працюють над plain-об'єктами і портами; discord.js — тонкий адаптер у `scripts/`. Позиції порівнюються як відносний порядок (Discord переприсвоює абсолютні числа), tie-групи не порівнюються; overwrites — declared-subset semantics (category-sync не drift).
4. **Snapshot-рендер без timestamp:** однаковий стан → байт-у-байт однаковий файл, weekly Action комітить лише реальний drift.

**Наслідки:**

- ✅ Структура сервера version-controlled: зміни через PR з рев'ю diff'ом, manual-drift видно у weekly snapshot-комітах.
- ✅ Відновлюваність: порожній сервер → `apply` → повна структура за ~30 операцій.
- ✗ Ручні кроки лишаються (`MANUAL_SETUP.md`): app/bot/OAuth, Community-wizard, Onboarding (`docs/discord-config/ONBOARDING.md`), Welcome Screen.
- ⚠ Forum-теги обмежені 20 символами (Discord API) — префікс `tpl:` замість `template:` з ТЗ.
- ⚠ Bot-токен — лише `.env` (gitignored) + GH Secrets; Server Members Intent не вмикається (скриптам досить `Guilds`).

**Альтернативи:** (а) Налаштувати руками + Server Template як backup — відхилено: template не version-controlled, не показує drift. (б) Готові тули (discord-server-as-code, Terraform discord-провайдери) — відхилено: незрілі/закинуті, своя тонка обгортка над discord.js простіша за аудит чужої. (в) `apply` у CI після merge — відхилено: write-доступ до live-спільноти з CI небезпечний, обсяг змін малий, ручний запуск дешевий.

---

## ADR-024: Production-grade DXF — рівно 2 шари + color-coded cut paths

**Статус:** Accepted (2026-06-15)

**Контекст:** Перегляд експортованого DXF у AutoCAD 2026 виявив **P0-баг**. DXF мав 6+ шарів: зовнішній контур на `LASER_CUT`, але отвори — на окремому `INNER_CUTS`, плюс `BEND_TEXT` (callout-и + `#N` badge), `DIM`/`DIM_HOLES` (розміри, які тягнули за собою авто-генерований `Defpoints` і DIMENSION-блоки). CAM-софт виробництв (Lantek/SigmaNest/ESI) інтерпретує шар «LASER_CUT» як «усе, що ріже лазер». Отвори на `INNER_CUTS` він **пропускав** → деталь виходила без отворів → вторсировина. Текст і розміри у DXF — CAM-noise: оператор їх не використовує, а CAM може спіткнутись об TEXT/DIMENSION entities.

**Рішення:** DXF несе **рівно 2 виробничі шари**, усі cut-paths — на одному:

- **`LASER_CUT`** (ACI color 7, ByLayer): ВСІ контури різання. Зовнішній периметр — `LWPOLYLINE` без власного кольору (успадковує 7 від шару). Внутрішні вирізи (отвори) — `CIRCLE` на тому ж шарі, але з **explicit ByEntity color 5 (blue)**, щоб CAM/людина візуально відрізняли inner від outer.
- **`BEND_LINES`** (ACI color 3 green, linetype `DASHED`): лінії гибу (info, не ріжуться).

Жодних `TEXT`/`DIMENSION` entities. Напрям гибу (UP/DOWN), номери гибів, Ø-виноски, розміри — лишаються **тільки у PDF** (для людини). Службові шари `0` і `Defpoints` створює сам ezdxf і їх видалити не можна (DXF-інваріант) — вони лишаються **порожніми**; тести рахують лише custom-шари.

**Наслідки:**

- ✅ CAM ріже всю геометрію (периметр + отвори) з єдиного шару — P0 усунено.
- ✅ Чистий файл без CAM-noise; менший розмір (немає DIMENSION-блоків).
- ✅ `DASHED` linetype додається з фіксованим pattern → байт-у-байт детермінізм збережено (snapshot-тести зелені).
- ✅ Регресія покрита: 5 structural-snapshot (по шаблону) + integration reopen + інваріант «2 шари» на всіх шаблонах.
- ⚠ Інформація про напрям гибу більше не дублюється у DXF — оператор бере її з супровідного PDF (обидва файли йдуть разом в експорті).
- ⚠ `0`/`Defpoints` лишаються у файлі (ezdxf), але порожні — формально шарів у таблиці більше двох; «2 шари» стосується виробничих.

**Альтернативи:**

- ESI/Lantek-style розділення `CUT_OUTER`/`CUT_INNER` (два окремі cut-шари) — відхилено: складніше для дрібного виробництва, наш color-by-entity на одному шарі читається будь-яким CAM як «усе ріже».
- DIN 6770 color-only (без шарів, лише кольори) — відхилено: шари `LASER_CUT`/`BEND_LINES` — стандарт-де-факто у LibreCAD/FreeCAD-флоу наших користувачів.
- Лишити Ø-розміри у DXF як «зручність» — відхилено: це і був головний CAM-noise; розміри належать PDF.

---

## ADR-025: Ізометрія у PDF через OCC hidden-line-removal (вектор, детермінований)

**Статус:** Accepted (2026-06-16)

**Контекст:** PDF-креслення мало лише 2D-розгортку — виробнику важко з першого погляду
впізнати кінцеву зігнуту форму. Потрібен довідковий 3D-вигляд (ізометрія) у правій
колонці під таблицею гибів. Раніше це відкладали на «post-MVP» (docstring `export/pdf.py`),
бо WebGL→PNG render — окремий pipeline і ризик для байт-у-байт детермінізму (CLAUDE.md §2.4).

**Рішення:** Малюємо **векторний інженерний каркас** (wireframe): видимі ребра суцільні,
приховані — пунктирні, з отворами. Замість ручної 3D→2D проєкції (крихко для гибів +
отворів) використовуємо вбудований OpenCascade hidden-line-removal (`HLRBRep_Algo`), яким
cadquery уже володіє (`occ_impl/exporters/svg.py:getSVG`). Worker будує 3D-solid через
`build_*(params)` для кожного шаблону (раніше відкидав — `_ = build_*`); проганяємо його
через HLR → `VCompound`/`OutLineVCompound` (visible) + `HCompound`/`OutLineHCompound`
(hidden) → дискретизуємо у 2D-полілайни (`export/isometric.py`) → малюємо у ReportLab.

`build_*` навмисно не вирізає отвори у 3D (preview = чистий extrude; отвори живуть у
DXF/розгортці). Тож для ізометрії згортаємо `unfolded.holes` (єдине джерело істини) назад
на 3D-грані й вирізаємо циліндри одним boolean-викликом (`export/isometry_solid.py`,
пер-шаблонний мапінг для corner_angle/wall_shelf/perforated_panel).

**Наслідки:**

- (+) Коректна обробка згинів і отворів «з коробки» (HLR — геометричний движок), без
  ручної тригонометрії.
- (+) Лишається байт-у-байт детермінованим: HLR детермінований для фіксованого
  input + версії OCP, дискретизація з фіксованим tolerance; геометрія — чиста функція
  params. Підтверджено тестом `test_однаковий_вхід_однакові_байти`.
- (+) Pure-vector → жодних растрових залежностей, малий розмір PDF.
- (−) Boolean-cut отворів + HLR додають ~0.1–0.5с на експорт (у межах бюджету 5с).
- (−) Пер-шаблонний fold-мапінг отворів — крихкий до змін осей у `build_*` (Y-знак
  corner_angle уже спіймали); прикрито unit-тестом «отвори додають полілайни».
- Додано scoped mypy-override `OCP.*` (без py.typed) — лише для `export/isometric.py`.

**Альтернативи:**

- WebGL/three.js → PNG render — відхилено: окремий headless-pipeline, важкий, ризик
  недетермінізму (anti-aliasing/драйвер), великий PDF.
- Ручна ізометрична проєкція box-моделей — відхилено: hidden-line removal для невипуклих
  згорнутих форм + отворів = власний HLR-движок, саме те, чого уникаємо.
- Затінений тілесний прізм (faces fill) — відхилено користувачем на користь каркасу з
  пунктирними прихованими ребрами (інженерна конвенція, видно всі грані й отвори).

---

## ADR-026: R3F render-gate + ErrorBoundary як defense-in-depth проти крашу на invalid params

**Статус:** Accepted (2026-06-16)

**Контекст:** P0-баг на staging — у студії гибового шаблону (corner_angle/l_bracket/
z_bracket/wall_shelf) введення замалого значення плеча (напр. «1» при товщина+радіус
= 4.5 мм) валило весь застосунок: controlled input → миттєве оновлення params →
`useMemo` у Scene кличе `build*ShapeCommands` (`packages/ui/src/3d-viewport/geometry.ts`)
→ assertion `throw` → **uncaught у React-дереві** → WebGL Context Lost → white-screen
«Application error». Perforated_panel (без гибу) — імунний.

**Рішення:** Три шари захисту:

1. **Render-gate (основний):** новий чистий валідатор `validateProfile`
   (`packages/cad-engine/src/validators/profile.ts`) — єдине джерело істини, що
   **дзеркалить assertion'и `geometry.ts`** для всіх 4 шаблонів. Кожен viewport-wrapper
   (`apps/web/src/components/*-viewport.tsx`) кличе його на (debounced) params і при
   issues рендерить `InvalidParametersFallback` замість `<Canvas>` — throw не виникає.
2. **R3FErrorBoundary (backstop):** класовий error-boundary (`packages/ui`) обгортає
   сцену й ловить будь-який неочікуваний uncaught throw усередині R3F → дружній
   fallback «3D-прев'ю тимчасово недоступне» + retry.
3. **Form-gate + server parity:** студії/редактори показують банер + блокують експорт
   (immediate params); Fastify-gate (`validateExportProfile`) і Python-worker
   (`validate/profile.py`) валідують незалежно → 422 RFC 9457 (ADR-019 defense-in-depth).

`validateProfile` повний паритет з `geometry.ts` (узгоджено): strictness точно як в
assertion'ах — legs `leg >= t+r` (inclusive), z/wall flanges + offset + shelf строго
`> threshold`. Прикрито property-тестами (fast-check TS 300 + hypothesis Python 300,
спільний oracle).

**Наслідки:**

- (+) App не крашить через invalid params: render-gate не дає throw; boundary ловить
  решту. Ясне UA-повідомлення замість white-screen.
- (+) Один валідатор → клієнт (render-gate + банер) і сервер (Fastify + worker) ділять
  логіку; не дублюється.
- (−) Пер-шаблонний паритет із `geometry.ts` треба синхронізувати при зміні геометрії
  білдерів (прикрито property-тестами + інваріантом CLAUDE.md §7).
- (−) viewport валідує debounced-params, банер — immediate → короткий лаг між банером
  і fallback'ом (прийнятно; debounce Phase 2.6 не чіпаємо).
- ui-vitest отримав `jsx:automatic` + `.test.tsx` include (boundary-тест без DOM/нових
  deps); web-stub доповнено `R3FErrorBoundary` (passthrough) + Scene-плейсхолдерами.

**Альтернативи:**

- Лише ErrorBoundary без render-gate — відхилено: boundary показав би загальний
  «недоступне» без конкретної поради; render-gate дає точне «Збільшіть плече A до 4.5 мм».
- Кешувати last-valid geometry (показувати попередню сцену при invalid) — відкладено
  (L3, окремий PR): більший scope, не потрібен для усунення крашу.
- Прибрати assertion'и з `geometry.ts` (не кидати) — відхилено: throw там — корисний
  інваріант для unit-тестів білдерів; гасимо його gate'ом, а не послабленням контракту.

---

## ADR-027: Products як preset базового шаблону

**Статус:** Accepted (2026-06-22)

**Примітка (housekeeping 2026-07-17):** текст відновлено ДОСЛІВНО з коміту `90f1639` (гілка `docs/phase-3-architecture`, PR #28). Уточнення щодо причини відсутності на main: PR #28 **ніколи не мержився** (досі `OPEN`, останній рух 2026-06-22) — це не випадок «втрачено при merge», а «ADR ніколи не потрапляв на main через власний PR». Сама реалізація Phase 3.0 (Products Catalog) усе одно відбулась — через окрему серію merged PR (#32, #37-#44, 2026-06-23), що зробило #28-#31 стейл-дублікатами (деталі: `docs/promts/inputs/housekeeping-audit.md` п.2).

**Контекст.** До Phase 3.0 каталог `/templates` показує 5 параметричних деталей
(`l_bracket`/`z_bracket`/`corner_angle`/`wall_shelf`/`perforated_panel`) — інженерна
аудиторія: повна Zod-схема, всі поля редаговані. Бізнес-мета розширення — UX-shift
від CAD-інструменту до сервісу для DIY/малого бізнесу. Додаємо нову сутність «виріб»
(`product`) як **preset базового шаблону з обмеженим набором редагованих полів**:
користувач конфігурує лише relevant параметри (наприклад, ширину панелі), решта
зафіксовані виробником продукту (форма отвору, товщина, матеріал).

Перші два вироби Phase 3.0:

1. **Декоративна перфо-панель** — на основі нового шаблону `perforated_panel_square`
   (рішення 6: новий шаблон, не extension), preset з фіксованим shape=square.
2. **Кастомна настінна полиця** (`wall-shelf-custom`) — на основі нового шаблону
   `enclosed_shelf` (4-сегментний box з опційними перфо-боковинами і ребром
   жорсткості), preset з фіксованою товщиною/радіусом/перфо-параметрами.

Це рішення фіксує **архітектурний контракт products-layer** перед стартом 8-PR
імплементації — щоб подальші sub-PR'и виконувалися детерміновано і не вертали
питання, що вже обговорені.

**Рішення.** Сім архітектурних виборів нижче — прийняті як єдиний пакет, бо
взаємозалежні (зокрема 1+2 та 5+6+7). Кожний з власними ALT/CHOICE/RATIONALE/
CONSEQUENCES; trade-off аналіз із трьох осей (розгортання / масштабування /
підтримка) проведений окремо у дискусійному циклі — тут лишається стиснутий sumар.

### Рішення 1. `products` як окрема drizzle-таблиця vs дискримінатор `type` у `templates`

**Альтернативи.** A) розширити `templates` колонкою `type: 'part' | 'product'` +
nullable product-only поля. B) окрема таблиця `products` зі слабкою прив'язкою до
templates через slug (без FK).

**Вибір.** **B** — окрема таблиця.

**Обґрунтування.**

- Семантичні відмінності: parts мають повну Zod-схему та auto-generated PNG; products
  — фото/render готового виробу та fixed_parameters/visible_fields. Один рядок
  templates із nullable колонками обох категорій (~50% NULL-density) лишався б
  напівпорожнім для кожної категорії.
- Ризик зростання templates до 50+ полів: кожна нова product-фіча у варіанті A
  додає `ALTER TABLE templates` і впливає на існуючі 5 part-рядків. У B — parts
  стабільні.
- Композиція у Phase 3.1 (composite products) — третя категорія, що потребує ще
  одного дискримінатора у A → cartesian-bloat. У B — `products.components jsonb`
  додається ізольовано.
- Без FK constraint навмисно: templates можуть жити лише у seed/Python-коді
  (slug як ідентифікатор у worker'і), FK вимагав би гарантованого DB-присутності.

**Наслідки.**

- (+) NULL-density 0% в обох таблицях; кожна Drizzle-модель чисто типізована.
- (+) Existing `GET /v1/templates` API лишається стабільним; products додаються як
  новий endpoint без зміни legacy-контракту.
- (+) Окремий index `products_published_idx` чистий; query plan простий.
- (−) Дві CRUD-функції замість однієї; перевірка цілісності `base_template_slug`
  делегована Zod-validator'у seed'а (a не FK).
- (−) JOIN `products → templates` неможливий на SQL-рівні — resolved в API через
  два запити; для двох продуктів irrelevant, при 50+ — `IN`-batch query.

### Рішення 2. URL routing — `/products/[slug]` vs `/templates/[slug]` для виробів

**Альтернативи.** A) все під `/templates/[slug]`, тип розрізняється у API response
(дискримінатор). B) окремий route `/products/[slug]`; каталог-URL лишається
`/templates` (umbrella з `?tab=products|parts`).

**Вибір.** **B** — окремий `/products/[slug]`.

**Обґрунтування.**

- SEO семантика: Google розрізняє `/templates/*` (інженерні «креслення») від
  `/products/*` (готові вироби) у Search Console — різні запити та різні rich
  results (schema.org/Product vs CreativeWork). Один URL-pattern для обох — втрачає
  цю диференціацію.
- Shareability: «Дивись який вирід я зробив: hart.crimea.ua/products/...» —
  одразу зрозуміло, що це готовий товар. URL читабельний.
- API consistency: дзеркало Рішення 1 — `GET /v1/templates/:slug` і `GET /v1/products/:slug`
  мають чисті response shapes; жодного дискримінатор-narrow на клієнті.
- Bug isolation: 404 з `/products/foo` одразу вказує на product-каталог; під одним
  URL-pattern діагностика складніша.

**Наслідки.**

- (+) Caталог `/templates` лишається umbrella-page; toggle `?tab=` — shallow routing
  без перезавантаження.
- (+) Sitemap.xml розділяє два логічні набори; CDN TTL можна налаштувати окремо.
- (+) Existing 9 e2e на `/templates/[slug]` лишаються зеленими (additive change).
- (−) +1 новий Next.js route + +1 API endpoint (~200 LOC).
- (−) `<TemplateStudio>` обертається обидвома page-компонентами (`templates/[slug]`
  і `products/[slug]`) — shared layer через Рішення 3.

### Рішення 3. Studio component — shared з `mode` prop vs два окремі studio

**Альтернативи.** A) для кожного шаблону створити другу копію студії з product-
логікою (`<PerforatedPanelProductStudio>` тощо). B) `mode: 'part' | 'product'`
prop у існуючих 5 студіях + `visibleFields`/`fixedParameters`/`productMeta` props.

**Вибір.** **B** — shared з `mode` prop.

**Обґрунтування.**

- Економія коду: AutoForm уже інтроспектує Zod-схему, додавання filter'у через
  `visible_fields` (рішення 4) — +5 LOC; копіювання повної студії — ~300 LOC × 3
  нових файлів дубляжу.
- UX consistency by design: один компонент = одна ментальна модель; розсинхрон
  між part-studio і product-studio (типова проблема варіанту A) неможливий.
- TypeScript discriminated union props (`{mode: 'part', ...} | {mode: 'product',
productMeta, visibleFields, fixedParameters}`) — narrow змушує передати правильні
  props; неможливо випадково передати product у part-flow.
- Bug fix у shared логіці (валідація, export-button) — в одному файлі автоматично
  відображається в обох режимах.

**Наслідки.**

- (+) 5 студій лишаються по одному файлу на шаблон; +~80 LOC mode-логіки на студію.
- (+) Існуючі 5 \*-editor компонентів не торкаються (новий prop опційний).
- (+) Composite products (Phase 3.1) додається як `mode: 'composite'` — той самий
  компонент, ще одна гілка narrow'у.
- (−) Більша когнітивна складність компонента — кожен contributor пам'ятає, який
  код виконується в якому режимі. Mitigation: TS-наратив + `assertNever(mode)`
  у default case.
- (−) Ризик випадкового coupling: поле для product-mode може ненавмисно
  використатися у part-mode. Покривається unit-тестами на mode='part' regression.

### Рішення 4. AutoForm розширення — `visible_fields` prop vs preprocess schema

**Альтернативи.** A) preprocess: `derivedSchema = baseSchema.pick(visibleFieldsMap)`
перед передачею у AutoForm. B) `visible_fields?: string[]` prop у AutoForm,
схема не торкається, filter застосовується після інтроспекції.

**Вибір.** **B** — prop-based.

**Обґрунтування.**

- Pure data transformation: AutoForm отримує оригінальну схему + список фільтра;
  не мутує Zod-структуру, легше дебажити.
- Cross-field валідатори (`.refine()`, наприклад wall_shelf `front_lip` 0 або ≥5)
  не ламаються — Zod-схема цілісна, refine коректно референсує всі поля. У варіанті
  A `pick()` може видалити поля, на які `refine` посилається → runtime-fail.
- Legacy AutoForm (без prop) працює без змін — `visible_fields=undefined` → весь
  schema (зворотна сумісність 5 part-editor'ів).
- Conditional visibility (`useMemo(() => computeVisibleFields(state), [state])`) —
  природний React pattern; динамічна preprocess Zod-схема потребує `useMemo` +
  deep cloning, гірше масштабується.

**Наслідки.**

- (+) Зміна `@flatcraft/ui/parameter-form/`: +1 опційний prop, +1 рядок фільтру.
- (+) Default values, group metadata (ADR-017), `.refine()` лишаються нетронутими.
- (−) Studio робить explicit merge `submittedValues + fixed_parameters → POST` — це
  не унікально до B, але треба пам'ятати, що сервер чекає повний об'єкт.
- (−) `visible_fields: string[]` не type-safe (можна передати неіснуюче ім'я).
  MVP: runtime warning + Zod-валідатор на seed cross-перевіряє поля проти
  `template.parameters_schema`. Type-safe upgrade (`keyof TShape`) — окремий PR.

### Рішення 5. `enclosed_shelf` — новий базовий шаблон vs extension `wall_shelf`

**Альтернативи.** A) розширити `wall_shelf` опційними полями `left_side_mm`/
`right_side_mm`/`top_rib_mm` + cross-field валідатори. B) окремий шаблон
`enclosed_shelf` зі своєю schemа/builder/scene/studio.

**Вибір.** **B** — новий шаблон.

**Обґрунтування.**

- Геометрична різниця принципова: `wall_shelf` — U-channel (3 сегменти, 1-2 гиби);
  `enclosed_shelf` — 4-5-сегментний box (back+bottom+2 sides+optional rib, 4-5 гибів).
  Спільність pipeline ~30% (тільки generic export-layer reuse), не 95%.
- Cross-field складність експоненційна: wall_shelf уже має `front_lip` 0 або ≥5;
  додавання `sides`/`rib` створило б 8-dimension cartesian (mode × front_lip × sides
  × rib). Test coverage непідйомний.
- Snapshot regeneration ризик: будь-яка зміна `wall_shelf` default body перегенерує
  DXF/PDF snapshot fixtures (CLAUDE.md §2.4 інваріант). Новий шаблон — нульовий
  ризик для existing wall_shelf.
- `buildWallShelfShapeCommands` (geometry.ts, 13 unit) — pure builder для 1-2 inner
  bends. Перетворення на 2-режимну функцію (U vs box) ламає всі assertion'и
  одночасно.

**Наслідки.**

- (+) Парадигма CLAUDE.md §4 моноpепо («окремий шаблон = окремий файл по кожному
  шару») лишається консистентною.
- (+) `validateProfile` (ADR-026) для enclosed_shelf — окремий case у одному
  switch'і; wall_shelf branch не торкається.
- (+) Snapshot байт-стабільність wall_shelf гарантована.
- (−) Дубляж pipeline (~500 LOC: Pydantic + Zod + builder + unfold + scene + studio
  - editor). Mitigation: generic exporters (`_export_flat_dxf`, `_draw_unfold_generic`)
    з Phase 2.10.a уже покривають export-layer reuse.
- (−) ExportRequest discriminatedUnion +1 варіант → 6 templates загалом; pattern
  встановлений Phase 2.10 — без сюрпризів.

### Рішення 6. perforated_panel square holes — extension `hole_shape` vs новий шаблон

**Альтернативи.** A) extension через `hole_shape: 'circle' | 'square'` (default
`'circle'`) у `perforated_panel` — backward-compat, ~30 LOC. B) окремий шаблон
`perforated_panel_square` зі своєю pipeline.

**Вибір.** **B** — новий шаблон ⚠ (контр до master prompt'у, який припускав A).

**Обґрунтування (попри більший LOC).**

- Regression isolation: existing `perforated_panel` snapshot fixtures (Phase 2.10.d)
  лишаються байт-у-байт стабільними нульовою зміною коду. У варіанті A є ризик
  Pydantic serialization `hole_shape` defaults впливає на JSON-payload hash → PDF
  text «Ø8» vs «8×8» при default migration.
- CAM-перевірка окремо per template: LWPOLYLINE 4-vertex entity (square) vs CIRCLE
  entity (circle) — Lantek/SigmaNest можуть обробляти по-різному (Risk 6 у PR).
  Один файл per template дозволяє isolated CAM-pilot перевірку на справжньому
  виробництві перед merge.
- Lineage у каталозі: `perforated_panel` і `perforated_panel_square` як два окремі
  base templates — користувач (інженер, не product-консумер) розрізняє у списку
  шаблонів. Products маскують це деталь implementation: декоративна перфо-панель
  — продукт, користувач не бачить slug.
- ADR consistency з Рішенням 5: «принципова різниця → новий шаблон» застосовується
  тут до DXF entity type як критичної відмінності для CAM-софту.

**Свідомо приймаємо trade-off проти DRY-principle:**

- A коштувала б ~30 LOC vs ~400 LOC у B (95% дубляжу через generic exporters).
- A забезпечила б instant 3-rd shape extension (hex/slot/oval) через enum.
- B при 5+ shape варіантах призведе до template-bloat у каталозі (5 шаблонів-перфо).
  Mitigation: тригер re-think у Phase 3.5+ (див. «Trigger перегляду» нижче).

**Наслідки.**

- (+) Нульова regression для `perforated_panel`; existing 5 part-shelf тестів і
  Phase 2.10.d snapshots green без змін.
- (+) Окремий CAM-pilot перевірочний крок для square — isolated.
- (+) discriminatedUnion +1 варіант → 7 templates з enclosed_shelf.
- (−) ~400 LOC дубляжу (Zod + Pydantic + builder + scene + studio + editor + tests).
- (−) Якщо post-launch evidence покаже, що 3-й/4-й shape потрібен, доведеться
  re-architect на extension (А) — болісніше за raw-rebuild.
- (−) `industry_names`, `bend-machine-esi.yaml`, validation matrix — те ж саме
  reuse, нульова специфіка нового шаблону.

### Рішення 7. Composite products (наприклад, мангал з 4 перфо + 2 кутника) — у scope Phase 3.0 чи відкладено

**Альтернативи.** A) повна підтримка composite у Phase 3.0: BOM-агрегація, ZIP-export,
multi-DXF, assembly preview. B) відкладено до Phase 3.1: Phase 3.0 — single-base
products only. C) hybrid — infrastructure готова (BOM stub + ZIP utility + Studio
mode='composite'), але без real composite products у seed.

**Вибір.** **B** — відкладено до Phase 3.1.

**Обґрунтування.**

- Перші два вироби Phase 3.0 — single-base-template products. Composite потребує
  окремої архітектурної роботи (BOM aggregation, ZIP packaging, assembly instructions
  PDF, cross-component validation, R3F assembly positioning) — не блокує MVP.
- Avoid over-engineering для unproven use case: ми не знаємо, чи композити справді
  потрібні користувачам, перш ніж soft-launch. Build infrastructure for known use
  cases (2 single products); composite додається коли є evidence попиту.
- Variant C (hybrid: infrastructure без implementation) розглядався — відхилений,
  бо ~400 LOC dead-code до Phase 3.1, API-shape lock-in без real-flow validation,
  і testing gap (unit-only без integration). Migration cost у Phase 3.1 від pure
  B → composite = ~1 тиждень refactoring (non-breaking: discriminator додається
  до ProductSchema, existing single products NULL для composite-полів) — прийнятна
  ціна за збереження YAGNI у Phase 3.0.

**Trigger переходу на Phase 3.1 (composite).** Активуємо, якщо:

- Discord/email фідбек: >5 unique users просять «вирід з кількох частин одним
  експортом».
- Аналітика: >20% користувачів роблять 2+ експорти на одному session (proxy для
  assembly use case).
- Виробничий пілот: замовники просять «kit з мангала: 4 панелі + 2 кутника».
- Кількість single products перевищить 10 (assembly use case стає прогнозованим).

**Наслідки.**

- (+) Phase 3.0 фокусується на доставці 2 products за 3.5 тижні (target 2026-07-16).
- (+) API ABI Phase 3.0 lock на single shape; composite додається через discriminator
  у Phase 3.1 (non-breaking).
- (+) Test surface і documentation у межах одного PR-набору (8 PR'ів за планом).
- (−) Якщо post-launch фідбек одразу requestує composite → +2-3 тижні чекати
  Phase 3.1. Manageable: workaround через окремі експорти + manual assembly,
  фідбек channel існує.
- (−) Phase 3.1 не отримує заздалегідь спроектованої архітектури — деякі рішення
  (S3 file structure для multi-artifact, R2 paths) робляться coordinated з real
  composite use case. Замість «pre-design правильно з першого разу» — «evidence-
  driven design з невеликим refactoring cost».

### Загальні наслідки рішень 1-7

Зміни, які чекають у sub-PR'ах Phase 3.0 (PR 2-9, див. Roadmap):

- **Data model (PR 2):** нова таблиця `products` (8 колонок), Zod-схеми
  `ProductSummary`/`ProductDetail`, pure helpers `resolveProductParams` і
  `filterSchemaByVisibleFields`. Drizzle migration `0001_*.sql`. Seed-структура
  `seed-products.ts`.
- **API (PR 2):** endpoints `GET /v1/products` і `GET /v1/products/:slug`;
  розширення `POST /v1/exports` приймати або `template_slug+parameters`, або
  `product_slug+userInput` (server резолвить fixed_parameters перед forward у
  cad-worker).
- **UI (PR 3-4, 6, 8):** новий `<SegmentedControl>` primitive; `templates/page.tsx`
  додає toggle Вироби|Деталі (default Вироби, бо це primary use case soft-launch);
  shared `<TemplateStudio mode>` обертає 5 існуючих студій; `/products/[slug]`
  route рендерить product з resolved params.
- **Templates (PR 5, 7):** новий шаблон `perforated_panel_square` (повна piipeline,
  Рішення 6); новий шаблон `enclosed_shelf` (4-5-сегментний box, опційні
  перфо-боковини і ребро жорсткості, Рішення 5).
- **Тести:** pytest 249 → ~290-310; cad-engine TS 63 → ~85; ui TS 70 → ~95;
  web TS 47 → ~70; api TS 35 → ~50; e2e 92 → ~115. Existing — green throughout
  усіх PR (regression-guard інваріант).
- **Виробничий процес додавання 3-го виробу post-Phase-3.0:** тільки seed entry
  у `products` + render PNG (через extended `generate-product-previews.ts` з Phase
  2.16.b). Без коду — за умови, що base_template уже існує.

### Альтернативи, які активно відкинуті (поза 7 основними)

- **Окремий домен `products.hart.crimea.ua`.** Відхилено: дроблення SEO authority,
  додаткова DNS+CF Caddyfile конфігурація, +Origin Cert. Жодних практичних переваг
  для MVP.
- **`products` із FK на `templates.id`.** Відхилено: templates можуть бути визначені
  лише у seed/Python-коді (slug — primary identifier у worker'і). FK constraint
  вимагав би гарантованого DB-присутності templates → ламає поточну архітектуру.
- **Render-prop pattern для Studio** (`<Studio render={mode => ...}/>`). Відхилено:
  ускладнення без виграшу — лише інша форма того самого `if (mode)`.
- **Composite через окрему таблицю `bundles`** (третя entity besides templates і
  products). Відхилено: занадто рано вводити третю abstraction перш ніж evidence.
  Composite як extension products — natural ramp-up у Phase 3.1.
- **Generic `<ShapeBuilder>` з runtime config** (один Python builder, читає JSON-
  config «N сегментів, M гибів»). Відхилено: occurence-driven refactoring. Поки
  5-7 шаблонів — окремі builders простіші для junior'а. Потенційне Phase 6+
  архітектурне рішення при template-pool >20.

### Trigger перегляду ADR

- Рішення 6: якщо `perforated_panel_square` дубляж стане непідйомним при додаванні
  3-го shape (hex/slot/oval) — re-architect на extension (A) з міграційним PR'ом.
- Рішення 7: при спрацюванні composite-тригерів (вище) — створюємо ADR-028
  «Composite products як extension products».
- Рішення 3: якщо `mode='product'` логіка набухне >150 LOC у одній студії —
  розділення на дві студії стає виправданим (re-architect).

---

## ADR-028: Валідація перфорації (pitch > розмір отвору) як окремий gate

**Статус:** Accepted (2026-06-24)

**Контекст:** Каталожна декоративна перфо-панель (perforated_panel_square) мала
параметри □20 мм при `pitch_y=10` мм. Геометрично сусідні отвори по осі Y
перетинаються (місток `pitch − hole = −10` мм) і зливаються у вертикальні прорізи —
DXF несе 11 злитих слотів, тоді як BOM/підпис рахує «88 окремих отворів □20». Жодного
gate'у на це не було: Zod перевіряє лише діапазони полів (pitch 10–200, hole 3–30),
а перетин — це cross-field геометрія. Виявлено тест-кейсами математики наповненості
(`tests/templates/test_perforated_panel_fill_math.py`).

**Рішення:** Окремий валідатор `validatePerforation` (cad-engine) — НЕ розширення
`validateProfile` (той — дзеркало `geometry.ts` про достатність плеча/полиці відносно
гибу; перфорація без гибів, інший концерн, і не має блокувати R3F render-gate, бо
плоский лист рендериться коректно). Правило: для додатного містка між отворами
`pitch > hole_size` по кожній осі (square → `hole_size_mm`, round → `hole_diameter_mm`);
`pitch ≤ hole_size` → `HOLES_OVERLAP` (торкання з нульовим містком теж invalid). Три
шари паритету (як ADR-019/026): клієнт (банер у редакторах + блок експорту в студії),
Fastify-gate (`validateExportPerforation` → 422 RFC 9457), Python-worker
(`validate/perforation.py` → 422). Property-парність з незалежним oracle (hypothesis 300).

**Наслідки:**

- (+) Неможливо згенерувати DXF зі злитих отворів, які BOM рахує як окремі.
- (+) Той самий валідатор на 3 рівнях; коди (`HOLES_OVERLAP`) узгоджені TS↔Python.
- (=) Seed-дефолт декоративної панелі (□8, pitch 25/25) валідний — лишається без змін.
  Перетин виникав лише при користувацькій конфігурації (□20/pitch_y=10 у скриншоті);
  саме її тепер ловить gate.
- Поки правило суто геометричне (`> 0` місток); мінімальний технологічний місток
  (ligament ≥ t або фікс. мм для лазера) — потенційний follow-up, коли буде spec-значення.

**Альтернативи:**

- Додати правило в `validateProfile` — відхилено: змішало б bend-profile і grid-концерни,
  і перетин блокував би R3F render-gate без потреби (плоский лист валідний для 3D).
- Лише Zod-`.refine` у схемі — відхилено: дублювалося б між web/api/worker і не дало б
  дружнього UA-повідомлення з підказкою; патерн проекту — спільний валідатор у cad-engine.

---

## ADR-029: Клієнтський перемикач форми отвору над двома шаблонами (без злиття)

**Статус:** Superseded by ADR-031 (2026-06-26)

**Контекст:** Користувач має обирати тип отвору перфо-панелі (круг/квадрат) у самому
конфігураторі. Форма живе у двох окремих шаблонах: `perforated_panel`
(`hole_diameter_mm`, DXF `CIRCLE`, PDF `Ø`) і `perforated_panel_square`
(`hole_size_mm`, DXF `LWPOLYLINE`, PDF `□`) — розділення з PR 5 (regression-ізоляція,
CAM). Початковий план Phase 3.0 передбачав єдине поле `hole_shape`, але реалізація
пішла на два шаблони.

**Рішення:** Варіант B — **не зливати** шаблони; додати **клієнтський перемикач**
(`SegmentedControl` «Круглі | Квадратні») у спільній студії. `holeShape` піднятий у
`PerforatedPanelStudio`, керує похідними `templateSlug`/`schema`/`renderViewport`;
`TemplateStudio` лишається змонтованим (params + матеріал зберігаються при свопі).
Стан params тримає **обидва ключі розміру синхронно** (`syncHoleKeys`); активна
Zod-схема читає свій, зайвий відкидається `ExportRequestSchema` (z.object) на API
перед форвардом у worker (`extra="forbid"`). **Нуль змін у backend / Pydantic / worker
/ DB / снапшотах** — байт-детермінізм і розділення шаблонів збережені. Хелпери —
`apps/web/src/lib/perforation-shape.ts`; редактори/студії злиті в один кожен.

**Наслідки:**

- (+) Picker у конфігураторі для шаблону й продукту; перемикання без втрати введеного.
- (+) ADR-027 «Рішення 6» (два шаблони) і ADR-024 (CAM DXF: CIRCLE vs LWPOLYLINE) не
  порушені — worker отримує чисті per-shape params.
- (−) Інваріант «обидва ключі синхронні» тримається клієнтом (`syncHoleKeys`); зайвий
  ключ покладається на strip `ExportRequestSchema` (зафіксовано тестом в `exports.test.ts`).
- Reversible: якщо колись зливати у `hole_shape`-шаблон — це окреме рішення (більший PR
  - reseed), цей перемикач не блокує.

**Альтернативи:**

- Злиття у один шаблон з `hole_shape` — відхилено зараз (DB-reseed, merge снапшотів, ADR-
  reversal); лишається можливим follow-up.
- Два окремі продукти (round+square) — відхилено: не дає picker'а в самому конфігураторі.

---

## ADR-030: Перфо-монтажна панель — ребриста (4 фланці + кутові отвори), не опційно

**Статус:** Accepted (2026-06-25) — розширено ADR-031 (форма отвору як параметр; круг теж ребристий)

**Контекст:** Користувач попросив доопрацювати виріб «перфорована панель» під реальну
монтажну панель (фото-референс): усі 4 сторони зміцнені ребрами жорсткості (фланцями
90°), у 4 кутах площини установочні отвори Ø5.5 для кріплення у шафу, вільні кути ребер
скруглені R5, на кресленні — кріпильні розміри (між отворами). Питання: новий шаблон чи
розширити існуючий, і чи ребра опційні.

**Рішення:** **Розширити `perforated_panel_square`** (квадратна перфорація — як на фото),
зробивши **ребра ОБОВ'ЯЗКОВИМИ** (не nullable-опція). Тобто квадратна перфо-панель тепер
ЗАВЖДИ ребриста монтажна панель — гнутий лоток. Круглий `perforated_panel` лишається
ПЛАСКИМ (поза скоупом).

Геометрія розгортки — **хрест/плюс** (як `enclosed_shelf`): центральна перфо-площина
`length×width` (= між лініями гибу) + 4 фланцеві «язики», кожен спан свого краю площини →
**кутова розрядка автоматична** (кути відкриті, фланці не накладаються при гибі, зазор
≈BA). Нове відносно `enclosed_shelf`: **R5-скруглення вільних кутів ребер** (DXF — bulge-
дуги), **4 установочні Ø5.5 на площині** (inset 12мм), **culling перфорації** у keep-out
навколо установочних отворів. `rib_corner_radius` (R5) та `corner_hole_inset` (12) — фікс.
константи воркера (не у Zod-формі); `rib_height` (15–50) і `bend_radius` (allowed set) — у
формі. Кріпильні розміри — у PDF (людино-розмір), у DXF їх немає (ADR-024).

**Наслідки:**

- (+) Один продукт у каталозі, прогресивна складність; UI-перемикач круг/квадрат лишається
  (тепер: «пласка кругла» ↔ «ребриста квадратна монтажна»).
- (+) Панель тепер валідується на гиб (радіус vs товщина, ADR-019) + `rib_height > t+r`
  (profile-gate, ADR-026) — паритет TS↔Python.
- (−) **Breaking-redefinition** `perforated_panel_square`: DXF/PDF output змінився; немає
  byte-снапшота саме для цього slug (структурний snapshot покриває лише 5 інших), тож реген
  не знадобився, але семантика виробу інша.
- (−) Перфорація біля кутів cull'иться (кутові точки решітки) → інваріант «повна решітка»
  ослаблено до «решітка cols×rows мінус ≤4 кутові точки».
- 3D-прев'ю показує лоток (4 ребра + кутові отвори); isometric у PDF немає (як
  `enclosed_shelf`).

**Альтернативи:**

- Новий окремий шаблон `perforated_panel_ribbed` — відхилено (користувач обрав «розширити
  існуючу»); було б чистіше за байт-стабільність, але дублювало б studio/schema/handler.
- Опційні ребра (nullable, як `enclosed_shelf.stiffening_rib`) — відхилено користувачем
  («ребра обов'язкові»): умовна логіка bend-таблиці/валідації/прев'ю у спільному коді.
- Установочні отвори на ребрах (а не на площині) — відхилено користувачем (на площині).

---

## ADR-031: Уніфікація перфо-панелі в ОДИН параметричний шаблон (форма отвору — параметр)

**Статус:** Accepted (2026-06-26) — supersedes ADR-029, розширює ADR-030

**Контекст:** ADR-029 збудував абстракцію «два шаблони, що різняться лише формою
отвору» (toggle круг/квадрат + shim `perforation-shape.ts`). ADR-030 зламав цю
симетрію: переробив **лише** `perforated_panel_square` на ребристий монтажний лоток,
лишивши `perforated_panel` плоским листом. Наслідки помітив користувач: (1) кругла
панель без ребер, квадратна — з ребрами (порушення DRY/SOLID: дубльовані param-класи,
build/unfold/dxf/pdf/validate, Zod-схеми, 3D-сцени, viewport-и); (2) висоту ребра не
можна змінити у формі продукту; (3) у 3D-прев'ю ребра вгору, хоча гиб `direction='down'`.
Усі три — симптоми зламаної симетрії.

**Рішення:** Злити обидва шаблони в **ОДИН** `perforated_panel` (ребристий монтажний
лоток), де форма перфо-отвору — звичайний параметр `hole_shape` (circle|square). Єдина
гілка, що лишається, — рендер отвору (circle → `CIRCLE`/cylinder, square → `LWPOLYLINE`/box).
Розмір отвору — єдиний ключ `hole_size_mm` (прибрано `hole_diameter_mm` і весь
`syncHoleKeys`). Ребра рендеряться **вниз** (−z/−Y, узгоджено з `direction='down'`).
`perforated_panel_square` видалено всюди (worker/types/cad-engine/ui/web/db); slug
`perforated_panel_square` прибирається з БД при seed (`RETIRED_TEMPLATE_SLUGS`). Продукт
«Декоративна перфо-панель» → base `perforated_panel`, `fixedParameters.hole_shape='square'`,
`userEditableFields += rib_height_mm` (радіус гибу лишається фіксованим дефолтом). Toggle
круг/квадрат лишається як UX, але тепер просто редагує параметр `hole_shape` (не свопає
slug/схему/viewport).

**Наслідки:** Прибрано дублювання по всьому стеку: один param-клас/build/unfold/dxf/pdf/
dimensions/validate/k_factor (worker), одна Zod-схема + одна гілка export-union (types),
один slug у validate/export-gate (cad-engine), одна 3D-сцена + один viewport (ui/web),
видалено shim `perforation-shape.ts`. Кругла й квадратна форми тепер ідентичні в усьому,
крім геометрії отвору — рівно як того хотів користувач. Висота ребра редагована у формі;
ребра у 3D — вниз. Мінус: зміна slug — разова seed-міграція (staging pre-launch, ризик
низький; стара перфо-панель була `isPublished=false`-base без публічного запуску).
Снапшоти DXF/PDF свідомо перегенеровано. Байт-детермінізм збережено.

**Альтернативи:**

- Залишити два шаблони + спільне ядро (shared-модуль) — менший ризик (без міграції slug),
  але лишає два param-класи й не прибирає toggle-shim; відхилено на користь чистого SOLID.
- Відкат ребер у квадратної (обидва плоскі) — суперечить ADR-030 («ребра обов'язкові»).
- Зробити ребра опційними (rib_height=0 → плоский) для обох — найгнучкіше, але два
  режими геометрії/валідації; відхилено (KISS).

---

## ADR-032: Observability & self-improvement loop

**Статус:** Accepted (2026-07-05)

**Контекст:** Перед публічним soft-launch платформа **сліпа** (діагноз
`docs/14_ARCHITECTURE_EVOLUTION.md §1.4`): pino-логи живуть у stdout контейнера і ніхто їх
не читає; Sentry (Phase 5.1) і продуктова аналітика (Phase 5.2) не зроблені; історія
експортів — in-memory `JobStore` (`apps/api/src/routes/exports.ts`), яка втрачається при
рестарті; ніде не рахується, який constraint найчастіше блокує користувача (R-10), ні чи
зійшлась деталь у металі (R-01). Після запуску ми не дізнаємось ні про краш R3F на телефоні
(R-02 acceptance неперевірюваний), ні де користувач страждає. Принцип, який фіксуємо: **кожен
експорт — це експеримент, результат якого платформа зобов'язана зібрати** (14 §4). Обмеження —
ресурси MS21 (2 vCPU / 4 GB, ADR-011), solo-maintenance (R-07) і GDPR-by-design
(CLAUDE.md §7-8, ADR-006).

**Рішення:** Побудувати observability трьома рівнями (технічна телеметрія → продуктова
аналітика → виробничий фідбек) на мінімальному стеку, що вписується в один сервер.
Специфікація — `docs/11_OBSERVABILITY.md`; послідовність PR — `docs/02_ROADMAP.md` §Phase 3.3.
Шість складових рішень, кожне з альтернативою / вибором / обґрунтуванням / наслідками:

**1. Сховище подій — Postgres-таблиця `events`, не зовнішній метрик-стек.**

- _Альтернатива:_ Prometheus + Grafana + OpenTelemetry-колектор, або «тільки pino stdout».
- _Вибір:_ append-only таблиця `events` у наявному Postgres
  (`id, ts, event_type, template_slug, process, params jsonb, error_code, duration_ms,
session_hash`).
- _Обґрунтування:_ MS21 не має ресурсу під окремий метрик-стек (анти-цілі 14 §5); solo-проєкт
  не має ким його обслуговувати (R-07 — складність головний ворог). Головне: `events` — це
  **продуктові дані**, не тільки метрики: `params jsonb` join'иться з `exports` і дає
  найцінніший датасет платформи (які параметри реально конфігурують, які constraint блокують).
  Метрик-стек цього не вміє, а SQL — вміє. Postgres уже в стеку → нуль нових залежностей, один
  бекап покриває і телеметрію.
- _Наслідки:_ (+) SQL-join `events`↔`exports`; дешево; бекап уже є. (−) не realtime-дашборд
  (прийнятно при ~100 експортів/день); потрібен retention-job; складне алертування замінює
  щотижневий digest.

**2. Трекінг помилок — Sentry SaaS free tier ×3, не self-hosted і не «тільки pino».**

- _Альтернатива:_ self-hosted GlitchTip (ще один контейнер → тиск на RAM MS21, R-11); «тільки
  pino» (нуль видимості клієнтських крашів).
- _Вибір:_ Sentry (SaaS free tier) у web + api + worker з обов'язковим `beforeSend`-фільтром PII.
- _Обґрунтування:_ це єдиний спосіб дізнатись про краш R3F на реальному телефоні (R-02
  acceptance зараз неперевірюваний — 14 §4.1); free tier покриває обсяг MVP; SaaS не їсть RAM
  сервера (R-11). `beforeSend` фільтрує email/IP — це вже інваріант CLAUDE.md §8 (R-04), паритет
  з pino-redact (`apps/api/src/logger.ts`).
- _Наслідки:_ (+) реальна видимість крашів на трьох сервісах; підтверджує R-02. (−) третя
  сторона-процесор → згадка у Privacy Policy (GDPR); DSN — тільки через env (`.env.example` з
  плейсхолдерами); sample-rate errors 100 % / traces 0 (ресурси MS21).

**3. Історія експортів — persist у таблицю `exports`, не in-memory.**

- _Альтернатива:_ лишити in-memory `JobStore` (втрата історії при рестарті — 14 §1.4);
  зберігати в Redis.
- _Вибір:_ persist у таблицю `exports` (уже описана в `docs/05_DATA_MODEL.md §2`) через
  drizzle-репозиторій з **тим самим інтерфейсом**, що й наявний `JobStore` (SSE-flow не
  змінюється). Retention артефактів у R2 — 90 днів від останнього скачування (data-model §7).
- _Обґрунтування:_ історія експортів = сировина для калібрування, статистики й аудиту; робить
  можливим R-12 mitigation 5 (аудит R2 на історичні invalid-експорти). p95 `export_duration` з
  `events.duration_ms` робить бюджети CLAUDE.md §9 вимірюваними, а не декларативними.
- _Наслідки:_ (+) довговічна, аудитована історія; drop-in заміна (інтерфейс-паритет). (−)
  потрібна міграція (PR 2, створює yurii вручну — CLAUDE.md §6); наявні e2e SSE мають лишитись
  зеленими.

**4. Продуктова аналітика — Umami self-hosted, не Plausible і не «нічого».**

_(Фінальне рішення yurii, 2026-07-05.)_

- _Альтернатива:_ **Plausible CE (self-hosted)** — потребує ClickHouse (~2 ГБ RAM) → не влазить у
  4 ГБ MS21 поряд зі стеком (web/api/worker/postgres/redis/minio); **Plausible Cloud** — щомісячні
  кошти + дані поза Україною (суперечить логіці ADR-011 «дані фізично в UA»); **«нічого»** —
  воронка невидима, R-10 лишається інтуїцією.
- _Вибір:_ **Umami self-hosted** на наявному MS21, окрема БД у **наявному** Postgres-контейнері
  (без нового datastore). Cookie-less, GDPR-friendly (ADR-006 → без cookie-banner).
- _Обґрунтування:_ Umami зберігає у Postgres, який уже є → **нуль додаткового RAM** на окремий
  datastore (на відміну від Plausible/ClickHouse); дані лишаються в Україні (ADR-011); cookie-less
  → GDPR без cookie-banner. Воронка `catalog → studio_opened → param_changed →
validation_error_shown → export_clicked → export_done`; ключова метрика —
  `validation_error_shown` з розбивкою по constraint (який ліміт найчастіше блокує → кандидат на
  ширшу параметризацію) — прямий вхід для R-10. Umami підключається `<script>`'ом — **нуль
  npm-залежностей**.
- _Наслідки:_ (+) видимість воронки без нового datastore, дані в UA. (−) ще один легкий
  Node-контейнер + окрема БД → деплой **окремим майбутнім PR** (`infra/compose` + `infra/ansible`,
  CLAUDE.md §6). web-vitals (FCP/TTI/mesh-update) — як custom events. **Тригер перегляду рішення:
  понад 500K подій/міс** (тоді зважити ClickHouse / винесений інстанс).

**5. Digest — щотижневий cron → Discord webhook, не email і не дашборд.**

- _Альтернатива:_ email (потрібен SMTP/Postmark — нова залежність); власний дашборд
  (build + auth + хостинг — overkill для solo).
- _Вибір:_ cron (неділя 18:00 Europe/Kyiv) → SQL по `events`/`exports`/`export_feedback` за
  7 днів → markdown → Discord webhook (`DIGEST_WEBHOOK_URL`).
- _Обґрунтування:_ найдешевше (один cron + webhook), інфра Discord уже існує (ADR-023). Це
  звичайний webhook-POST, **не** `pnpm discord:apply` (CLAUDE.md §6 не порушено). Markdown-digest
  — ідеальний вхід для дешевої LLM-моделі (14 §4.4, `docs/15` C3). Формат: top-5
  `validation_error` по constraint, failed exports, p95 `export_duration` vs бюджет §9,
  deviation-репорти (Phase 3.4+), Sentry-summary.
- _Наслідки:_ (+) нуль нової інфри; сирі дані → щотижневий список рішень. (−) не інтерактивний
  (прийнятно); залежить від `events`+`exports` (PR 2 першим). Правило процесу: **кожен пункт
  digest'а → або GitHub-issue, або явно «accepted noise»** — це і є механізм самовдосконалення.

**6. GDPR-межі — без PII у телеметрії.**

- _Альтернатива:_ логувати IP / стабільний session-id для багатшої аналітики (відхилено — GDPR,
  §8, R-04).
- _Вибір:_ `events` і `export_feedback` — **без email/IP**; `session_hash` = хеш із **добовим
  salt** (непереслідуваний між днями); retention 12 місяців; правило «параметри виробу —
  технічні дані, не PII».
- _Обґрунтування:_ GDPR-by-design (CLAUDE.md §7, R-04); мінімізація PII. Параметри — це
  геометрія, не персональні дані. Добовий salt не дає зшити сесії користувача між добами
  (агрегатний сигнал є, стеження немає). 12 міс — паритет з retention `audit_log`
  (data-model §7).
- _Наслідки:_ (+) аналітика без експозиції PII. (−) не можна відстежити користувача крос-день
  (свідомо — потрібен агрегат, не нагляд); згадка у Privacy Policy.

**Наслідки (загальні):**

- Замикається **self-improvement loop** (14 §4.4): `Sentry + events + export_feedback +
web-vitals → щотижневий digest → issue/hotfix + обов'язковий регресійний тест` (культура
  «інцидент → тест», Hotfix 2.10.e) → калібрування YAML. Рішення перестають прийматись наосліп.
- Бюджети CLAUDE.md §9 стають вимірюваними (p95 export з `events.duration_ms`).
- Ризики отримують інструментацію: R-02 (краш на mobile) стає перевірюваним, R-10 (шаблони не
  задовольняють потреби) — вимірюваним, R-12 (аудит R2) — можливим, R-01 (K-фактор) готується
  до замикання у Phase 3.4 (виробничий фідбек).
- Фаза розбита на PR-и (docs-gate → імплементація → progress-log), деталі — `docs/02_ROADMAP.md`
  §Phase 3.3. Нові top-level залежності (`@sentry/*`) вводяться у своїх PR з явним OK
  (CLAUDE.md §6). Umami — `<script>`, нуль npm-залежностей.

**Альтернативи (для фази загалом):** повний observability-стек (Prometheus + Grafana + Loki +
OTel + Kafka/event-sourcing + ML-пайплайн) — відхилено як анти-ціль (14 §5): на 2 vCPU / 4 GB і
10 users/day він коштує більше, ніж дає, і суперечить R-07. Sentry (free) + Postgres `events` +
Umami (self-hosted) + Discord webhook покривають 100 % потреб MVP і v1.x.

---

## ADR-033: Template Registry contract — єдиний реєстр шаблонів + conformance-suite

**Статус:** Proposed (2026-07-13). Docs-only gate Phase 3.5 (`docs/02_ROADMAP.md`, промпт A2/B4 з `docs/15_LLM_PROMPTS.md`).

**Контекст:**

- 14 §1.2, §2 і C1-інвентаризація (`docs/promts/inputs/c1-template-inventory.md`, 2026-07-13) показали: додавання шаблону №7 сьогодні торкається **~12 місць у 5 workspace**. Вартість «нового виробу» — ~ 20 файлів + 3 тестові набори + оновлення 4-х hardcoded set-ів у `template-studio.tsx:29-35,90-107`.
- Дрейф уже фактичний. C1 фіксує **8 поведінкових розбіжностей** з file:line:
  - F1 `WallShelfParametersBaseSchema` у ExportRequest замість refined → server пропускає `front_lip_mm` constraint.
  - F2 `enclosed-shelf-viewport.tsx` без `validateProfile` (порушує інваріант ADR-026).
  - F3 `perforated-panel-editor.tsx:59-62` замінює `bendMatrixIssues` → server кидає при експорті.
  - F4 `bends`-контракт має **3 різні форми** (scalar / array-2 / array-4 / array-1-2 / array-3-4).
  - F5 Scene-builder розколотий між `packages/ui/src/3d-viewport/geometry.ts` (3 шаблони) і inline у `-scene.tsx` (2 шаблони).
  - F6 `enclosed_shelf` не експортовано з Python `templates/__init__.py:__all__`.
  - F7 `l_bracket` і `enclosed_shelf` — немає dedicated e2e-spec.
  - F8 `perforated_panel` — SegmentedControl над AutoForm, patternless.
- Мета — новий шаблон = **1 TS-модуль + 1 Python-модуль + снапшоти + автогенерований spec**. Нуль правок у `apps/web`, `apps/api`. «Різні вироби по-різному відображаються/обраховуються» має стати **структурно неможливим**.

**Рішення (6 підпунктів, кожне ALT/CHOICE/RATIONALE/CONSEQUENCES).**

### 1. Де живе реєстр — новий `packages/templates` vs розширення `packages/types`

- _ALT-A:_ окремий пакет `packages/templates` — містить `TemplateDefinition`, реєстр, sceneBuilder-и, validators.
- _ALT-B:_ розширити `packages/types/src/templates/` — додати сам definition-контракт поряд зі схемами.
- _CHOICE:_ **ALT-A** (`packages/templates`).
- _RATIONALE:_ `packages/types` за конвенцією browser-safe і містить **лише Zod-схеми** без runtime-залежностей (три.js, React, CadQuery). `sceneBuilder` тягне `three.js` — недоречно в `types`. `packages/ui` вже залежить від `three.js`, але містить UI-компоненти, а реєстр — це data. Окремий пакет тримає межу «data vs UI» чистою. Deps: `packages/templates` → `packages/types` + `packages/cad-engine` (validators + spec + `ShapeCommand`-тип) — **без `packages/ui`**. `packages/ui` стає **споживачем** реєстру (generic-viewport імпортує `TEMPLATE_REGISTRY`), а не його залежністю. Обов'язкова умова — реєстр повинен імпортуватись у `apps/api` (Fastify, Node.js) БЕЗ `react`/`react-dom` у бандлі, інакше startup-час і bundle-size ростуть без причини. Наслідок: тип `ShapeCommand` переїжджає з `packages/ui/src/3d-viewport/geometry.ts` у `packages/cad-engine` (це data-контракт для sceneBuilder-ів, не UI-код). Це джерело істини, з якого `apps/web`, `apps/api`, `workers/cad` (парити) читають.
- _CONSEQUENCES:_ (+) один точковий import у web/api; (+) definition можна тестувати без React/three; (+) `apps/api` імпортує реєстр без React у бандлі — інваріант, захищений автотестом у PR 2 («import-graph `apps/api` не містить `react`/`react-dom`»); (−) новий workspace = +tsconfig, +vitest, +CI-крок; (−) міграція C1-об'єктів (`hole_grid.ts`, частина `geometry.ts`, `ShapeCommand` з `packages/ui`) потребує перенесення (у PR 2).

### 2. Доля `discriminatedUnion` у `ExportRequest`

- _ALT-A:_ зберегти `discriminatedUnion` — генерувати його з реєстру у compile-time (codegen або TS-мапа).
- _ALT-B:_ відмовитись від union — `ExportRequest = { slug: string, params: unknown }`, дискримінація у registry-lookup runtime.
- _ALT-C:_ використовувати generic `z.object({ slug, params: z.unknown() }).superRefine((v, ctx) => registry[v.slug].schema.parse(v.params))`.
- _CHOICE:_ **ALT-C** (`superRefine` через registry).
- _RATIONALE:_ ALT-A вимагає **breaking-change для F1** (`WallShelfParametersBaseSchema` → refined) або codegen-стеку. ALT-B втрачає Zod-parse на межі API — гірший error message. ALT-C дає точний Zod-error, дозволяє **refined-схеми у registry** (не Base), і працює з будь-якою кількістю шаблонів без discriminatedUnion-обмежень. Type-narrow досягається через окремий `TemplateSlug`-літерал union, генерований з `Object.keys(TEMPLATE_REGISTRY)` через `satisfies` (compile-time).
- _CONSEQUENCES:_ (+) F1 виправляється — server бачить `front_lip_mm` constraint; (+) `enclosed_shelf` / `perforated_panel` не мають Base-варіанту, вимога знімається; (−) TS-inferrence на `ExportRequest.params` потребує narrow-функції `narrowParams(slug, params)` — тонкий helper.

### 3. Generic editor через AutoForm + `.describe()` vs збереження ручних editor'ів

- _ALT-A:_ повний generic — `<AutoForm schema={def.schema} defaults={def.defaults} onChange={...} />`, ручних editor-файлів немає.
- _ALT-B:_ generic + слоти для special controls (F8 SegmentedControl, F3 custom validator hint) через `def.ui.extraControls?: ExtraControlSpec[]`.
- _ALT-C:_ зберегти ручні editor'и, обгорнути реєстром лише definition (мінімальний крок).
- _CHOICE:_ **ALT-B** (generic + декларативні extra-controls).
- _RATIONALE:_ ALT-A ламає F8 (SegmentedControl `hole_shape` не мапиться на AutoForm-полe без extra) і F5 (wall-shelf summary тексти). ALT-C нічого не міняє (18 файлів лишаються). ALT-B декларує extra-controls у definition (`{ kind: 'segmented', field: 'hole_shape', options: [...] }`), і generic-editor їх рендерить. Це закриває F8 без hard-code'у.
- _CONSEQUENCES:_ (+) 18 файлів (`*-editor.tsx`) видаляються; (+) validation chain (`bendMatrixIssues + profileIssues + zodIssuesToFieldErrors + validatePerforation`) уніфікується у AutoForm через `def.validators: Validator[]` — F3 закрито; (−) contract'у розширюється (extra-controls kind-union); (−) для складніших UX (product-mode `visibleFields`) definition потребує опційного `def.ui.visibleFields?: string[]`.

### 4. Generic viewport через sceneBuilder-реєстр

- _ALT-A:_ definition має `def.ui.sceneBuilder: (params, thickness) => ShapeCommand[]` — generic-viewport будує `ExtrudeGeometry`.
- _ALT-B:_ definition має `def.ui.render: (params, thickness) => ReactNode` — повна свобода R3F-JSX.
- _ALT-C:_ реєстр з двома kind-ами: `{ kind: 'extrude', shapeBuilder }` для L/Z/wall/corner, `{ kind: 'composed', node }` для enclosed/perforated.
- _CHOICE:_ **ALT-C** (два kind-и sceneBuilder).
- _RATIONALE:_ ALT-A не тримає F5 (enclosed_shelf/perforated_panel — BoxGeometry-композиція, не 2D-shape sweep). ALT-B — занадто вільно, вбиває інваріант «нема per-slug коду в apps/web». ALT-C фіксує **два дозволених патерни** у контракті, і кожен новий шаблон обирає один. Це знімає F5.
- _CONSEQUENCES:_ (+) `packages/ui/src/3d-viewport/geometry.ts` перетворюється на утиліти для `kind:'extrude'`; (+) `enclosed-shelf-scene.tsx`/`perforated-panel-scene.tsx` переносяться у definition; (+) F2 закривається — generic-viewport ЗАВЖДИ викликає `validateProfile()` через `def.validators`; (−) якщо з'явиться 3-й патерн (наприклад, procedural mesh), контракт розширюється (новий kind).

### 5. Python-реєстр + parity-тест slug-ів

- _ALT-A:_ ручний реєстр у `workers/cad/flatcraft_cad/templates/__init__.py` (`TEMPLATES: dict[str, type[Template]]`).
- _ALT-B:_ автоматична реєстрація через `__init_subclass__` у `base.py:Template`.
- _CHOICE:_ **ALT-A** (ручний dict).
- _RATIONALE:_ ALT-B ламає explicit-import у Python (файл, який не імпортовано, не реєструється) — потрібен явний `from ... import *` у `__init__`, що додає магії. ALT-A закриває F6: якщо `enclosed_shelf` відсутній у dict, parity-тест з TS-реєстром негайно fail'ить у CI.
- _CONSEQUENCES:_ (+) Parity-тест `test_templates_registry_parity`: `set(TS_REGISTRY.keys()) == set(PY_REGISTRY.keys())` (експортовано у JSON через `tools/scripts/export-registry.ts` під час prebuild); (+) F6 закривається; (−) prebuild-крок додає ~0.5с.

### 6. Conformance-suite — параметризований набір, автогенерований з реєстру

Для кожного slug у реєстрі CI ганяє КОЖНУ з перевірок:

1. **Schema parity TS↔Python** — property-based (fast-check + hypothesis), як у Hotfix 2.10.e (150+ iter): згенерований TS-об'єкт валідно парситься Pydantic'ом і навпаки.
2. **DXF/PDF детермінізм** — фіксований seed → фіксовані байти (снапшот-тест, patrern з `workers/cad`).
3. **Render-gate** — на невалідних параметрах generic-viewport показує fallback, не крашиться (`R3FErrorBoundary` — backstop, ADR-026).
4. **e2e smoke** — Playwright: відкрити `/templates/{slug}` → змінити параметр → export button reachable. Це **автогенерується з реєстру** — закриває F7 (`l_bracket`, `enclosed_shelf` тепер мають spec).

Suite **fail-closed:** новий шаблон без усіх 4-х проходжень — червоний CI. Реєстр без conformance = червоний CI. Це і є структурна гарантія «шаблон не може бути доданий наполовину».

**Інваріанти, які контракт НЕ сміє ламати (перерахую явно):**

- **Байт-у-байт DXF/PDF** (CLAUDE.md §2.4) — снапшот-тести підтвердять. Ізометрія у PDF (ADR-025) і 2 шари DXF (ADR-024) — інваріанти.
- **Render-gate ADR-026** — generic-viewport обов'язково викликає `validateProfile` перед mount'ом; ErrorBoundary — backstop.
- **Products ADR-027** — `TemplateDefinition` має опційний `def.products: ProductDefinition[]` (`slug`, `fixed`, `userEditableFields`); products lookup — `apps/web` бере з реєстру.
- **Browser-safe entry `packages/cad-engine`** — реєстр не тягне `node:*`; scene-builder-и — pure на браузерних API.
- **Серверна валідація ADR-019** — `def.validators` викликаються Fastify-gate ДО постановки job'а в BullMQ.
- **React-free реєстр** — `packages/templates` (і його import-transitive у `apps/api`) НЕ тягне `react`/`react-dom`. Захищено автотестом у PR 2 (parse import-graph або bundle-analyzer перевірка `apps/api/src/routes/exports.ts`). Ламати цей інваріант = ламати «apps/api — Node.js без DOM».

**Наслідки:**

- Phase 3.5 стає **7 PR-ів** (per-template + registry-package): PR 2 — реєстр + conformance-suite + перенесення `ShapeCommand` з `packages/ui/src/3d-viewport/geometry.ts` у `packages/cad-engine` + автотест «react-free import у `apps/api`» (без міграцій шаблонів). PR 3-8 — по одному шаблону, від простого до складного (C1 §4 порядок: `perforated_panel` → `corner_angle` → `l_bracket` → `z_bracket` → `wall_shelf` → `enclosed_shelf`). E2e зелені після КОЖНОГО PR.
- Після завершення Phase 3.5: `apps/web/src/components/*-{studio,editor,viewport}.tsx` × 18 файлів **видалено**; `TemplateStudioSlug` union автогенерований; `SLUGS_WITH_*` set-и — методи `def.capabilities: string[]`. F2 (render-gate), F5 (scene split), F6 (Python **all**), F7 (e2e coverage), F8 (SegmentedControl) — усі закриті контрактом.
- ADR-033 базовий для **ADR-034 Process layer** (14 §3): `TemplateDefinition.process_slug` стає першим полем `Process`-абстракції.
- Vendor-неутральність: `TemplateDefinition` не знає про sheet-metal specifics (bend_matrix, k_factor) — вони делеговані до `def.validators` і `def.process_slug`. Це готує ґрунт для 3D-друку / CNC як окремих processes.

**Альтернативи (загальні для рішення):**

- **Data-driven через YAML** (замість TypeScript-об'єктів у реєстрі) — відхилено: втрачається type-safety на TS-side, шаблон-схема Zod у YAML не серіалізується.
- **Codegen з YAML-single-source** — розглядалося, відкладено як анти-ціль solo-проєкту (R-07): підтримка codegen'у — окрема робота, і TS/Python дублювання схем усе одно лишається (Pydantic ≠ Zod).
- **Мікросервіс на template** — відхилено як явну анти-ціль 14 §5 (мікросервіси на 4 GB RAM).

---

## ADR-035: AI bugfix flow v2 — issue → тріаж → фікс (Actions) → локальне мультиагентне рев'ю → merge yurii

**Статус:** Accepted (2026-07-19, Master Run 9, docs+infra-only setup-run)

**Контекст:** `docs/14` §4.4 замикає self-improvement loop правилом «кожен пункт digest'а/Sentry
стає issue АБО accepted noise» — але після заведення issue виправлення досі вимагає ручної
Claude Code-сесії. ADR-036 §3 передбачив цю прогалину явно: «оркестрація (запуск run'ів) поки
ручна — на yurii, до запуску ai-bugfix-flow» і зарезервував цей номер. Конвеєр дрібних
виправлень (typo, UX-текст, дрібний off-by-one) не вимагає повної ваги master-run-протоколу
(docs/16) — але вимагає ті самі гейти: людина в контурі на approve і на merge, TDD-регресія
обов'язкова (культура 2.10.e), захист від runaway-агента. `docs/promts/master-ai-bugfix-flow.md`
— другий (після Run 8) реальний прогін ADR-036-конвеєра, і перший, що виносить частину роботи
з локальної сесії у GitHub Actions.

**Рішення** (кожна — альтернатива / вибір / обґрунтування / наслідки):

**1. Лейбл-гейт (`ai-fix`) — тригер лише для власників write-доступу.**

- _Альтернативи:_ тригер на КОЖЕН новий issue (`on: issues: [opened]`) — найпростіше, але
  автоматично виконує тріаж на текст від БУДЬ-ЯКОГО відвідувача публічного репо, без гейту;
  тригер на коментар з `@claude`-згадкою (стандартний патерн `claude-code-action`) — той самий
  проблема: коментувати може будь-хто.
- _Вибір:_ `on: issues: [labeled]` + job-рівня `if: github.event.label.name == 'ai-fix'`
  (аналогічно `ai-approved` для fix-стадії). У GitHub лейбли на issue може ставити лише
  користувач із **write**-доступом до репо (публічний viewer/non-collaborator — не може).
- _Обґрунтування:_ лейбл — це вже вбудований у GitHub permission-check, безкоштовний і не
  вимагає власного allow-list акаунтів. Це основна лінія захисту від prompt-injection: без
  лейбла issue-текст (untrusted input, будь-хто може написати issue у публічному репо) НІКОЛИ
  не потрапляє агенту.
- _Наслідки:_ (+) нуль додаткової інфраструктури для гейту; (−) yurii — єдина людина, що може
  запустити конвеєр (прийнятно, single-maintainer, R-07).

**2. Двостадійність тріаж → `ai-plan-ready`/`ai-architectural`/`ai-need-info` → `ai-approved` → фікс.**

- _Альтернативи:_ одна стадія «лейбл → одразу фікс» — швидше, але агент починає писати код
  без людини, що прочитала план (ризик костиля на неправильному root-cause); тріаж і фікс в
  одному job'і одного workflow — не дає yurii паузи для approve між планом і виконанням.
- _Вибір:_ два окремі workflow на два окремі лейбли. `ai-triage.yml` (label `ai-fix`) лише
  коментує і ставить наступний лейбл (`ai-plan-ready` / `ai-architectural` / `ai-need-info`) —
  **нуль прав на запис коду**. `ai-fix.yml` (label `ai-approved`, ставить yurii ПІСЛЯ читання
  плану) — імплементація.
- _Обґрунтування:_ дзеркалить прийнятий двостадійний патерн (Архітектор план → Будівельник
  код, ADR-036 §3); пауза між тріажем і approve — та сама точка контролю, що в
  `docs/16` §1 «gate переноситься з чату на PR-review», тут — з чату на лейбл.
- _Наслідки:_ (+) yurii завжди читає план ДО того, як щось почне писати код; ARCHITECTURAL-кейси
  зупиняються на тріажі, нуль витраченого фікс-бюджету. (−) на один issue — мінімум 2 ручні дії
  (approve лейбла двічі: implicit через label вибір, і потім merge).

**3. Рев'ю — ЛОКАЛЬНЕ мультиагентне (Claude+agy), НЕ окремий `ai-review.yml` у Actions.**

- _Альтернативи:_ третій workflow `ai-review.yml` (сильна Claude-модель у Actions, тригер на
  `pull_request` від fix-гілки) — симетрично з тріаж/фікс, але: (a) `agy`-квоти прив'язані до
  локального Google-логіна yurii — Actions runner фізично не може викликати `agy`, отже
  рев'ю в CI було б Claude-only, без вендорної диверсифікації (ADR-036 §3 мета); (b) дублювати
  Claude-рев'ю в CI, коли Claude-Будівельник вже писав фікс тим самим вендором — подвійна
  витрата OAuth-квоти на 2 виклики одного вендора замість 1 незалежного крос-вендорного.
- _Вибір:_ рев'ю — `docs/promts/ai-review-local.md`, переюзабельний промпт, який yurii запускає
  ОДНІЄЮ командою локально у свіжій Claude Code-сесії. Оркестратор викликає `agy` (Рев'юер +
  Тест-інженер, обидва read-only) і сам верифікує/оформлює тести — точна дзеркальна структура
  Стадії 3 Master Run 8 (`docs/promts/agy-orchestration-recommendations.md`).
- _Обґрунтування:_ CLAUDE.md §2 «Junior-friendly», «без розумних абстракцій без потреби» —
  третій workflow заради симетрії, коли він не може дати обіцяну вендорну диверсифікацію,
  порушує цей принцип. Локальний запуск — той самий Claude, що вже пройшов Стадію 3 Run 8,
  жодного нового коду не пишеться, лише новий переюзабельний промпт-документ.
- _Наслідки:_ (+) справжня крос-вендорна незалежність (Claude пише код, Gemini рев'ює,
  Claude верифікує вердикт Gemini); нуль подвійної CI-витрати. (−) рев'ю НЕ автоматичне —
  yurii мусить сам запустити команду для кожного `ai-fix`-PR (прийнятний trade-off: merge і так
  завжди ручний). **v3-тригер (явно занотовано, не зараз):** якщо репо стане приватним І з'явиться
  self-hosted runner з доступом до `agy`-логіна (A8, `docs/14`) — тріаж/рев'ю можуть переїхати
  на `agy` у CI повністю; це окреме майбутнє рішення, не частина цього ADR.

**4. `agy` — дозволи НЕ розширюємо; новий журнал `docs/promts/inputs/agy-stats.md`.**

- _Альтернативи:_ звузити `write_file(*)` назад до `write_file(docs/promts/inputs/*)` зараз —
  Run 8 вже показав, що вужчий glob технічно не спрацював (два підтверджені інциденти
  scope-creep, issue #78); розширити дозволи `agy` (напр. `command(git)`) для зручності —
  свідомо відхилено, збільшує blast radius без потреби для ЦІЄЇ ролі (Рев'юер/Тест-інженер —
  read-only за задумом).
- _Вибір:_ усі чинні правила `agy` з Run 8 лишаються БЕЗ ЗМІН (headless `agy -p`; файлова
  передача diff — stdin не працює; без bash; запис лише у `docs/promts/inputs/`; `git status`
  ПІСЛЯ кожного виклику). Додається лише журнал `docs/promts/inputs/agy-stats.md` — один рядок
  на кожен виклик (дата, задача, модель, результат ok/scope-creep/timeout/auth, вердикт
  підтверджений, кейсів прийнято/відхилено).
- _Обґрунтування:_ два інциденти scope-creep за один run (Master Run 8) — це вже патерн, не
  випадковість, але недостатньо даних, щоб обирати між «продовжити з git-status-перевіркою» і
  «розслідувати glob-механізм» (Опитування PR #81, ще не вирішено yurii). Журнал — дешевий спосіб
  накопичити статистику на кілька bugfix-прогонів, перш ніж приймати архітектурне рішення
  (worktree-ізоляція `agy`, чи інше) для v3.
- _Наслідки:_ (+) рішення про majorфутуру `agy`-ізоляцію спирається на дані, не на один інцидент;
  нуль нового ризику цим ADR. (−) ручна дисципліна (оркестратор мусить не забути дописати рядок)
  — як і `git status`-правило, це процес, не механічний гейт.

**5. SECURITY — issue-текст = untrusted input.**

Issue у публічному репо може написати будь-хто (навіть якщо лейбл ставить лише yurii — сам
ТЕКСТ issue не гейтований, і саме він потрапляє в промпт агента). Це відомий клас атак на
CI-агентів (prompt injection через оброблюваний контент). Мітигації, застосовані в обох
workflow (`ai-triage.yml`, `ai-fix.yml`):

1. **Лейбл-гейт** (рішення 1) — основна лінія: без явної дії write-access-користувача текст
   ніколи не доходить до агента.
2. **Мінімальні `permissions:`** — `ai-triage.yml`: `contents: read, issues: write, id-token:
write` (лише коментар+лейбл, без права писати код); `ai-fix.yml`: `contents: write, issues:
write, pull-requests: write, id-token: write` (тільки те, що реально потрібно для гілки+PR;
   жодних `secrets:`, `actions:`, `packages:` за замовчуванням). `id-token: write` обов'язковий
   для `claude-code-action` (OIDC-обмін); це дозвіл на видачу посвідчення самому workflow, НЕ
   запис у репо.
3. **Pinned SHA для `anthropics/claude-code-action`** (не version-тег `@v1`, як решта
   `.github/workflows/*.yml` у репо, — свідомий виняток: це єдина дія в репо, що виконує
   агента над untrusted issue-текстом, елевований поріг довіри до supply-chain виправданий).
   `actions/checkout` лишається на репо-конвенції `@v5` (не обробляє untrusted текст).
4. **Заборонені шляхи** для fix-стадії (рішення C у промпті) — навіть якщо injection обійде
   інструкції промпту, мітигація подвійна: (a) `settings` JSON з `permissions.deny` — механічна
   заборона на рівні Claude Code tool-permissions; (b) окремий verification-step
   (`tools/scripts/check-forbidden-paths.sh`), що валить job, якщо забороненй шлях таки
   змінився.
5. **`concurrency`** — один run на issue (`group: ai-{triage,fix}-<issue-number>`,
   `cancel-in-progress: true`) — захист від паралельного спаму лейблами на той самий issue.
6. **`--max-turns`** (`claude_args`) — стеля ходів проти runaway-витрати підписки/квоти:
   тріаж ~40 (лише читання+коментар), фікс ~150 (TDD-цикл важчий).

**Наслідки (загальні):**

- Нові файли: `.github/workflows/{ai-triage,ai-fix}.yml`, `.github/ISSUE_TEMPLATE/{bug_report,
improvement}.yml`, `docs/promts/ai-review-local.md`, `docs/17_AI_BUGFIX_FLOW.md`,
  `tools/scripts/check-forbidden-paths.sh` (+тест-скрипт), `docs/promts/inputs/agy-stats.md`
  (порожній журнал, перший рядок — на першому реальному прогоні).
- Нові GitHub-лейбли (мануально, чеклист PR): `ai-fix`, `ai-plan-ready`, `ai-approved`,
  `ai-architectural`, `ai-need-info`.
- Новий repo secret (мануально): `CLAUDE_CODE_OAUTH_TOKEN`.
- `docs/promts/master-ai-bugfix-flow.md` (v2) включено у PR — конвенція `docs/promts`.
- ARCHITECTURAL-межа під час Registry-міграції (Run 7): доки триває, тріаж зобов'язаний
  класифікувати фікси у файлах студій/шаблонів як ARCHITECTURAL (уникнути зустрічних правок,
  `docs/17` §«Конфлікт з Run 7»).

**Альтернативи (загальні):** повністю ручний bugfix-процес (статус-кво до цього ADR) —
відхилено, дрібні фікси й далі споживали б повноцінну Claude Code-сесію непропорційно до
розміру задачі; повна автоматизація без гейтів (auto-merge зелених ai-fix PR) — відхилено,
суперечить ADR-036 §5 «гейти незмінні».

---

## ADR-036: Модель розробки 2.0 — треки, ритми, мультиагентний конвеєр

**Статус:** Accepted (2026-07-18; ключові рішення зафіксовані yurii 2026-07-17, цей запис — формалізація у Master Run 6, docs-only)

**Контекст:** Модель «фази і спринти» (CLAUDE.md §11, Roadmap Phase 0-5 → 3.x) виконала свою
роль: MVP feature-complete, staging live, телеметрія активована (ADR-032), виробничий
фідбек-loop замкнено (Phase 3.4). Симптоми зрілості старої моделі: (1) фазова нумерація
роздвоїлась (історична «Phase 3 Auth» проти «Phase 3.x Architecture Evolution» — Roadmap
потребував легенду, щоб його читати); (2) двигуном розвитку стають **дані** (щотижневий digest,
Sentry, виробничий фідбек), а не заздалегідь розписаний план; (3) виконавцем стає **конвеєр
агентів** (master-runs, майбутній ai-bugfix-flow), а не одна сесія; (4) мануальні кроки,
розкидані по PR-чеклистах, губляться — урок: drizzle-міграція з PR #69 стояла тиждень
(розблоковано лише `master-unblock-run.md`). Потрібна модель, де Roadmap — карта черг,
ритми — двигун, агенти — виконавці, yurii — власник гейтів і оцінювач готового продукту.

**Рішення** (п'ять складових, кожна — альтернатива / вибір / обґрунтування / наслідки):

**1. Roadmap — треки-черги без дат, не фази і не kanban поза репо.**

- _Альтернативи:_ лишити фази з датами; kanban-tool поза репо (GitHub Projects, Trello).
- _Вибір:_ `docs/02_ROADMAP.md` — **п'ять треків** (T1 Стабілізація, T2 Registry, T3 Launch,
  T4 Еволюція платформи, T5 Інфраструктура). Кожен трек: мета → нумерована черга «наступний
  PR/run» з готовими посиланнями на промпти `docs/promts/*` → гейт yurii. Без дат і дедлайнів.
- _Обґрунтування:_ соло-розробник + агенти не мають «спринт-ємності», яку є сенс планувати
  датами: пропускна здатність визначається увагою yurii на гейтах. Порядок усередині треку
  задає черга; пріоритет між треками коригують ритми (рішення 2). Kanban поза репо ламає
  принцип «документація = код» (CLAUDE.md §2.8) і не версіонується разом із промптами.
  Історія фаз не губиться — вона у `docs/13` і в архів-таблиці нового 02.
- _Наслідки:_ (+) у кожному напрямі завжди видно «що наступне», і це відразу готова одиниця
  запуску (промпт); нема ілюзії дат. (−) нема прогнозів термінів (свідомо); черги треба
  підтримувати актуальними — це робота ритмів.

**2. Ритми: неділя — digest, 1-е число місяця — huddle.**

- _Альтернативи:_ ad-hoc («перевіряю, коли є час»); щоденний стендап-режим (overkill для solo).
- _Вибір:_ (a) **неділя** — digest (cron 18:00 Europe/Kyiv, ADR-032 §5) → розбір ≤15 хв:
  **кожен пункт digest'а стає GitHub-issue АБО явно позначається «accepted noise»** записом у
  digest-треді Discord; (b) **1-е число місяця** — huddle за промптом A4 (`docs/15`): вхід =
  останні 4 digest'и + поточний `docs/02`; вихід = корекція черг треків (переставити, додати,
  зняти пункти).
- _Обґрунтування:_ digest уже існує і безкоштовний (ADR-032); правило «issue або accepted
  noise» — зафіксований механізм самовдосконалення (`docs/14` §4.4), тепер воно отримує
  фіксований слот уваги. Huddle перетворює місячні дані на рішення про черги — це і є
  «переплановування» замість спринт-планування.
- _Наслідки:_ (+) розвиток керується даними; вартість уваги фіксована (15 хв/тиждень + один
  huddle/міс). (−) дисципліна лежить на yurii; порожній digest (нема трафіку) не скасовує
  huddle — відсутність даних теж сигнал.

**3. Ролі агентів + маршрутизація моделей.**

- _Альтернативи:_ одна сесія «на все» (немає незалежного рев'ю, дорога модель на дешевих
  задачах); повністю ручна розробка.
- _Вибір:_ чотири ролі (таблиця маршрутизації — `docs/15` §0):
  **Архітектор** — найсильніша reasoning-модель (Opus/Fable): master-runs, ADR, тріаж, huddle;
  **Будівельник** — Sonnet: імплементація за затвердженим планом/ADR;
  **Рев'юер** — незалежне рев'ю AI-PR (вердикт проти плану й інваріантів §7/§13): ЗАРАЗ — сильна
  Claude-модель в окремій сесії (не та, що писала код);
  **Розвідник** — дешеві моделі (Haiku/чат), read-only: інвентаризації, аудити, чернетки,
  підсумовування digest.
- _Gemini CLI як Рев'юер/Розвідник — УМОВНА опція, статус `pending`:_ yurii ще не перевірив
  доступ CLI за своєю підпискою. **Тригер активації:** yurii підтверджує робочий CLI-доступ →
  пілот на одному AI-PR (Gemini-рев'ю паралельно з Claude-Рев'юером, порівняння вердиктів) →
  за результатом — окремий рядок у `docs/15` §0. До того — БЕЗ інтеграції.
- _Обґрунтування:_ маршрутизація за складністю вже довела себе (docs/15 §0, рівні A/B/C);
  незалежний Рев'юер — захист від self-review blind spots (стадія review у
  `master-ai-bugfix-flow`); крос-вендорне рев'ю цінне саме незалежністю, але не раніше
  перевіреного доступу.
- _Наслідки:_ (+) дешеві задачі не палять дорогу модель; рев'ю відокремлене від імплементації.
  (−) оркестрація (запуск run'ів) поки ручна — на yurii, до запуску ai-bugfix-flow.

**4. «Черга yurii» — один закріплений issue для ВСІХ мануальних кроків.**

- _Альтернативи:_ чеклисти в кожному PR (статус-кво, що призвів до загубленої міграції #69);
  окремий docs-файл (не видно з головної репо, зайвий commit-шум).
- _Вибір:_ один **закріплений (pinned) GitHub-issue «Черга yurii»** — єдине місце всіх
  мануальних кроків. Протокол: кожен run ЗОБОВ'ЯЗАНИЙ додати свої мануальні пункти окремою
  секцією з датою і посиланням на джерело (PR/run); yurii викреслює виконане (чекбокси).
  PR-чеклисти мануальних кроків лишаються ДУБЛЕМ для контексту — джерело істини одне: issue.
- _Обґрунтування:_ урок #69 — крок, описаний лише у PR-чеклисті, загубився, тиждень простою.
  Pinned issue видно на головній сторінці репо, він підтримує чекбокси, історію правок і
  нічого не коштує.
- _Наслідки:_ (+) одна точка «що потрібно від мене»; run'и мають явний обов'язок оновлення.
  (−) актуальність issue — обов'язок кожного run'у; перевірка — недільний ритм.

**5. Гейти незмінні.**

- _Альтернативи:_ авто-merge зелених AI-PR; делегування merge агентам за замовчуванням.
- _Вибір:_ merge будь-якого PR — **лише yurii**; винятки — разовою явною згодою у конкретному
  run'і з явним scope (патерн Run 5: «merge делеговано ЛИШЕ для PR цього run'у при зеленому
  CI»). CLAUDE.md §1-12, drizzle-міграції, infra — за наявними правилами §6, не делегуються.
  Оцінка готового продукту (acceptance) — теж yurii.
- _Обґрунтування:_ гейт — головний захист від runaway-агентів і компаундингу помилок
  (`docs/16` §9 лишається чинним без змін); разовий виняток — контрольований і trace-ований
  у тексті промпту run'у.
- _Наслідки:_ (+) людина завжди в контурі. (−) throughput обмежений увагою yurii —
  свідомо: якість над швидкістю.

**Наслідки (загальні):**

- `docs/02_ROADMAP.md` повністю переписано у форматі треків (цей PR); фазова таблиця
  `docs/14` §6 отримує історичний статус; `docs/15` §0 — ролі замість рівнів A/B/C;
  CLAUDE.md §11 «Цикл розробки» замінюється циклом 2.0 — **ручна правка yurii** (готовий
  текст у PR description; §6 забороняє агенту правити CLAUDE.md).
- Одиниця progress-log не змінюється: закритий пункт черги = запис у `docs/13` + ротація
  CLAUDE.md §13 (механіка «завершення фази» переживає перейменування у «завершення пункту
  черги»).
- ADR-034 (Process layer, run A3) і ADR-035 (AI bugfix flow) **зарезервовані** за майбутніми
  run'ами — розрив нумерації в індексі свідомий.

**Альтернативи (загальні):** GitHub Projects / Linear як планер — відхилено (поза репо, не
версіонується, +1 інструмент для solo); зберегти фази і дописувати 3.7, 3.8… — відхилено
(нумерація вже роздвоїлась і потребувала легенду; дати не мають сенсу при agent-driven
розробці, де ємність = увага на гейтах).

---

## ADR-037: i18n-архітектура — власні словники + `/en/*` routing (Etap A)

**Статус:** Accepted (2026-07-20, Master Run 8 Стадія 2)

**Контекст:** Телеметрія (Umami) показала ~50% англомовних відвідувачів — EN-версія
обґрунтована даними, закриває `docs/00_OPEN_QUESTIONS.md` OQ-19. Прецедент уже є:
`/privacy` + `/privacy/en`, `/terms` + `/terms/en` — повне дублювання JSX без
i18n-фреймворку (`docs/promts/inputs/i18n-inventory.md` зона 4). Стадія 1 (agy-скани,
верифіковано 0/32 розбіжностей) інвентаризувала точний обсяг UA-текстів на 3 інших
поверхнях: лендінг/about/soon, каталог+картки+footer, export-flow UI+OG. Явна межа
цього ADR: **студії** (`*-studio.tsx` × 6, AutoForm `.describe()`-лейбли, Zod
error-messages, PDF-генерація worker'а) — поза scope, мігрують на Template Registry
(Run 7, `docs/promts/master-registry-track.md`) і будуть локалізовані етапом B.

**Рішення** (6 складових, кожна — альтернатива / вибір / обґрунтування / наслідки):

**1. Механізм — власні типізовані словники, не `next-intl`, не `paraglide`.**

- _Альтернативи:_ `next-intl` (research agy: підтримує Next.js 15 App Router + RSC,
  але потребує middleware для routing, `localePrefix` стратегії мають відомі
  edge-case'и з client/server-state конфліктами, canary/Turbopack нюанси —
  `docs/promts/inputs/i18n-research.md`); `paraglide` (build-tool-heavy, compile-step,
  найменше підходить для розміру проєкту).
- _Вибір:_ власні словники — `apps/web/src/i18n/dictionaries.ts`: `const uk = {...} as const`
  - `const en: typeof uk = {...}` — TS-компілятор сам гарантує паритет ключів
    (типізованіше за окремі `.json`-файли + ручний type-файл, які пропонував
    промпт-чернетка — свідоме відхилення формату на користь сильнішої гарантії).
- _Обґрунтування:_ CLAUDE.md §2 («Type-safe end-to-end», «Junior-friendly. Без
  розумних абстракцій без потреби») і §6 (default — без нових top-level залежностей).
  Проєкт малий (6 сторінок у Etap A), MS21-ресурси не виправдовують middleware +
  бандл `next-intl`. Прецедент `/privacy`+`/en` уже довів, що ручний підхід працює;
  словники — той самий підхід, узагальнений і типобезпечний (замість повного
  дублювання JSX — спільні React-компоненти, параметризовані `locale`+`dict`).
- _Наслідки:_ (+) нуль нових залежностей; компілятор ловить розсинхрон ключів; той
  самий React-компонент рендерить обидві локалі. (−) нема ICU-плюралізації/форматування
  «з коробки» (не потрібно — тексти короткі, без множини); ручна підтримка словника
  при рості кількості сторінок (прийнятний trade-off — Etap B після Registry
  переоцінить, якщо обсяг зросте).

**2. Routing — uk без префікса (дефолт, наявні URL незмінні) + `/en/*` prefix.**

- _Альтернативи:_ дзеркальний `<route>/en` суфікс (як `/privacy/en` — наявний
  прецедент, але несистемний для 6+ нових сторінок); єдиний `[locale]`-сегмент для
  ВСІХ маршрутів (означало б перенести `/`, `/about` тощо під `/uk/*`, ламаючи наявні
  URL і 15+ e2e-специфікацій).
- _Вибір:_ нові EN-дзеркала — `/en`, `/en/about`, `/en/soon`, `/en/templates`,
  `/en/templates/[slug]`, `/en/products/[slug]` (App Router: окремі файли
  `app/en/**/page.tsx`, перевикористовують спільні presentational-компоненти з
  `locale="en"`). Наявний `/privacy/en`+`/terms/en` **лишається як є** (інша схема,
  не мігрується цим ADR — legal-сторінки поза Etap A scope).
- _Обґрунтування:_ «uk-URL незмінні» — жорстка вимога промпту (наявні e2e не
  чіпаються). Префіксний `/en/*` — стандартний, симетричний патерн: перемикач
  обчислює цільовий шлях universally (`/en` + pathname.replace(/^\/en/, "")),
  без hardcoded route-table.
- _Наслідки:_ (+) 0 змін у наявних URL/e2e; передбачуваний патерн для майбутніх
  сторінок. (−) непослідовність із `/privacy/en` (свідома, задокументована,
  міграція privacy/terms на `/en/privacy` — окремий майбутній PR, не зараз);
  перемикач може вести на 404 для НЕ-дзеркалених сторінок (`/f/[exportId]`,
  `/styleguide`, `/privacy`) — прийнятний Etap A-ліміт, Footer глобальний.

**3. Визначення мови — Accept-Language on first-visit (вузький matcher) + функціональна cookie + ручний перемикач.**

- _Альтернативи:_ лише ручний перемикач (без auto-detect — гірший perceived-quality
  для EN-переважної половини трафіку); geo-IP (нова залежність/сервіс, не потрібна).
- _Вибір:_ `apps/web/src/middleware.ts`, **matcher обмежений 6 дзеркаленими uk-шляхами**
  (`/`, `/about`, `/soon`, `/templates`, `/templates/:slug`, `/products/:slug`) — НЕ
  глобальний. Якщо cookie `hart_locale` відсутня і перший preferred-language з
  `Accept-Language` починається з `en` (не `uk`) → редірект на `/en`-дзеркало +
  `Set-Cookie hart_locale=en` (functional, `SameSite=Lax`, 1 рік, без PII). Якщо
  редіректу не сталося — `hart_locale=uk` теж ставиться (щоб не парсити header на
  кожному request). Перемикач (LocaleSwitcher, Footer, 44px tap-target) завжди
  перезаписує cookie на явний вибір користувача.
- _Обґрунтування:_ **Критичний ризик CI** — Playwright headless Chromium без
  `use.locale` шле `Accept-Language` системи раннера (типово `en-US` на GH Actions
  Ubuntu) → auto-redirect зламав би ВСІ наявні uk e2e-тести. Мітигація: `playwright.config.ts`
  `use.locale = "uk-UA"` (явний дефолт для контексту тестів — узгоджено з «наявні e2e
  зелені»); окремий новий e2e-файл перевіряє редірект через `test.use({ locale: "en-US" })`.
  Вузький matcher (не весь сайт) обмежує blast radius авто-редіректу лише
  дзеркаленими сторінками.
- _Наслідки:_ (+) EN-трафік з першого візиту бачить рідну мову; cookie
  функціональна (не аналітична) — узгоджується з ADR-006/ADR-032 GDPR-принципами.
  (−) middleware — нова інфраструктурна точка (малий, чистий файл, без залежностей);
  `docs/09_STAGING_PREFLIGHT.md`/`docs/08_DEPLOYMENT.md` не потребують змін (middleware
  запускається в тому самому Next.js runtime). `/privacy` §2 «Без трекінг-cookies»
  оновлюється текстом про цю ЄДИНУ функціональну cookie (не аналітичну, не трекінг).

**4. Словники — `apps/web/src/i18n/dictionaries.ts`, типізовані ключі, namespace на зону.**

- _Альтернативи:_ окремий файл-словник на кожну зону (`home.ts`, `about.ts`,
  `catalog.ts`, ...) замість одного `dictionaries.ts` з namespace-ами всередині
  — менше git-конфліктів при паралельній розробці кількох зон, але важче
  звірити повноту проти `i18n-inventory.md` (10+ файлів замість одного місця
  правди); дублювати DB-контент (`template.nameUk`/`nameEn`) у словнику теж
  (замість читання напряму з API) — відхилено, порушує «одне джерело істини
  для даних» (CLAUDE.md §3), API вже повертає обидва варіанти напряму.
- _Вибір:_ один файл, namespace-и `common` (footer/site-links/switcher), `home`,
  `about`, `soon`, `catalog` (+ `templateCard`/`productCard`), `templateDetail`,
  `productDetail`, `exportFlow`, `og`. DB-контент (`template.nameUk`/`nameEn`,
  `descriptionUk`/`descriptionEn`) — читається напряму з API-відповіді за
  `locale`, НЕ дублюється у словнику (single source of truth — `packages/db`).
  `products.name`/`description` — **не має EN-поля** (перевірено schema.ts): на
  `/en/products/[slug]` показується те саме UA-значення для DB-контенту, тоді як
  вся статична обгортка (breadcrumb, «not found», підписи) — англійською. Явно
  занесено в «Опитування» PR — чи додавати `name_en`/`description_en` міграцією
  (CLAUDE.md §6 — потребує explicit-інструкції, якої в цьому run'і нема).
- _Обґрунтування:_ uk-значення словника мають бути **byte-identical** до наявних
  hardcoded рядків (вимога «uk-URL незмінні» = і візуально незмінні, не лише
  URL-шлях) — перевіряється тим, що наявні e2e (що асертують конкретний UA-текст)
  лишаються зеленими без модифікацій.
- _Наслідки:_ (+) один файл — легко звірити повноту проти
  `docs/promts/inputs/i18n-inventory.md`; типізовані ключі ловлять typo на
  compile-time. (−) файл виросте при Etap B (студії) — прийнятно, namespace
  ізолює зростання.

**5. Межа Etap A / Etap B — студії залишаються НЕТОРКНУТИМИ.**

- _Альтернативи:_ частково перекласти студії (лише текстові JSX-лейбли, БЕЗ
  AutoForm `.describe()`-метаданих і Zod-повідомлень) — відхилено: розмиває
  чіткий handoff-пункт для Registry-міграції (Run 7), і `.describe()`
  метадані все одно підуть під нову `TemplateDefinition`-схему, тобто
  часткова робота була б викинута; НЕ готувати dictionary-ready `locale`-prop
  на `export-button.tsx`/`post-export-donate-nudge.tsx` зараз (повністю
  відкласти до Etap B) — відхилено, бо ці 2 компоненти генеричні (не
  прив'язані до конкретного шаблону), підготовка backward-compatible
  optional-prop практично безкоштовна і закриває частину майбутньої роботи
  заздалегідь.
- _Вибір:_ `*-studio.tsx` × 6 (AutoForm-лейбли, Zod-повідомлення) — **нуль diff**.
  `template-studio.tsx` (спільний shell, НЕ per-template) і `export-button.tsx` /
  `post-export-donate-nudge.tsx` отримують опційний `locale` prop (default `"uk"`,
  **backward-compatible**, наявні call-сайти в 6 студіях НЕ оновлюються цим PR) —
  дає dictionary-ready компонент, готовий для Etap B, але на живих `/en/templates/[slug]`
  і `/en/products/[slug]` кнопка експорту сьогодні лишається українською (студія її
  рендерить із дефолтним locale). Цей компроміс — свідомий, задокументований у PR.
- _Обґрунтування:_ промпт явно забороняє чіпати студії («СВІДОМО не чіпає
  студії/форми/валідацію — вони підуть етапом B ПІСЛЯ Registry»); `template-studio.tsx`
  і `export-button.tsx` — генерична інфраструктура без AutoForm/`.describe()`/Zod
  прив'язки до конкретного шаблону, тому підготовка (без wiring) не суперечить
  межі.
- _Наслідки:_ (+) нуль ризику для Registry-міграції (Run 7); чіткий handoff-пункт
  для Etap B. (−) `/en/templates/[slug]` і `/en/products/[slug]` — **частково
  перекладені сторінки** (header/breadcrumb EN, сама студія всередині — UA) — це
  свідомий, задокументований стан Etap A, не баг. **Consequence для Run 7:**
  `TemplateDefinition` (ADR-033) має передбачити локалізовані label-метадані —
  занести окремим пунктом у наступний запуск `master-registry-track.md`.

**6. Мова PDF/креслень — відкладено, поза Etap A.**

- _Альтернативи:_ локалізувати підписи PDF зараз через мовний параметр у
  CadQuery-генераторі — відхилено: суттєва робота у Python-worker'і, вимагає
  нових снапшот-тестів і ризикує детермінізмом байт-у-байт (CLAUDE.md §2.4),
  непропорційно для Etap A; client-side SVG/overlay поверх готового PDF
  (накласти перекладений текст без зміни worker'а) — відхилено: крихко,
  підписи стають нередагованими шаром поверх растру, і фактичний вміст файлу
  (той, що йде на верстат) лишається українським — оверлей був би оманливим
  для користувача.
- _Вибір:_ PDF-генерація (`workers/cad/flatcraft_cad/export/pdf.py`) лишається
  українською. Не входить у жоден Etap цього ADR.
- _Обґрунтування:_ ISO/EN ISO 7200-креслення (CLAUDE.md §7) значною мірою
  мовонезалежні (символи, позначення); зміна мови PDF — Python-worker, окрема
  вертикаль з власними снапшот-тестами (детермінізм — інваріант CLAUDE.md §2.4),
  не рядкова заміна.
- _Наслідки:_ (−) EN-користувач після export отримує UA-підписану PDF — відомий
  gap, **«Опитування» PR**: чи потрібен окремий тікет у T2/T4 (`docs/02_ROADMAP.md`)
  для EN PDF після Registry (де снапшот-інфраструктура вже буде змінюватись).

**7. hreflang/alternates + sitemap — follow-up (2026-07-18, Стадія 3 зауваження зони D).**

- _Контекст:_ Незалежне рев'ю `agy` (Master Run 8, Стадія 3, PR #80) виявило,
  що `i18n-inventory.md` (зона 4) явно вказував прогалину — «hreflang/alternates
  відсутні, ADR-037 має закрити» — а сам ADR цього не робив. Follow-up PR
  закриває gap без зміни рішень 1-6.
- _Альтернативи:_ покластися лише на `sitemap.xml` без `<link rel="alternate">`
  у кожній сторінці — відхилено, Google явно рекомендує обидва канали
  одночасно (сторінка — основний сигнал, sitemap — доповнення для великих
  сайтів); окремий `[locale]`-route-group з централізованою alternates-логікою
  замість per-page `metadata`/`generateMetadata` — відхилено, означало б
  переписати routing (рішення 2 вже відхилило єдиний `[locale]`-сегмент).
- _Вибір:_ `apps/web/src/i18n/hreflang.ts` — `localeAlternates(locale, ukPath,
enPath)` (загальний випадок, напр. `/privacy`+`/privacy/en`) і
  `mirroredAlternates(locale, ukPath)` (зручний варіант для `/en/*`-дзеркал,
  EN-шлях виводиться через наявний `toEnPath`). Кожна з 16 локалізованих
  сторінок (8 uk + 8 en: `/`, `/about`, `/soon`, `/templates`,
  `/templates/[slug]`, `/products/[slug]`, `/privacy`, `/terms`) отримує
  `alternates: {canonical, languages: {uk, en, "x-default": uk}}`. Новий
  `app/sitemap.ts` (Next.js convention) додає ті самі reciprocal alternates
  на рівні sitemap-запису для кожного uk/en URL (включно з динамічними
  `/templates/[slug]`, `/products/[slug]` — slug з `fetchPublishedTemplates`/
  `fetchPublishedProducts`). `/f/[exportId]` — свідомо ПОЗА scope (private
  noindex QR-посилання, ADR-032 §feedback, не публічний контент).
- _Обґрунтування:_ `x-default` = uk-шлях — узгоджено з `DEFAULT_LOCALE` (§2);
  `canonical` — сама поточна локаль (кожна мовна версія канонічна сама на
  себе, hreflang зв'язує еквіваленти, не позначає дублікат).
- _Наслідки:_ (+) коректний SEO-сигнал для двомовного контенту, замикає
  прогалину з inventory. (−) 16 файлів торкнуто (лише додавання одного поля
  `alternates` у наявний `metadata`-об'єкт, без структурних змін); sitemap
  робить 2 API-виклики (templates/products) при кожному crawl-запиті
  `/sitemap.xml` (Next кешує за замовчуванням, окремого TTL не додавали —
  прийнятний trade-off для розміру каталогу MVP).

**Наслідки (загальні):**

- Нові файли: `apps/web/src/i18n/{locale.ts,dictionaries.ts,routes.ts}`,
  `apps/web/src/middleware.ts`, `apps/web/src/components/locale-switcher.tsx`,
  6 нових `app/en/**/page.tsx`, `app/en/opengraph-image.tsx`.
  Існуючі uk-файли рефакторяться на споживання словника (текст byte-identical).
- `playwright.config.ts` отримує `use.locale = "uk-UA"` — захист наявних e2e від
  Accept-Language-редіректу; новий тест перевіряє EN-гілку явним context-override.
- `/privacy` + `/privacy/en` §2 оновлюються (згадка функціональної `hart_locale`
  cookie).
- Registry-контракт (ADR-033/Run 7) отримує consequence-пункт про локалізовані
  label-метадані в `TemplateDefinition`.

**Альтернативи (для рішення загалом):** повна i18n одним PR разом зі студіями —
відхилено (промпт явно розділяє Etap A/B, ризик потонути в Registry-міграції
одночасно з i18n); відкласти EN до ПІСЛЯ Registry повністю — відхилено (телеметрія
вже показує попит, `/privacy`-прецедент і Registry — незалежні вертикалі).

---

_Шаблон нової ADR:_

```
## ADR-NNN: <короткий заголовок>

**Статус:** Proposed | Accepted | Deprecated | Superseded by ADR-MMM (дата)

**Контекст:** Чому виникло питання, які обмеження.

**Рішення:** Що робимо і чому саме так.

**Наслідки:** Плюси, мінуси, що це блокує/відкриває.

**Альтернативи:** Що ще розглядали і чому відкинули.
```
