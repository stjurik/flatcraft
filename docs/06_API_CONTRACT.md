# 06. API Contract

> REST + JSON, версія `/v1`. Усі body — Zod-валідовані. OpenAPI 3.1 генеруємо з Zod через `@asteasolutions/zod-to-openapi`. Артефакт: `apps/api/openapi.json` (генерується у CI).
> Усі ендпоінти — у kebab-case, ресурси — множина (`/exports`, `/templates`).
> Помилки — шаблон [RFC 9457 Problem Details](https://datatracker.ietf.org/doc/html/rfc9457).

---

## 0. Загальне

### Базовий URL

- dev: `http://localhost:4000/v1`
- staging: `https://api.staging.flatcraft.io/v1`
- prod: `https://api.flatcraft.io/v1`

### Аутентифікація

- Access token — JWT у заголовку `Authorization: Bearer <token>`. Час життя: 15 хв.
- Refresh token — HttpOnly Secure SameSite=Lax cookie `flatcraft_rt`. Час життя: 30 дн.
- CSRF — для cookie-залежних ендпоінтів (`/auth/refresh`, `/auth/logout`) вимагається double-submit `X-Csrf-Token` header == cookie value.

### Помилки (RFC 9457)

```json
{
  "type": "https://flatcraft.io/errors/validation",
  "title": "Validation failed",
  "status": 422,
  "detail": "Field 'thickness_mm' must be one of [1, 1.5, 2, ...]",
  "instance": "/v1/exports",
  "errors": [{ "field": "thickness_mm", "code": "INVALID_ENUM", "value": 7 }]
}
```

**Коди валідації гиба (`POST /exports`, серверний gate — ADR-019).** Серверна валідація проти `bend-machine-esi.yaml` обов'язкова (клієнтська — лише UX). Невалідний гиб → `422` з RFC 9457, **жоден артефакт не створюється**:

Кожен запис `errors[]` має `message` — дружню україномовну підказку (для радіуса: «Збільшіть / Зменшіть радіус гибки…»); `detail` дублює `message` першої помилки.

| `code`                    | Поле             | Додаткові поля                                                   | Коли                                                   |
| ------------------------- | ---------------- | ---------------------------------------------------------------- | ------------------------------------------------------ |
| `RADIUS_NOT_ALLOWED`      | `bend_radius_mm` | `message`, `allowed: number[]`, `value`, `thickness`, `material` | R недопустимий для (товщина) за матрицею               |
| `THICKNESS_NOT_SUPPORTED` | `thickness_mm`   | `message`, `value`                                               | Товщини немає у матриці                                |
| `MATERIAL_NOT_ALLOWED`    | `material_code`  | `message`, `value`                                               | Матеріал не в групі для цієї товщини (напр. нерж 10мм) |
| `ANGLE_NOT_ALLOWED`       | `bend_angle_deg` | `message`, `value`                                               | Кут не з `allowed_angles_deg`                          |

Приклад для Z-bracket t=5 / R=2.5 (для t=5 матриця дозволяє лише {4.0, 5.0}):

```json
{
  "type": "https://flatcraft.io/errors/validation",
  "title": "Validation failed",
  "status": 422,
  "detail": "Збільшіть радіус гибки: для товщини 5 мм мінімальний радіус 4 мм (дозволено: 4, 5 мм).",
  "instance": "/exports",
  "errors": [
    {
      "field": "bend_radius_mm",
      "code": "RADIUS_NOT_ALLOWED",
      "value": 2.5,
      "message": "Збільшіть радіус гибки: для товщини 5 мм мінімальний радіус 4 мм (дозволено: 4, 5 мм).",
      "allowed": [4.0, 5.0],
      "thickness": 5.0,
      "material": "cold_rolled_steel"
    }
  ]
}
```

**Код валідації перфорації (`POST /exports`, серверний gate — ADR-019/026).** Для `perforated_panel` (єдиний перфо-шаблон, ADR-031; форма отвору — параметр `hole_shape`) крок отворів має перевищувати розмір отвору `hole_size_mm` по кожній осі, інакше сусідні отвори торкаються/зливаються у суцільний проріз (заготовка не відповідає BOM «N окремих отворів»). Перевірка — `validatePerforation` (cad-engine), дзеркалена у Fastify-gate і Python-воркері; клієнт показує банер + блокує експорт (UX, не замінює сервер).

| `code`          | Поле                        | Додаткові поля     | Коли                                                                   |
| --------------- | --------------------------- | ------------------ | ---------------------------------------------------------------------- |
| `HOLES_OVERLAP` | `pitch_x_mm` / `pitch_y_mm` | `message`, `value` | Крок ≤ розміру отвору (сторона квадрата / діаметр) — отвори зливаються |

Приклад для perforated_panel (hole_shape=square, □20 мм, pitch_y=10 < 20 → лише вісь Y):

```json
{
  "type": "https://flatcraft.io/errors/validation",
  "title": "Validation failed",
  "status": 422,
  "detail": "Збільшіть «Крок Y»: крок 10 мм має бути більший за сторону отвору 20 мм — інакше сусідні отвори перетинаються.",
  "instance": "/exports",
  "errors": [
    {
      "field": "pitch_y_mm",
      "code": "HOLES_OVERLAP",
      "value": 10,
      "message": "Збільшіть «Крок Y»: крок 10 мм має бути більший за сторону отвору 20 мм — інакше сусідні отвори перетинаються."
    }
  ]
}
```

### Rate limit

- Глобальний flood-захист — на рівні **Cloudflare WAF** (edge), а НЕ у Fastify. Fastify-плагін реєструється `global: false` навмисно: web (SSR) робить server-side fetch до API з однієї IP контейнера, тож глобальний per-IP ліміт throttl'ив би усі SSR-запити під спільним ключем. Точковий ліміт — лише на browser-direct маршрутах.
- `/exports` POST: **30/год/IP** + burst-ban (>50 у вікні → тимчасовий 403). Soft-launch без auth, тож ключ — IP, не user (ADR-020, Phase X.1). Перевищення → `429` RFC 9457 (`type: .../errors/rate-limit`) з україномовним `detail`. У prod req.ip = реальна клієнтська IP (trustProxy + X-Forwarded-For від Caddy/CF).
- `/auth/login`, `/auth/register`: 10/год/IP. _(🚧 v1.1+ — auth ще не реалізовано, див. ADR-020.)_

Заголовки відповіді: `RateLimit-Limit`, `RateLimit-Remaining`, `RateLimit-Reset`, `Retry-After` (при 429).

> Реалізовано: `apps/api/src/plugins/rate-limit.ts`. Маршрути нижче без `🚧`-позначки — наявні у MVP; з `🚧 v1.1+` — лише спроєктовані (ADR-020).

---

## 1. Auth

> 🚧 **v1.1+ planned — не реалізовано у MVP.** Soft-launch без auth (ADR-020). Endpoints нижче спроєктовані, але не існують у поточному API; активуються при тригерах ADR-020.

### POST /v1/auth/register

```yaml
request:
  email: string (lower, valid email)
  password: string (min 12, must contain letter+digit)
  display_name: string (optional)
  locale: 'uk' | 'en'  (default 'uk')
response 201:
  user_id: uuid
  email: string
  email_verification_required: true
errors:
  409 EMAIL_TAKEN
  422 VALIDATION
```

### POST /v1/auth/login

```yaml
request: { email, password }
response 200:
  access_token: string # JWT
  user: { id, email, display_name, role, locale, units }
  set-cookie: flatcraft_rt=... # HttpOnly
errors: 401 INVALID_CREDENTIALS
  423 ACCOUNT_LOCKED # після 5 невдалих спроб — 15 хв пауза
```

### POST /v1/auth/refresh

- Cookie `flatcraft_rt` + `X-Csrf-Token`.
- Видає новий access_token, ротує refresh.

### POST /v1/auth/logout

- Інвалідовує refresh у БД, очищає cookie.

### GET /v1/auth/oauth/google/start

- 302 → Google.

### GET /v1/auth/oauth/google/callback

- 302 → web з access token у короткоживучому одноразовому query (одразу обмінюємо на cookie).

### POST /v1/auth/email/verify

- Body: `{ token }`. Token приходить листом.

---

## 2. Account

> 🚧 **v1.1+ planned — не реалізовано у MVP.** Потребує auth (ADR-020). Без облікових записів немає `/account/*`, quota чи GDPR-self-service.

### GET /v1/account/me

- Профіль.

### PATCH /v1/account/me

- `display_name`, `locale`, `units`.

### GET /v1/account/quota

```json
{
  "period_start": "2026-05-01",
  "free_used": 3,
  "free_limit": 10,
  "bonus_until": "2026-06-08T12:00:00Z"
}
```

### POST /v1/account/export-data (GDPR)

- Створює job → email з лінком на JSON-дамп.

### POST /v1/account/delete (GDPR soft-delete з 30-day grace)

- Body: `{ confirm_email: string }`.

### GET /v1/account/sessions

- Список активних refresh-сесій з User-Agent.

### DELETE /v1/account/sessions/{session_id}

---

## 3. Templates / Materials

### GET /v1/templates

- Кешуємо 1 хв CDN-side, 1 год клієнт-side.
- Query: `?lang=uk` (default з заголовка), `?published=true`.

```json
{
  "items": [
    {
      "slug": "l_bracket",
      "name": "Кронштейн L-подібний",
      "description": "...",
      "preview_image_url": "https://r2.flatcraft.io/...",
      "parameters_schema": { "...": "Zod-as-JSON-Schema" },
      "default_parameters": { "legA_mm": 100, ... },
      "compatibility": [
        { "material_code": "cold_rolled_steel", "thickness_min_mm": 1, "thickness_max_mm": 8 },
        ...
      ]
    }
  ]
}
```

### GET /v1/templates/{slug}

- Те саме, але один.

### GET /v1/materials

```json
{
  "items": [
    {
      "code": "cold_rolled_steel",
      "name": "Холоднокатана сталь DC01",
      "category": "steel",
      "density_kg_m3": 7850,
      "thicknesses_mm": [1, 1.5, 2, 2.5, 3, 4, 5, 6, 8]
    }
  ]
}
```

---

## 4. Drafts (стан проєкту користувача)

### GET /v1/drafts

- Список чернеток поточного користувача (paginated).

### POST /v1/drafts

```yaml
request:
  template_slug: string
  name: string (optional, default 'Untitled')
  parameters: object  # перевіряється проти template.parameters_schema
  material_code: string
  thickness_mm: number
  surface_finish: 'raw' | 'painted' | null
  paint_ral: string | null
response 201:
  id, name, validation_status, validation_errors, created_at
```

### GET /v1/drafts/{id}

### PATCH /v1/drafts/{id}

- Часткове оновлення. Тригерить ре-валідацію.

### POST /v1/drafts/{id}/validate

- Повертає `{ status: 'valid' | 'invalid', errors: [...] }`.

### DELETE /v1/drafts/{id}

---

## 5. Exports (генерація DXF/PDF/STEP)

### POST /v1/exports

```yaml
request:
  draft_id: uuid
  formats: array of ('dxf' | 'pdf' | 'step')  # default: ['dxf', 'pdf']
response 202:
  export_id: uuid
  status: 'queued'
  poll_url: '/v1/exports/{id}'
  sse_url: '/v1/exports/{id}/events'
errors:
  402 QUOTA_EXCEEDED  # → клієнт показує /unlock
  422 DRAFT_INVALID   # validation errors
```

### GET /v1/exports/{id}

```json
{
  "id": "uuid",
  "status": "queued | running | done | failed",
  "formats": ["dxf", "pdf"],
  "files": {
    "dxf": { "url": "https://r2.../signed?...", "expires_at": "..." },
    "pdf": { "url": "...", "expires_at": "..." }
  },
  "bom": {
    "blank_width_mm": 350,
    "blank_height_mm": 200,
    "cut_length_mm": 1100,
    "bend_count": 1,
    "paint_area_m2": 0.07,
    "mass_kg": 0.55
  },
  "error_message": null
}
```

### GET /v1/exports/{id}/events (SSE)

- Поточний статус + progress: `event: progress\ndata: {"phase":"unfold","percent":40}`.

### GET /v1/exports

- Історія користувача (paginated, останні 30 днів).

### Observability (Phase 3.3, ADR-032) — preview

**Фаза 3.3 НЕ додає нових публічних endpoints.** Телеметрія пишеться server-side:

- `POST /v1/exports`, `GET /v1/exports/{id}`, `GET /v1/exports/{id}/events`, `GET /v1/exports` —
  контракт **незмінний**; додається лише persistence (in-memory `JobStore` → таблиця `exports`,
  той самий respond-shape). Клієнт нічого не помічає.
- Події `events` (`export_requested` / `validation_rejected` / `export_completed` /
  `export_failed`) емітить api у своїх хендлерах — це не роут, а серверний запис (`docs/11 §6`).
- **Внутрішній контракт worker→api→`events`:** worker повідомляє `cad_started` / `cad_completed`
  (з `duration_ms`) через наявний worker→api-callback (той самий канал, що вже несе результат
  експорту), **не** через новий публічний роут. Payload — `packages/types/src/events/` (Zod,
  `docs/11 §5`); джерело істини спільне для api й worker (як внутрішній BullMQ job payload, §11).
- `web_vital` — тонкий beacon web→api (custom event), не публічний ресурс.

Read-API для `events` у MVP немає: дані споживають digest-cron і майбутня адмінка (ad-hoc SQL).

---

## 6. Donations

> 🚧 **v1.1+ planned — не реалізовано у MVP.** У soft-launch донати на ЗСУ — почесна система: прямі лінки (Monobank банка, UNITED24) у post-export CTA і на `/about`, без `donation_claims`/unlock-flow. Активується при тригері ADR-020 (>$50/міс). `/v1/uploads` (proof) також лишається v1.1+.

### GET /v1/donations/channels

- Перелік активних каналів і їхніх параметрів (банка-лінк, USDT-адреса, UNITED24-лінк).

### POST /v1/donations/claim

```yaml
request:
  channel: 'monobank_banka' | 'united24' | 'usdt'
  amount_uah: number  # юзер вказує суму
  proof_file_id: uuid  # попередньо завантажено через /v1/uploads
response 201:
  claim_id, status: 'pending'
```

### POST /v1/uploads (multipart, для proof)

- Тільки для авторизованих, max 5 MB, тільки `image/*` і `application/pdf`.

---

## 7. Admin

> 🚧 **v1.1+ planned — не реалізовано у MVP.** Потребує auth + ролі (ADR-020).

Усі під префіксом `/v1/admin/...`, потребують `role = admin`.

### GET /v1/admin/users (search, paginate)

### GET /v1/admin/donations/claims (фільтр `status=pending`)

### POST /v1/admin/donations/claims/{id}/approve

### POST /v1/admin/donations/claims/{id}/reject

### GET /v1/admin/exports (моніторинг)

### POST /v1/admin/templates (CRUD)

---

## 8. Webhooks

### POST /v1/webhooks/monobank-acquiring (v1.1)

- Підтвердження донату через офіційний шлюз.
- Аутентифікація: HMAC-SHA256 у заголовку `X-Sign`.

---

## 9. Health & Ops

### GET /healthz

- Liveness: завжди 200.

### GET /readyz

- Readiness: 200 якщо БД + Redis доступні.

### GET /metrics (Prometheus exposition format, тільки з internal IP)

> **Примітка (ADR-032):** продуктова телеметрія Phase 3.3 йде в Postgres-таблицю `events`, **не**
> в Prometheus-стек (анти-ціль 14 §5). `/metrics` лишається щонайбільше мінімальним ops-liveness
> (без Grafana/колектора); за непотреби може лишитись нереалізованим.

---

## 10. Версіонування

- Контракт `v1` стабілізуємо після Phase 5. Зміни — тільки додавання полів.
- Зломні зміни — `v2` з паралельним мейнтенансом 6 міс.

---

## 11. Що ще потрібно описати (поза цим документом)

- WebSocket/SSE protocol (рамки повідомлень).
- Формат внутрішнього BullMQ-job payload (`packages/types/src/jobs.ts`).
- OpenAPI schema файл — генерується автоматично у CI з Zod.
