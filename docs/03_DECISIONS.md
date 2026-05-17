# 03. Architecture Decision Records (ADR)

> Кожне нетривіальне технічне рішення фіксуємо тут. Коротко: контекст → рішення → наслідки → альтернативи. Якщо рішення скасовано — статус `Superseded by ADR-N`.

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

_Шаблон нової ADR:_

```
## ADR-NNN: <короткий заголовок>

**Статус:** Proposed | Accepted | Deprecated | Superseded by ADR-MMM (дата)

**Контекст:** Чому виникло питання, які обмеження.

**Рішення:** Що робимо і чому саме так.

**Наслідки:** Плюси, мінуси, що це блокує/відкриває.

**Альтернативи:** Що ще розглядали і чому відкинули.
```
