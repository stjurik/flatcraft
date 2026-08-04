# 02. Roadmap — hart.crimea.ua (модель 2.0: треки + ритми)

> **Призначення файлу:** карта черг розробки. П'ять треків, кожен — мета → черга
> «наступний PR/run» → гейт yurii. Без дат і спринтів: пропускна здатність визначається
> увагою yurii на гейтах, пріоритети коригують ритми (див. §Ритми). Модель — **ADR-036**.
>
> **Історія** (завершені фази, повні описи): `docs/13_PROGRESS_LOG.md`.
> **Стратегія** (діагноз, рекомендації registry/process/feedback): `docs/14_ARCHITECTURE_EVOLUTION.md`.
> Цикл: трек → перший пункт черги → run/PR (промпт з `docs/promts/*` або `docs/15`) →
> гейт yurii (merge + acceptance) → запис у `docs/13` → ритми коригують черги.

---

## Треки

### T1. Стабілізація — конвеєр «дані → issue → ai-fix»

**Мета:** кожен сигнал телеметрії (digest, Sentry, виробничий фідбек) перетворюється на
issue і виправлення без локальної сесії; дрібний борг не накопичується.

**Черга:**

1. ✅ **Конвеєр побудовано і пройшов acceptance** (закрито 2026-08-03).
   `docs/promts/master-ai-bugfix-flow.md` дав ADR-035, workflows
   `ai-triage`/`ai-fix`, issue-форми, `docs/17`. Наскрізний прохід — issue #84
   → тріаж у CI → `ai-approved` → Будівельник у CI → незалежне рев'ю `agy` →
   merge PR **#97** (`d4c81be`) → staging. Ціна: **5 падінь тріажу і 4
   спростовані гіпотези** (справжня причина — недійсне значення OAuth-секрету).
   Деталі — `docs/13_PROGRESS_LOG.md` «Master Run 10+11», ADR-035 §Фактичний
   результат. Супутні PR: #86, #94, #95 (terminal-state guard,
   `show_full_output` прибрано).
2. **Постачання сигналу «digest/Sentry → issue»** — лишається ручним ритуалом
   (рішення 2026-08-03, Опитування Master Run 12): недільний digest ≤15 хв,
   кожен пункт → issue АБО «accepted noise» у треді; Sentry — очима. Причина:
   ~10 користувачів/день, обсяг сигналу малий, автоматика постачання коштує
   більше, ніж економить, і додає клас шуму до того, як є що фільтрувати.
   **Тригер перегляду:** digest стабільно дає >5 пунктів АБО аудиторія росте
   кратно → повернутись до варіанта «Sentry webhook → issue-чернетка».
3. ✅ **TD-01 — закрито** (перевірено 2026-08-03): усі дії вже на актуальних
   мажорах — `actions/checkout@v5` ×15, `actions/setup-node@v5` ×7,
   `pnpm/action-setup@v5` ×7, `actions/setup-python@v6` ×2,
   `upload-artifact@v6`, `docker/*` v4-v7, `astral-sh/setup-uv@v7`. Жодної дії
   на Node 20 не лишилось; дедлайни 16.06.2026 і 16.09.2026 не загрожують.
   Бампи розійшлись по різних PR, пункт лишався невикресленим.
4. **`NODE_VERSION` 20.11.0 → 22 або 24** (новий пункт, виділено з TD-01).
   Це версія Node для **збірки проєкту** (`ci.yml`, `env.NODE_VERSION`), не для
   runtime дій — TD-01 її не покривав. Node 20 досяг EOL **30.04.2026**, тобто
   рантайм збірки лишився без security-патчів. Цілі: **22** (EOL 04.2027,
   мінімальний ризик) або **24** (EOL 04.2028, довший горизонт). Робити разом
   із наступним оновленням залежностей, не окремо.
5. **TD-02** (guard проти stale `*.js` поряд з `.ts` у `packages/*/src/`;
   див. §Tech-debt). Станом на 2026-08-03 `.js` у `src/` немає ні в git, ні
   локально — але й guard'а немає, тобто пастка відтворювана.
   **Примітка до майбутнього issue:** переважний scope — скрипт
   `tools/scripts/*.sh` + тест рівня shell (за зразком
   `check-forbidden-paths.sh` + `.test.sh`), а НЕ vitest: Будівельник у CI не
   має `node_modules` і прогнати vitest не зможе (`docs/17` §9).

**Гейт yurii:** лейбл `ai-approved` на тріажені плани; merge кожного fix-PR після
ai-review-вердикту (`docs/promts/ai-review-local.md`).

### T2. Registry — «специфікація → нова Деталь» (ADR-033)

**Мета:** новий шаблон = 1 TS-модуль + 1 Python-модуль + снапшоти; нуль правок у
`apps/web`/`apps/api`; додавання Деталі — відтворюваний конвеєр за специфікацією.

**Черга:**

1. **Запуск `docs/promts/master-registry-track.md`** (Master Run 7): Етап 1 —
   `packages/templates` + conformance-suite (PR 2 за `docs/12` §1-3, §5) → Етап 2 —
   міграція 6 шаблонів **по одному PR** (порядок: `perforated_panel` → `l_bracket` →
   `z_bracket` → `corner_angle` → `wall_shelf` → `enclosed_shelf`) → видалення
   per-template файлів → Етап 3 — конвеєр нової Деталі (run створить docs/18-специфікацію
   та переюзабельний промпт new-part-run — цих файлів ще нема).
   _Умова старту:_ **після першого тижня телеметрії** (digest-acceptance, T3 п.1) —
   дані можуть змінити порядок міграції шаблонів.
2. **Дві нові Деталі за специфікаціями yurii** (окремий майбутній run `new-part-run` ×2) —
   acceptance всієї registry-системи.

**Гейт yurii:** ADR-033 `Proposed → Accepted` при merge плану Run 7; заповнені
docs/18-специфікації двох Деталей; merge кожного етапу.

### T3. Launch — публічний soft-launch

**Мета:** з staging-бети — у публічний продукт з виміряним першим тижнем.

**Черга:**

1. **Digest-acceptance — неділя 2026-07-19, 18:00 Europe/Kyiv**: перший автоматичний
   digest у Discord (перевірка формату `docs/11` §9 + перше застосування правила
   «issue або accepted noise»).
2. **Go-live PR за `docs/08_DEPLOYMENT.md` §8** (go-live checklist: prod-домен, WAF,
   рішення по BETA-watermark, smoke-тести) — закриває колишній пункт Phase 5.10.
3. **KPI-тиждень**: перший тиждень публічного трафіку → звірка з §KPI нижче у
   найближчому digest/huddle.
4. **Юрист для `/privacy` + `/terms`**: рев'ю draft-текстів (зараз обидві сторінки з
   банером «Драфт», колишній пункт Phase 5.4) → зняття draft-банера.

**Гейт yurii:** рішення go-live; контакт з юристом; оцінка KPI-тижня.

### T4. Еволюція платформи — process layer і новий процес

**Мета:** 3D-друк і мехобробка додаються як плагіни-вертикалі, не форки (стратегія
`docs/14` §3). Обидва пункти — **ПІСЛЯ T2** (registry — база для process layer).

**Черга:**

1. **Run A3** (`docs/15_LLM_PROMPTS.md` §A3, docs-only gate) → ADR-034 «Manufacturing
   process layer»: ієрархія Process → Template → Product → Draft → Export → Artifact →
   Feedback; artifacts як список `{kind, mime, r2_key}`; `templates.process_slug`.
2. **FDM-друк v1.2** — перший новий процес (2-3 шаблони, STL/3MF + PDF-паспорт) —
   після прийняття ADR-034.

**Гейт yurii:** merge ADR-034; рішення про старт v1.2.

### T5. Інфраструктура — відкриті рішення

**Мета:** зняти два відкриті інфраструктурні рішення даними, не інтуїцією.
_(Джерело обох пунктів — аналіз 2026-07-14, сесія архітектора поза репо; висновки
переносяться в ADR при прийнятті. Цим run'ом рішення НЕ приймаються — ADR-036.)_

**Черга:**

1. **Рішення repo-visibility**: варіанти — public+MIT (статус-кво, CLAUDE.md §2.6) /
   **★private** (рекомендація аналізу 2026-07-14) / private з подальшим re-open після
   launch. Зачіпає принцип «Open Source MIT з першого коміту» → прийняття лише окремим
   ADR з фіксацією наслідків (ліцензія, GitHub Actions-ліміти, контриб'ютори).
2. **A8: staging/CI-runner + uptime-експеримент** — self-hosted runner + збір uptime-даних
   протягом кварталу → рішення про міні-ПК / переїзд prod (пов'язано з R-11, single-server).

**Гейт yurii:** обидва рішення — huddle + окремий ADR.

---

## Ритми

### Неділя — digest (≤15 хв)

1. Відкрити щотижневий digest у Discord (cron нд 18:00 Europe/Kyiv, ADR-032 §5).
2. **Кожен пункт** digest'а → GitHub-issue (лейбл `ai-fix`, коли T1 конвеєр запущено)
   **АБО** явний запис «accepted noise: причина» у digest-треді.
3. Переглянути закріплений issue «Черга yurii» — викреслити виконане, перевірити
   актуальність.
4. За потреби — лейбл `ai-approved` на тріажені плани (T1 конвеєр).

### 1-е число місяця — huddle (промпт A4)

- Запуск: промпт **A4** з `docs/15_LLM_PROMPTS.md` у звичайному чаті сильної моделі
  (це діалог, не headless — `docs/16` §9).
- Вхід: останні 4 digest'и + поточний цей файл.
- Вихід: **корекція черг треків** (переставити/додати/зняти пункти) — правка цього файлу
  (docs-PR або прямий commit yurii).

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

> Не блокує роботу, закривається через T1-конвеєр (кандидати на перші ai-fix issues).

- [x] **TD-01.** ~~Бампнути версії GitHub Actions (`actions/checkout@v4`, `docker/*`, `actions/setup-python@v5` тощо).~~ **Закрито 2026-08-03** (Master Run 12, звірка з `origin/main`): `checkout@v5`, `setup-node@v5`, `pnpm/action-setup@v5`, `setup-python@v6`, `upload-artifact@v6`, `docker/*` v4-v7, `setup-uv@v7`. Дій на Node.js 20 не лишилось — дедлайни 16.06.2026 / 16.09.2026 неактуальні. Бампи розійшлись по різних PR, пункт лишався невикресленим два місяці. **Не покрито цим пунктом:** `NODE_VERSION` (версія Node для збірки, не для дій) — винесено окремим пунктом черги T1.
- [ ] **TD-02.** Унеможливити stale скомпільовані `*.js`/`*.js.map` поряд із `.ts` у `packages/*/src/`. **Чому:** vitest при `import "./foo.js"` резолвить буквальний `.js` і підхоплює stale-білд замість свіжого `.ts` — локальні прогони показують неправдиві результати (плутанина у Phase 2.16.b: тест «бачив» стару Zod-схему з `url()`, хоча `.ts` уже мав `min(1)`). Файли untracked (CI чистий), проблема лише локальна. Варіанти: lefthook/pre-commit guard, що падає на stray `src/**/*.js`; `clean`-крок у dev-командах; або гарантувати, що жоден `tsc` не запускається без `outDir: dist`.

---

## Не робимо

**Інфраструктурні анти-цілі** (`docs/14` §5): на MS21 (2 vCPU / 4 GB) і 10 users/day —
жодних microservices, Kubernetes, Kafka/event-sourcing, Prometheus+Grafana-стеку,
OpenTelemetry-колектора, ML-пайплайнів. Sentry (free tier) + Postgres `events` + Umami
(self-hosted) + Discord webhook покривають 100 % потреб MVP і v1.x. Складність — головний
ворог solo-проєкту (R-07).

**Продуктові анти-цілі** (поза scope, post-launch): калькулятор вартості; інтеграція з
прайсом виробника (CSV/API); Телеграм/Discord-бот нотифікацій; маркетплейс кількох
виробників; завантаження користувацьких STEP/STL; mobile app; AI-помічник «опиши що
треба → отримай шаблон»; польська/німецька локалізація; власний платіжний шлюз.

---

## Умовні фази (⏸ ADR-020, активуються тригерами)

- **Auth & Limits** (колишня «Phase 3», ~2 тижні): Auth.js + Argon2id + JWT/refresh,
  `usage_quota` «10 безкоштовних/міс», гість-режим, адмінка. Разом з нею — GDPR DSR
  endpoints (`/account/export-data`, `/account/delete`; колишній пункт 5.5 — без
  акаунтів немає ідентифіковного суб'єкта). **Тригери:** >5 ботів/тиждень на CF WAF;
  АБО >3 unique users просять «зберегти draft».
- **Donations** (колишня «Phase 4», ~1 тиждень): `/unlock`, `donation_claims`,
  адмін-верифікація, email-сповіщення. **Тригер:** >$50/міс приходить на ЗСУ через банку.
- Ендпоінти/таблиці обох фаз лишаються спроєктованими у `docs/06_API_CONTRACT.md` /
  `docs/05_DATA_MODEL.md` як `v1.1+ planned`.

---

## Архів завершених фаз

> Повні описи, тестові числа і рішення — у `docs/13_PROGRESS_LOG.md` (append-only
> журнал). Тут — лише навігаційна таблиця. Чекбокс-історія доступна у git-історії
> цього файлу (до 2026-07-18).

| Фаза                                                                                      | Завершено            | PR                                                  | Джерело                                      |
| ----------------------------------------------------------------------------------------- | -------------------- | --------------------------------------------------- | -------------------------------------------- |
| Phase 0. Setup (монорепо, CI, lefthook)                                                   | 2026-05-16           | —                                                   | `docs/13` «Phase 0 — Foundation»             |
| Phase 1. CAD core (валідатори, unfold, DXF)                                               | 2026-05-16           | —                                                   | `docs/13` «Phase 1 — CAD core»               |
| Phase 2. UX MVP (5 шаблонів end-to-end, 2.10.a-e, design system 2.11-2.16)                | 2026-06-03           | —                                                   | `docs/13` «Phase 2 — Templates & UI»         |
| Phase X.1. Beta-mode tweaks (rate-limit, watermark, ЗСУ-CTA, /about)                      | 2026-06-04           | —                                                   | `docs/13` «Soft-launch (Phase X.1)», ADR-020 |
| Phase 2.9.b. Drawing polish (badges, розміри, BOM UA)                                     | 2026-06-05           | —                                                   | `docs/13` «Drawing polish», ADR-021          |
| Discord IaC                                                                               | 2026-06-11           | —                                                   | `docs/13` «Discord IaC», ADR-023             |
| Hotfix 2.9.d. Production-grade DXF                                                        | 2026-06-15           | —                                                   | `docs/13` «Hotfix 2.9.d», ADR-024            |
| Feature 2.9.e. Ізометрія у PDF                                                            | 2026-06-16           | —                                                   | `docs/13` «Feature 2.9.e», ADR-025           |
| Hotfix 2.9.f. R3F render-gate                                                             | 2026-06-16           | —                                                   | `docs/13` «Hotfix 2.9.f», ADR-026            |
| Phase 5. Infrastructure (5A-5F: prod-compose, Ansible, backups, staging live; решта → T3) | 2026-05-28 (staging) | —                                                   | `docs/13` «Phase 5 — Infrastructure»         |
| Phase 3.0. Products Catalog                                                               | 2026-06-23           | #32, #37-#44                                        | ADR-027 (запис у docs/13 — борг)             |
| Phase 3.1. Перфо-панель: ребра + кутові отвори                                            | 2026-06-25           | —                                                   | `docs/13` «Feature 3.1», ADR-030             |
| Phase 3.2. Уніфікація перфо-панелі (hole_shape)                                           | 2026-06-26           | —                                                   | `docs/13` «Feature 3.2», ADR-031             |
| Phase 3.3. Observability foundation (+активація на staging 2026-07-12)                    | 2026-07-06           | #54-#56, #58-#60; активація #63/#65, hotfix #71-#72 | `docs/13` «Feature 3.3», ADR-032             |
| Phase 3.4. Виробничий фідбек — QR у PDF                                                   | 2026-07-17           | #69, #75                                            | `docs/13` «Feature 3.4», ADR-032 §feedback   |
