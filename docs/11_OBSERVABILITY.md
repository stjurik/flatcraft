# 11. Observability & self-improvement loop

> Специфікація до **ADR-032**. Як платформа бачить себе: технічна телеметрія, продуктова
> аналітика, виробничий фідбек — і як сирі дані щотижня перетворюються на рішення. Реалізація —
> серія PR **Phase 3.3** (`docs/02_ROADMAP.md`). Джерело-аналіз — `docs/14_ARCHITECTURE_EVOLUTION.md §4`.
>
> **Статус:** специфікація (docs-gate, Phase 3.3 PR 1). Тут — контракт, не імплементація; код —
> у наступних PR фази.

---

## 1. Принцип

**Кожен експорт — це експеримент, результат якого платформа зобов'язана зібрати**
(`docs/14 §4`). До Phase 3.3 платформа сліпа (14 §1.4): логи в stdout, історія експортів
in-memory, нуль аналітики й фідбеку. Observability — фундамент усіх подальших рішень про
шаблони/процеси: без даних вони приймаються наосліп. Тому фаза йде **першою** з еволюційного
треку (14 §6) і **до** публічного soft-launch.

Стек свідомо мінімальний (ADR-032, анти-цілі 14 §5): Postgres `events` + Sentry (SaaS free) +
Plausible + Discord webhook. Жодного Prometheus/Grafana/OTel/Kafka/K8s.

---

## 2. Три рівні

| Рівень                  | Що бачимо                    | Інструмент                               | Ризик, який закриває  |
| ----------------------- | ---------------------------- | ---------------------------------------- | --------------------- |
| 1. Технічна телеметрія  | що ламається, скільки триває | Sentry ×3 + `events` + persist `exports` | R-02, R-12, бюджет §9 |
| 2. Продуктова аналітика | де користувач страждає       | Plausible (воронка) + web-vitals         | R-10                  |
| 3. Виробничий фідбек    | чи зійшлось у металі         | `/f/{export_id}` + `export_feedback`     | R-01                  |

Phase 3.3 будує рівні 1-2. Рівень 3 (виробничий фідбек) — **Phase 3.4** (окремий PR-gate,
`docs/15` промпт B3, R-01 mitigation 4); тут згадується лише як майбутній споживач digest'а.

---

## 3. Схема `events` (SQL preview)

Append-only, без PII. Це **preview** — фактична схема у `packages/db/src/schema.ts` + міграція
створюються у Phase 3.3 PR 2 (міграцію генерує yurii вручну через `drizzle-kit`, CLAUDE.md §6).

```sql
-- append-only: жодного UPDATE/DELETE у гарячому шляху (retention — окремий scheduled job)
CREATE TABLE events (
  id            uuid PRIMARY KEY,                     -- uuid v7 (sortable)
  ts            timestamptz NOT NULL DEFAULT now(),
  event_type    text        NOT NULL,                 -- словник §4
  template_slug text,                                 -- напр. 'l_bracket' (NULL для web_vital)
  process       text        NOT NULL DEFAULT 'sheet_metal', -- майбутній process-layer (14 §3)
  params        jsonb,                                -- знімок параметрів виробу (НЕ PII)
  error_code    text,                                 -- напр. 'RADIUS_NOT_ALLOWED' (NULL при success)
  duration_ms   integer,                              -- для cad_* / export_* подій
  session_hash  text                                  -- добовий salt, непереслідуваний (§7)
);

CREATE INDEX events_ts_idx       ON events (ts DESC);
CREATE INDEX events_type_ts_idx  ON events (event_type, ts DESC);
CREATE INDEX events_template_idx ON events (template_slug, ts DESC);
```

Дублює структуру у `docs/05_DATA_MODEL.md §2 (events)` — там канонічна таблиця полів, тут SQL для
наочності.

---

## 4. Словник `event_type`

| `event_type`          | Хто емітить             | Коли                                 | Ключові поля                           |
| --------------------- | ----------------------- | ------------------------------------ | -------------------------------------- |
| `export_requested`    | api (Fastify hook)      | прийнято `POST /exports` (після Zod) | template_slug, params, session_hash    |
| `validation_rejected` | api (gate ADR-019/026)  | серверний gate відхилив (422)        | template_slug, params, error_code      |
| `export_completed`    | api                     | job done, артефакти в R2             | template_slug, duration_ms             |
| `export_failed`       | api                     | job failed (cad-worker/мережа)       | template_slug, error_code, duration_ms |
| `cad_started`         | api (worker round-trip) | старт CAD-операції                   | template_slug                          |
| `cad_completed`       | api (worker round-trip) | кінець CAD-операції                  | template_slug, duration_ms             |
| `web_vital`           | web → api               | тік FCP/TTI/mesh-update              | params (metric+value), session_hash    |

Кореляції, що дає словник:

- `export_requested` + `validation_rejected` → **воронка відмов** (скільки запитів гине на
  серверному gate і по якому constraint).
- `cad_started` / `cad_completed` → **чиста тривалість CAD** (без мережі/черги).
- `export_completed.duration_ms − cad_completed.duration_ms` → **overhead pipeline** (черга +
  R2-upload + мережа).

---

## 5. Zod-схеми payload'ів (preview)

Єдине джерело — майбутній `packages/types/src/events/` (Phase 3.3 PR 2), спільний для api й worker
(через JSON-schema, як `packages/types/src/jobs/`). Нижче — **форма**, не код у `packages/`.

```ts
// PREVIEW — фактичний код у packages/types/src/events/ (Phase 3.3 PR 2)
const EventBase = z.object({
  event_type: z.enum([
    "export_requested",
    "validation_rejected",
    "export_completed",
    "export_failed",
    "cad_started",
    "cad_completed",
    "web_vital",
  ]),
  template_slug: z.string().nullable(),
  process: z.string().default("sheet_metal"),
  session_hash: z.string().nullable(),
});

const ExportRequestedPayload = EventBase.extend({
  event_type: z.literal("export_requested"),
  params: z.record(z.unknown()), // знімок параметрів виробу (валідований per-template схемою)
});

const ValidationRejectedPayload = EventBase.extend({
  event_type: z.literal("validation_rejected"),
  params: z.record(z.unknown()),
  error_code: z.string(), // напр. "RADIUS_NOT_ALLOWED", "HOLES_OVERLAP"
});

const CadCompletedPayload = EventBase.extend({
  event_type: z.literal("cad_completed"),
  duration_ms: z.number().int().nonnegative(),
});

const WebVitalPayload = EventBase.extend({
  event_type: z.literal("web_vital"),
  params: z.object({ metric: z.enum(["FCP", "TTI", "mesh_update"]), value_ms: z.number() }),
});
// export_completed / export_failed / cad_started — аналогічно (duration_ms / error_code)
```

**Інваріант «no-PII».** Payload-схемі **заборонено** містити email/IP/будь-яке персональне поле.
Unit-тест «no-PII keys» (перелік ключів проти allow-list) — обов'язковий у PR 2; це серверний
паритет pino-redact (`apps/api/src/logger.ts`) і Sentry `beforeSend` (CLAUDE.md §8).

---

## 6. Хто пише, хто читає

**Пишуть:**

- **api (Fastify):** `export_requested`, `validation_rejected`, `export_completed`,
  `export_failed` — через route-хендлери/hooks у `apps/api/src/routes/exports*` (там, де зараз
  живе `JobStore`). Запис — після Zod-валідації, поза гарячим respond-шляхом (не блокує 202).
- **cad-таймінг:** worker **не має доступу до Postgres**, тож `cad_started` / `cad_completed`
  (з `duration_ms`) пише також **api**, вимірюючи worker round-trip синхронного `/export`
  (Phase 3.3 PR 2, рішення D3; worker без змін). Точніший worker-internal тайминг — refinement
  при BullMQ (Phase 5).
- **web:** `web_vital` — тонкий beacon у api (custom event), не напряму в БД.

**Читають:**

- **digest-cron** (§9) — агрегати за 7 днів.
- **admin** — ad-hoc SQL (майбутня адмінка `apps/api/src/routes/admin`). Публічного read-API для
  `events` немає (телеметрія — server-side).

---

## 7. PII / GDPR (ADR-032 п.6, ADR-006)

- `events` і `export_feedback` — **без email/IP**.
- `session_hash` — хеш із **добовим salt** (salt ротується щодоби, зберігається поза БД); зшити
  сесії користувача між добами неможливо. Мета — агрегатний сигнал (унікальні сесії/день), не
  стеження.
- Retention — **12 місяців** (паритет з `audit_log`, data-model §7); прибирає scheduled job.
- Правило: **параметри виробу — технічні дані, не PII** (це геометрія). Тому `params jsonb`
  зберігаємо повністю.
- Sentry — `beforeSend` фільтрує email/IP (інваріант CLAUDE.md §8), паритет з pino-redact.
- Згадка Sentry (третя сторона-процесор) і телеметрії — у Privacy Policy (Phase 5.4).

---

## 8. Воронка Plausible

```
catalog → studio_opened → param_changed → validation_error_shown → export_clicked → export_done
```

- Cookie-less (ADR-006) → без cookie-banner.
- **Ключова метрика — `validation_error_shown` з розбивкою по constraint** (який ліміт блокує
  найчастіше). Прямий вхід для R-10: топ-constraint → кандидат на ширшу параметризацію шаблону.
- Web-vitals (FCP/TTI/mesh-update) — custom events; звіряються з бюджетами CLAUDE.md §9.
- **Plausible vs `events` — не взаємозамінні:** Plausible — агрегатна воронка/UX-сигнал
  (клієнт-side, семпльований); `events` — точний серверний факт (для digest, аудиту, join з
  `exports`). Один констатує намір користувача, другий — результат на сервері.

---

## 9. Щотижневий digest

Cron **неділя 18:00 Europe/Kyiv** (worker або `tools/scripts` — рішення у PR 4) → SQL за 7 днів →
markdown → Discord webhook (`DIGEST_WEBHOOK_URL`; звичайний POST, **не** `discord:apply` —
ADR-023 / CLAUDE.md §6). Ядро — pure-функція `build_digest(rows) → str` з unit-тестами на
фікстурах (порожній / типовий / з deviation-репортом тиждень).

**Формат:**

```markdown
# hart · щотижневий digest (2026-MM-DD … MM-DD)

## 1. Top-5 validation errors (по constraint)

| constraint (error_code) | к-сть | шаблон(и) |

## 2. Failed exports

| template | error_code | к-сть | приклад ts |

## 3. Тривалості (p95 vs бюджет §9)

| етап         | p95 | бюджет | статус |
| ------------ | --- | ------ | ------ |
| export (DXF) | …   | 3 c    | ✅/⚠️  |
| export (PDF) | …   | 5 c    | …      |

## 4. Виробничий фідбек (Phase 3.4+)

| export_id | outcome | deviation_mm | коментар | ← порожньо до Phase 3.4

## 5. Sentry summary

| issue | events | перший раз |

## 6. Обсяг

унікальних сесій: N · експортів: N (done/failed) · відхилень валідації: N
```

**Правило процесу:** кожен пункт digest'а → **або GitHub-issue** (Conventional-Commits-заголовок,
стиль `docs/15` C3), **або явно позначений «accepted noise»**. Це замикає self-improvement loop
(14 §4.4): не магія, а конвеєр даних у Roadmap. Місячний архітектурний huddle сильної моделі
(`docs/15` A4) читає 4 digest'и й пропонує пріоритети/перегляд ADR.

---

## 10. Non-goals (анти-цілі 14 §5)

На MS21 (2 vCPU / 4 GB) і 10 users/day **не робимо**: Prometheus/Grafana, Loki, OpenTelemetry-
колектор, Kafka/event-sourcing, ML-пайплайн, realtime-дашборд, per-user cross-day tracking.
Складність — головний ворог solo-проєкту (R-07). Якщо реальні дані покажуть межу цього стеку —
переоцінюємо окремим ADR (не наперед, YAGNI).

---

## 11. Статус реалізації (Phase 3.3, `docs/02_ROADMAP.md`)

| PR   | Зміст                                                        | Статус              |
| ---- | ------------------------------------------------------------ | ------------------- |
| PR 1 | ADR-032 + цей файл + Roadmap + preview Data Model/API (docs) | ✅                  |
| PR 2 | `events` + persist `exports` у Postgres (+ Zod payload'и)    | ▶ міграція — yurii  |
| PR 3 | Sentry ×3 (web/api/worker) + `beforeSend` PII-тести          | ⏳                  |
| PR 4 | Digest-cron → Discord webhook                                | ✅ (cron — Ansible) |
| PR 5 | Plausible + web-vitals                                       | ⏳                  |
| PR 6 | Progress-log (`docs/13` + ротація CLAUDE.md §13)             | ⏳                  |
