# 02. Roadmap — flatcraft

> Roadmap — це список **спринтів по 1–2 тижні**. Кожен спринт = одна користувацька цінність + критерії приймання + тести.
> Принципи: TDD, спочатку валідатор → потім UI, спочатку 1 шаблон end-to-end → потім решта.

## Стадії

| Стадія                          | Терміни (соло-розробник, junior + Claude Code) | Мета                                                                    |
| ------------------------------- | ---------------------------------------------- | ----------------------------------------------------------------------- |
| **Phase 0. Setup**              | 1 тиждень                                      | Локальне середовище, CI, перший «hello world» end-to-end                |
| **Phase 1. CAD core**           | 3 тижні                                        | Валідатор гибки + розгортка + експорт DXF одного шаблону (L-кронштейн)  |
| **Phase 2. UX MVP**             | 3 тижні                                        | 3D-редактор + форма параметрів + експорт DXF/PDF + 5 шаблонів           |
| **Phase 3. Auth & Limits**      | 2 тижні                                        | Реєстрація, лічильник 10 безкоштовних, гість-режим (без експорту)       |
| **Phase 4. Donations**          | 1 тиждень                                      | Monobank Banka link + ручне підтвердження + продовження ліміту          |
| **Phase 5. Hardening + Launch** | 2 тижні                                        | GDPR, Privacy Policy, Sentry, prod-deploy на Mirohost Cloud, домен, SSL |
| **Total**                       | ≈ 12 тижнів                                    | Public MVP                                                              |

Після MVP — окремий roadmap у `docs/02_ROADMAP_v1.md` (поки не створюємо).

---

## Phase 0. Setup (1 тиждень)

**Definition of Done:** `pnpm dev` піднімає весь стек локально. CI на GitHub Actions проганяє lint+test на push.

- [x] **0.1.** Скелет монорепо (`apps/web`, `apps/api`, `workers/cad`, `packages/*`) — 2026-05-15
- [x] **0.2.** `docker-compose.yml`: Postgres + Redis + MinIO + Mailpit (web/api/cad — локально) — 2026-05-16
- [x] **0.3.** Drizzle init: 12 таблиць згідно docs/05, перша міграція, seed (7 матеріалів × 10 товщин + 5 шаблонів-placeholder) — 2026-05-16
- [x] **0.4.** Fastify hello-world з health-check (`/health`), pino logger з PII-redact, Zod-валідація env, fastify-type-provider-zod — 2026-05-16
- [x] **0.5.** Next.js 15 App Router + Tailwind, R3F куб (`dynamic ssr:false`), Playwright e2e — 2026-05-16
- [ ] **0.6.** GitHub Actions: lint + typecheck + test + build для всіх workspace
- [ ] **0.7.** Pre-commit hook (lefthook): lint + typecheck + test
- [ ] **0.8.** README.md з інструкцією «як запустити локально за 5 хвилин»

**Тести:** smoke-test, що health-check API повертає 200, web відкривається на `localhost:3000`.

---

## Phase 1. CAD core (3 тижні)

**Definition of Done:** з командного рядка можна запустити `cad-worker` із параметрами L-кронштейна → отримати валідний DXF, який відкривається у LibreCAD.

- [ ] **1.1.** `packages/cad-engine/data/bend-machine-esi.yaml` — завантажити з `docs/07_BEND_MACHINE_SPEC.md`
- [ ] **1.2.** `packages/cad-engine/src/spec.ts` — завантажувач + Zod-схема
- [ ] **1.3.** `packages/cad-engine/src/validators/` — функції `validateBend`, `validateSheet`, `validateHoles` (TDD: тести спочатку)
- [ ] **1.4.** `packages/cad-engine/src/k-factor.ts` — обчислення K за матеріалом + R/S
- [ ] **1.5.** `workers/cad/flatcraft_cad/templates/l_bracket.py` — параметрична модель L-кронштейна на CadQuery
- [ ] **1.6.** `workers/cad/flatcraft_cad/unfold.py` — алгоритм розгортки з K-фактором (тестовий fixture: ручний розрахунок)
- [ ] **1.7.** `workers/cad/flatcraft_cad/export/dxf.py` — експорт у DXF з шарами `LASER_CUT`, `INNER_CUTS`, `BEND_LINES`, `BEND_TEXT`, `DIM`
- [ ] **1.8.** Снепшот-тести: фіксований seed → фіксований DXF byte-output (для регресій)

**Тести:** pytest з фікстурами для 3 розмірів L-кронштейна; перевіряємо, що валідатор кидає правильні помилки на занадто товсту/тонку заготовку, на закороткий полиць, на недозволений радіус.

---

## Phase 2. UX MVP (3 тижні)

**Definition of Done:** користувач відкриває сайт, вибирає шаблон, крутить повзунки, бачить 3D-прев'ю в реальному часі, скачує DXF + PDF.

- [ ] **2.1.** Сторінка `/templates` — каталог шаблонів з прев'юшками
- [ ] **2.2.** Сторінка `/templates/[slug]` — редактор параметрів + 3D-viewport
- [ ] **2.3.** `packages/ui/src/3d-viewport/` — react-three-fiber сцена (orbit controls, zoom, кадрування)
- [ ] **2.4.** `packages/ui/src/parameter-form/` — авто-генерація форми з Zod-схеми шаблону (number inputs, sliders, селектори матеріалу/товщини)
- [ ] **2.5.** Live-валідація з підсвіченням обмежень (червоні поля + tooltip з причиною)
- [ ] **2.6.** Інтеграція OpenCascade.js: оновлення mesh при зміні параметрів (debounce 100мс)
- [ ] **2.7.** Кнопка «Export» → API `/exports` → BullMQ → cad-worker → presigned URL з R2/MinIO
- [ ] **2.8.** Прогрес-індикатор (SSE) поки worker генерує
- [ ] **2.9.** PDF з розгорткою + ізометрією + таблицею гибів + BOM + QR-код (workers/cad/export/pdf.py через ReportLab або WeasyPrint)
- [ ] **2.10.** Решта 4 шаблонів (Z-кронштейн, кутник, полиця, перфо-панель) — кожен як окремий PR

**Тести:** Playwright e2e — відкрити сторінку → змінити параметр → побачити оновлення 3D → клікнути Export → отримати DXF.

---

## Phase 3. Auth & Limits (2 тижні)

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

## Phase 4. Donations (1 тиждень)

**Definition of Done:** після ліміту користувач бачить кнопку «Розблокувати на місяць → 200 грн на ЗСУ», клікає → переходить на банку Monobank → завантажує квитанцію → адмін підтверджує → ліміт продовжено.

- [ ] **4.1.** Сторінка `/unlock` з кнопками «Monobank Banka» (link), «UNITED24» (link), «USDT» (адреса гаманця)
- [ ] **4.2.** Форма «я задонатив» (load receipt + email + amount) → `donation_claims` table
- [ ] **4.3.** Адмін-сторінка для верифікації claim (одна кнопка «Approve» → продовжує quota на 30 днів)
- [ ] **4.4.** Email-сповіщення про підтвердження (через Postmark або Resend)
- [ ] **4.5.** _v1.1:_ Monobank Acquiring webhook для автопідтвердження

**Тести:** unit на логіку продовження ліміту (timezone-safe, на 30 днів від моменту підтвердження).

---

## Phase 5. Hardening + Launch (2 тижні)

**Definition of Done:** домен `flatcraft.io` (або обраний), SSL через Cloudflare, GDPR-compliance, Privacy/ToS опубліковані, Sentry прокладено, перші 10 живих юзерів.

- [ ] **5.1.** Sentry SDK у web + api + worker; `beforeSend` фільтр PII
- [ ] **5.2.** Plausible/Umami self-hosted або хмарний акаунт
- [ ] **5.3.** Cookie banner (мінімальний, GDPR-сумісний — наш власний компонент)
- [ ] **5.4.** Privacy Policy + ToS + Cookie Policy (UA + EN, шаблон у `legal/`)
- [ ] **5.5.** GDPR Data Subject Request endpoint: `/account/export-data`, `/account/delete`
- [ ] **5.6.** Створити сервер Mirohost Cloud (MS21) у панелі + Cloudflare DNS + R2 bucket; задокументувати кроки в `infra/README.md`
- [ ] **5.7.** Ansible-плейбук для налаштування сервера (Docker, docker-compose, automatic backups, firewall, swap)
- [ ] **5.8.** Backup-скрипт: щоденний `pg_dump` → R2 (зашифрований age)
- [ ] **5.9.** Staging environment (окремий Cloud-сервер або Docker namespace на тому ж)
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
