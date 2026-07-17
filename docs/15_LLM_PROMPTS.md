# 15. LLM Prompts — маршрутизація завдань по моделях

> Супровід до `docs/14_ARCHITECTURE_EVOLUTION.md`. Готові промпти для реалізації рекомендацій, розкладені по рівнях складності. Стиль успадковано з `docs/promts/phase-3-0-pr1-architecture.md` (КОНТЕКСТ → МЕТА → ОБМЕЖЕННЯ → ДЕЛІВЕРАБЛИ → ТЕСТИ → ПОЧАТОК).

## 0. Правила маршрутизації

| Рівень                  | Тип завдання                                                      | Модель                                                         | Доступ до репо                                                                  |
| ----------------------- | ----------------------------------------------------------------- | -------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| **A — стратегічні**     | ADR, архітектурні рішення, trade-off-аналіз, docs-gate PR         | Найсильніша reasoning-модель (Claude Opus/Fable у Claude Code) | Повний                                                                          |
| **B — імплементаційні** | Код за затвердженим ADR: чіткий scope, TDD, відомі паттерни       | Середня (Claude Sonnet у Claude Code)                          | Повний                                                                          |
| **C — підготовчі**      | Інвентаризація, аудит, чернетки текстів, підсумовування digest'ів | Дешева/безкоштовна (Haiku, чат-моделі)                         | **Read-only або без доступу** — результат у чат/markdown, ніколи не пише у репо |

Правила для ВСІХ промптів рівнів A і B:

1. Промпт завжди починається зі списку обов'язкових файлів для читання (мінімум: `CLAUDE.md`, `AGENTS.md`, релевантні ADR).
2. A-промпт — завжди **docs-only PR-gate**: жодного коду, поки yurii не затвердив ADR.
3. B-промпт виконується **тільки після** merge відповідного A-PR і посилається на номер ADR.
4. Обмеження CLAUDE.md §6 повторюються явно (міграції вручну, без нових top-level залежностей без згоди, без правок CLAUDE.md §1-12).
5. Кожен промпт закінчується: «Покажи ПЛАН → дочекайся OK → виконуй → STOP після PR».
6. C-результати складати у `docs/promts/inputs/` (або лишати в чаті) — вони вхід для A/B, не істина.

Рекомендована послідовність запуску: **C2 → A1 → B1 → B2 → B3 → B5** (observability) паралельно з **C1 → A2 → B4** (registry), потім **A3**.

> **Автономний/паралельний запуск** (headless `claude -p`, git worktree, runner-скрипт) — див. `docs/16_AUTONOMOUS_RUNS.md`.

---

## Рівень A — стратегічні промпти

### A1. ADR-032 + docs/11_OBSERVABILITY.md (Phase 3.3, docs-only gate)

```
[Phase 3.3 — PR 1: Observability & self-improvement loop (ADR-032 + docs/11 + Roadmap)]

КОНТЕКСТ
- ОБОВ'ЯЗКОВО прочитай: CLAUDE.md (§1-13), AGENTS.md, docs/14_ARCHITECTURE_EVOLUTION.md §4
  (це ТЗ цього PR), docs/02_ROADMAP.md (Phase 5.1/5.2 — Sentry/analytics ще не зроблені),
  docs/04_RISKS.md (R-01, R-02, R-10, R-12), docs/05_DATA_MODEL.md (exports),
  docs/06_API_CONTRACT.md, apps/api/src/logger.ts (pino redact — інваріант),
  apps/api/src/routes/exports* (поточний in-memory JobStore).
- Якщо існує docs/promts/inputs/c2-log-audit.md (аудит логування, промпт C2) — прочитай.
- Бізнес-контекст: платформа перед публічним soft-launch сліпа (див. 14 §1.4).
  Мета фази — «кожен експорт = експеримент, результат якого збираємо».

МЕТА
Зафіксувати ADR-032 «Observability & self-improvement loop», створити
docs/11_OBSERVABILITY.md як специфікацію, додати Phase 3.3 checklist у Roadmap,
preview змін у Data Model і API Contract.

ОБМЕЖЕННЯ
- DOCS-ONLY PR. Жодних змін у packages/, apps/, workers/, infra/.
- НЕ створювати міграцій. НЕ редагувати CLAUDE.md §1-12. НЕ ротувати §13.
- Гілка docs/phase-3-3-observability, Conventional Commits, 3-5 commits.

ДЕЛІВЕРАБЛИ
A. ADR-032 у docs/03_DECISIONS.md. Рішення (кожне ALT/CHOICE/RATIONALE/CONSEQUENCES):
   1. Сховище подій: Postgres-таблиця `events` vs зовнішній стек (Prometheus/OTel).
      ВИБІР: Postgres. Обґрунтуй через MS21-ресурси (ADR-011), solo-maintenance (R-07),
      те, що events = продуктові дані (join з exports), а не тільки метрики.
   2. Sentry (SaaS free tier) для web+api+worker vs self-hosted GlitchTip vs «тільки pino».
      ВИБІР: Sentry з beforeSend PII-фільтром (інваріант CLAUDE.md §8).
   3. JobStore in-memory → таблиця exports (уже в data model). Retention артефактів у R2.
   4. Продуктова аналітика: Plausible vs Umami vs нічого. Критерій: cookie-less,
      GDPR без banner-ускладнень (ADR-006), self-hosted опція, RAM-бюджет MS21.
      ВИБІР: Umami self-hosted (окрема БД у наявному Postgres) — ADR-032 §4,
      фінальне рішення 2026-07-05. Plausible відхилено (CE = ClickHouse ~2 ГБ RAM;
      Cloud = кошти + дані поза UA).
   5. Digest: cron у worker → Discord webhook (інфра ADR-023 вже є) vs email vs дашборд.
      Формат digest-markdown: top-5 validation_error по constraint, failed exports,
      p95 export_duration vs бюджет §9, deviation-репорти (Phase 3.4+), Sentry summary.
   6. GDPR-межі: без email/IP у events; session_hash з добовим salt; retention 12 міс;
      правило «параметри виробу — технічні дані, не PII».
B. docs/11_OBSERVABILITY.md — специфікація:
   - схема events (SQL preview): id, ts, event_type, template_slug, process, params jsonb,
     error_code, duration_ms, session_hash;
   - словник event_type (export_requested, validation_rejected, export_completed,
     export_failed, cad_started, cad_completed, web_vital) + Zod-схема payload'ів
     (preview, без коду у packages/);
   - хто пише: Fastify onSend-hook / worker; хто читає: digest-cron, admin;
   - воронка Umami: catalog → studio_opened → param_changed →
     validation_error_shown → export_clicked → export_done;
   - формат щотижневого digest + правило «кожен пункт → issue або accepted noise».
C. docs/02_ROADMAP.md — секція «Phase 3.3 — Observability foundation» з PR-checklist:
   PR 1 (цей), PR 2 events+exports tables, PR 3 Sentry ×3, PR 4 digest-cron,
   PR 5 Umami + web-vitals, PR 6 progress-log.
D. docs/05_DATA_MODEL.md — preview: events, зміни exports (persist).
E. docs/06_API_CONTRACT.md — preview: без нових публічних endpoints у 3.3
   (events пишуться server-side), позначити внутрішній контракт worker→events.

ТЕСТИ
- Docs-only; переконайся, що prettier/lefthook по md зелені.

ПОЧАТОК
1. Покажи ПЛАН (структура ADR-032, зміст docs/11, checklist фази).
2. Дочекайся OK від yurii. 3. Виконуй. 4. gh pr create. 5. STOP — PR 2 без OK не починати.
```

### A2. ADR-033 Template Registry (Phase 3.5, docs-only gate)

> **Статус (housekeeping 2026-07-17): docs-gate виконано.** ADR-033 і
> `docs/12_TEMPLATE_CONTRACT.md` присутні на main (ADR-033 сам має статус
> `Proposed`, не `Accepted`). Зміст потрапив на main непрямо — `git blame`
> веде на `74ff1c0`/PR #71, не власний PR (ймовірний побічний ефект
> squash-merge з невірної бази, клас помилки `chore/guard-branch-base`).
> Імплементаційні PR 2-9 (реєстр + міграція 6 шаблонів) — НЕ розпочато.

```
[Phase 3.5 — PR 1: Template Registry contract (ADR-033 + docs/12 + міграційний план)]

КОНТЕКСТ
- ОБОВ'ЯЗКОВО прочитай: CLAUDE.md, AGENTS.md, docs/14_ARCHITECTURE_EVOLUTION.md §2,
  ADR-013/017/026/027/031, packages/types/src/templates/* (усі 6 схем),
  packages/ui/src/3d-viewport/geometry.ts, apps/web/src/components/template-studio.tsx
  (+ будь-які 2 пари *-editor.tsx/*-viewport.tsx для порівняння),
  workers/cad/flatcraft_cad/templates/base.py.
- Якщо існує docs/promts/inputs/c1-template-inventory.md (промпт C1) — це головний вхід:
  таблиця відмінностей 6 шаблонів. Без нього — зроби інвентаризацію сам (перший commit).
- Мета бізнесу: новий шаблон = 1 TS-модуль + 1 Python-модуль + снапшоти; нуль змін
  у apps/web. «Різні вироби по-різному відображаються» має стати неможливим структурно.

МЕТА
ADR-033 «Template Registry contract» + docs/12_TEMPLATE_CONTRACT.md + план міграції
6 шаблонів (по одному на PR) + специфікація conformance-suite.

ОБМЕЖЕННЯ
- DOCS-ONLY. Без коду, без міграцій, без правок CLAUDE.md §1-12.
- Контракт НЕ має ламати: детермінізм, render-gate (ADR-026), продукти (ADR-027),
  browser-safe головний entry cad-engine.

ДЕЛІВЕРАБЛИ
A. ADR-033, рішення: 1) TemplateDefinition-контракт (склад полів; де живе —
   новий packages/templates vs розширення types — обґрунтуй залежності);
   2) generic editor через AutoForm + .describe()-метадані (ADR-017) vs збереження
   ручних editor'ів; 3) generic viewport через sceneBuilder-реєстр; 4) доля
   discriminatedUnion ExportRequest при реєстровому підході; 5) Python-реєстр і
   parity-тест slug'ів; 6) conformance-suite (перелік перевірок на кожен шаблон:
   schema parity TS↔Python property-based, DXF/PDF детермінізм, render-gate,
   e2e smoke — автогенерація з реєстру).
B. docs/12_TEMPLATE_CONTRACT.md: контракт + «Definition of Done нового шаблону»
   (чекліст, який стане шаблоном промпту для кожного майбутнього виробу).
C. Roadmap Phase 3.5: PR-checklist — registry-пакет + conformance-suite (PR 2),
   потім міграція шаблонів ПО ОДНОМУ (PR 3-8, від найпростішого perforated_panel
   до enclosed_shelf), видалення per-template файлів у фінальних PR, e2e 92+ зелені
   після КОЖНОГО PR.
ПОЧАТОК — як в A1 (план → OK → виконання → STOP).
```

### A3. ADR-034 Process layer (Phase 3.6, docs-only)

```
[Phase 3.6 — ADR-034: Manufacturing process layer (docs-only)]

КОНТЕКСТ
- Прочитай: CLAUDE.md, docs/14_ARCHITECTURE_EVOLUTION.md §3, ADR-033 (registry — база),
  docs/05_DATA_MODEL.md, packages/types/src/domain/export.ts, схему artifacts у exports.
- Бізнес: згодом 3D-друк (FDM) і мехобробка. ЗАРАЗ — тільки словник і схеми,
  щоб майбутній процес був плагіном, а не форком.

МЕТА
ADR-034: ієрархія Process → Template → Product → Draft → Export → Artifact → Feedback.
Рішення: 1) artifacts як список {kind, mime, r2_key} замість фіксованих ключів dxf/pdf/step
(+ backward-compat план для наявних записів/клієнтів); 2) templates.process_slug
(константа sheet_metal поки); 3) ExportJob.process у payload черги; 4) структура
процес-пакета (capability-spec YAML + валідатори + експортери + worker-модуль) —
на прикладі майбутнього fdm_print, БЕЗ його реалізації; 5) правило: sheet-metal-специфіка
не додається у спільні шари. Явно перелічи, що НЕ робимо (YAGNI-розділ).
Preview змін у Data Model + Roadmap-нотатка «v1.2 FDM» + пропозиція правок CLAUDE.md §3
(окремим списком, НЕ редагуючи сам CLAUDE.md).
ПОЧАТОК — план → OK → виконання → STOP.
```

### A4. Щомісячний архітектурний huddle (без доступу до репо — можна у звичайному чаті сильної моделі)

```
Ти — архітектурний радник проєкту hart.crimea.ua (параметричні вироби з листового
металу; стек: Next.js + Fastify + Python CadQuery, монорепо, solo-розробник).
Вхідні дані нижче: (1) останні 4 щотижневі digest'и платформи (top validation errors,
failed exports, p95 тривалості, deviation-репорти з виробництва, Sentry summary),
(2) поточний список фаз Roadmap.
Завдання: 1) назви 3 найважливіші сигнали у даних і що вони кажуть про продукт;
2) чи підтверджують дані поточні пріоритети Roadmap — якщо ні, що переставити;
3) чи є сигнал, що якесь архітектурне рішення (ADR) варто переглянути; 4) один
експеримент на наступний місяць з метрикою успіху. Відповідай стисло, українською.
[вставити digest'и + roadmap]
```

---

## Рівень B — імплементаційні промпти (після затвердження відповідного ADR)

> Шаблон-обгортка для всіх B: «Прочитай CLAUDE.md, AGENTS.md, ADR-0XX, docs/11 або 12.
> TDD (red→green→refactor). Гілка feat/…, Conventional Commits, PR. Обмеження §6:
> міграції drizzle НЕ генерувати самостійно — підготуй schema.ts-зміни і зупинись,
> міграцію yurii створює вручну через drizzle-kit. Покажи план → OK → виконуй → STOP.»

### B1. Events + exports у Postgres (Phase 3.3 PR 2)

```
Реалізуй persist-шар телеметрії за ADR-032 / docs/11_OBSERVABILITY.md.
ДЕ: packages/db/src/schema.ts (events, зміни exports), packages/types/src/events/
(Zod-схеми event payload'ів — єдине джерело для api і worker), apps/api (запис
export_requested/validation_rejected/export_completed/export_failed у route-хендлерах
exports; заміна in-memory JobStore на drizzle-репозиторій з тим самим інтерфейсом),
workers/cad (cad_started/cad_completed з duration_ms — через існуючий callback у api).
БЕЗ PII: жодного email/IP у events (тест на це обов'язковий). session_hash — добовий salt.
ТЕСТИ: unit на Zod event-схеми; integration (testcontainers) — POST /exports лишає
рядки у exports+events; регресія — SSE-flow експорту без змін (наявні e2e зелені).
ДОКИ: оновити docs/06_API_CONTRACT.md (внутрішній контракт), docs/11 позначити done-пункти.
```

### B2. Sentry web + api + worker (Phase 3.3 PR 3)

```
Підключи Sentry за ADR-032. ДЕ: apps/web (@sentry/nextjs), apps/api (@sentry/node
як Fastify-plugin поряд з наявними plugins/), workers/cad (sentry-sdk python).
DSN — тільки через env (.env.example з плейсхолдерами). beforeSend: фільтр email/IP —
UNIT-ТЕСТИ на фільтр у КОЖНОМУ з трьох сервісів (це інваріант CLAUDE.md §8, Roadmap 5.1).
Нові top-level залежності — перелічи у плані і дочекайся OK (CLAUDE.md §6).
Sample rate: errors 100%, traces 0 (MS21-ресурси). Docker env — infra/compose НЕ чіпати,
підготуй diff-пропозицію в PR description.
```

### B3. QR-фідбек з виробництва (Phase 3.4)

> **Статус (2026-07-17): виконано.** PR #69 (`4a7d94d`) + PR #75/issue #70
> (`34a2127`) — обидва merged. `docs/04_RISKS.md` R-01 mitigation 4 → ✅.
> Повний запис — `docs/13_PROGRESS_LOG.md` «Feature 3.4».

```
Реалізуй виробничий feedback-loop за ADR-032 §feedback (див. 14 §4.3, R-01 mitigation 4).
ДЕ: workers/cad/flatcraft_cad/export/pdf.py — QR веде на {BASE_URL}/f/{export_id}
(зараз перевір, куди веде QR, і збережи детермінізм снапшотів: URL з export_id →
снапшоти перегенеруй усвідомлено окремим commit'ом); apps/web — сторінка /f/[exportId]
(мобільна, без auth, 3 поля: виготовлено так/ні, відхилення мм + де, коментар;
дизайн-токени docs/10); apps/api — POST /feedback/{export_id} (Zod, rate-limit IP,
404 на невідомий export); packages/db — export_feedback (schema.ts, міграція — yurii).
ТЕСТИ: pytest QR-URL; api integration happy+404+rate-limit; e2e: форма сабмітиться
з телефонного viewport 360×640. ДОКИ: 06_API_CONTRACT + 04_RISKS R-01 (закрити mitigation 4).
```

### B4. Studio unification (Phase 3.5 PR 2+, по одному шаблону на PR)

```
Мігруй шаблон {SLUG} на Template Registry за ADR-033 / docs/12_TEMPLATE_CONTRACT.md.
Порядок фази: PR 2 — пакет registry + conformance-suite (без міграцій шаблонів);
PR 3+ — по одному шаблону: перенеси Zod/defaults/sceneBuilder у definition,
переключи /templates/[slug] на data-driven шлях, видали <slug>-studio/-editor/-viewport
і гілку в template-thumb. ІНВАРІАНТИ: render-gate ADR-026 зберігається (validateProfile
у registry-шляху), product-mode ADR-027 працює, DXF/PDF байт-у-байт незмінні (снапшоти НЕ
перегенеровувати — вони не мають змінитись!), усі e2e зелені ПІСЛЯ КОЖНОГО PR.
Якщо міграція шаблону вимагає зміни контракту registry — STOP, обговорення з yurii.
```

### B5. Weekly digest → Discord (Phase 3.3 PR 4)

```
Реалізуй щотижневий digest за ADR-032 §digest. ДЕ: workers/cad (або tools/scripts —
обґрунтуй вибір у плані): cron неділя 18:00 Europe/Kyiv → SQL по events/exports/
export_feedback за 7 днів → markdown (формат з docs/11) → Discord webhook (env DIGEST_WEBHOOK_URL).
Discord-обмеження ADR-023: це НЕ discord:apply, звичайний webhook-POST — дозволено.
Pure-функція build_digest(rows) → str з unit-тестами на фікстурах (порожній тиждень,
типовий тиждень, тиждень з deviation-репортом). Мережевий шар — тонкий, замоканий.
```

---

## Рівень C — підготовчі промпти (дешеві моделі, read-only)

### C1. Інвентаризація відмінностей шаблонів (вхід для A2)

```
Нижче — вміст файлів 6 шаблонів з трьох місць кодової бази (Zod-схеми packages/types,
editor/viewport-компоненти apps/web, Python-модулі workers/cad). Побудуй markdown-таблицю:
рядки — аспекти (поля схеми, групи .describe(), валідатори, scene-builder, особливі гілки
у DXF/PDF, e2e-покриття), колонки — 6 шаблонів. Познач: ✅ однаково / ⚠️ відрізняється
стилістично / ❌ відрізняється поведінково. Окремим списком: топ-10 місць копі-пасту,
які найімовірніше дрейфують. Нічого не вигадуй — тільки те, що є у наданому коді.
Результат збережу як docs/promts/inputs/c1-template-inventory.md.
[вставити файли]
```

### C2. Аудит поточного логування (вхід для A1)

```
Нижче — усі місця з logger./log./console. з apps/api, apps/web, workers/cad (grep-вивід
з контекстом). Побудуй таблицю: файл | рівень | подія | чи є structured-поля | чи може
містити PII. Потім список «сліпих зон»: які важливі події життєвого циклу експорту
(запит, відмова валідації, старт CAD, завершення, помилка, тривалість) НЕ логуються
або логуються без параметрів. Результат: docs/promts/inputs/c2-log-audit.md.
[вставити grep-вивід]
```

### C3. Підсумовування щотижневого digest (регулярна рутина після Phase 3.3)

```
Нижче — щотижневий digest платформи hart.crimea.ua (помилки валідації, невдалі експорти,
тривалості, фідбек з виробництва). Зроби: 1) 5 рядків «що сталося» простою мовою;
2) згрупуй помилки за ймовірною причиною; 3) розстав пріоритет P0/P1/P2 з одним реченням
обґрунтування; 4) сформулюй готові заголовки GitHub-issues для P0/P1 (Conventional
Commits-стиль). Без вигадок: якщо даних мало — так і напиши.
[вставити digest]
```

### C4. UX-тексти та переклади

```
Напиши UA+EN тексти для мобільної форми виробничого фідбеку (/f/{export_id}):
заголовок, 3 підписи полів (виготовлено?, відхилення розмірів мм + де, коментар),
кнопка, повідомлення подяки, повідомлення помилки. Тон: дружній до майстра в цеху,
без канцеляриту, коротко (людина стоїть біля верстата). 2 варіанти на вибір.
```

---

## Підтримка цього файлу

Коли ADR-032/033/034 прийняті — промпти A стають історією (як docs/promts/phase-\*),
а B-промпти уточнюються номерами PR. Нові рутинні C-промпти (digest, переклади,
інвентаризації) додавати сюди — це «бібліотека делегування» проєкту.
