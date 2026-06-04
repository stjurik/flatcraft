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

_Шаблон нової ADR:_

```
## ADR-NNN: <короткий заголовок>

**Статус:** Proposed | Accepted | Deprecated | Superseded by ADR-MMM (дата)

**Контекст:** Чому виникло питання, які обмеження.

**Рішення:** Що робимо і чому саме так.

**Наслідки:** Плюси, мінуси, що це блокує/відкриває.

**Альтернативи:** Що ще розглядали і чому відкинули.
```
