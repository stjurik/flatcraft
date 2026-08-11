# AGENTS.md — карта підпроєктів для Claude Code

> Файл-довідник: який модуль за що відповідає, які команди запускати, які тести покривають що. Читайте, коли беретесь за нову частину коду.

## apps/web — Next.js (frontend)

**Призначення:** SSR/CSR UI, 3D-редактор, форма параметрів, експорт.

**Стек:** Next.js 15 (App Router), TypeScript strict, react-three-fiber, Tailwind, shadcn/ui, Auth.js client.

**Команди:**

```bash
pnpm --filter @flatcraft/web dev           # порт 3000
pnpm --filter @flatcraft/web build
pnpm --filter @flatcraft/web test          # vitest + RTL
pnpm --filter @flatcraft/web test:e2e      # Playwright
pnpm --filter @flatcraft/web lint
```

**Структура:**

```
apps/web/
├── src/
│   ├── app/                     # App Router pages
│   │   ├── (marketing)/         # /, /about, /pricing
│   │   ├── (app)/               # /templates, /templates/[slug], /account
│   │   └── (auth)/              # /login, /register
│   ├── components/              # web-specific (з ui приходять загальні)
│   ├── lib/                     # api-client, auth, formatters
│   └── styles/
├── tests/
│   ├── unit/
│   └── e2e/
├── public/
└── next.config.ts
```

**Залежить від:** `@flatcraft/types`, `@flatcraft/cad-engine`, `@flatcraft/ui`.

---

## apps/api — Fastify (backend)

**Призначення:** REST API, Auth, постановка задач у чергу, адмінка backend.

**Стек:** Fastify, TypeScript strict, Zod, Drizzle, BullMQ, Auth.js (Fastify integration), pino.

**Команди:**

```bash
pnpm --filter @flatcraft/api dev           # порт 4000
pnpm --filter @flatcraft/api start
pnpm --filter @flatcraft/api test          # vitest + supertest
pnpm --filter @flatcraft/api test:int      # testcontainers (Postgres у Docker)
```

**Структура:**

```
apps/api/
├── src/
│   ├── routes/
│   │   ├── auth/
│   │   ├── account/
│   │   ├── templates/
│   │   ├── drafts/
│   │   ├── exports/
│   │   ├── donations/
│   │   └── admin/
│   ├── plugins/                 # Fastify plugins (auth, rate-limit, sentry, swagger)
│   ├── lib/                     # business logic
│   ├── jobs/                    # BullMQ producers
│   └── server.ts
└── openapi.json                 # генерується у CI
```

**Залежить від:** `@flatcraft/types`, `@flatcraft/db`.

---

## workers/cad — Python CAD Worker

**Призначення:** важкі CAD-обчислення: розгортка, експорт DXF/PDF/STEP. Слухає Redis-чергу через `bullmq-py`.

**Стек:** Python 3.12, CadQuery, FastAPI (для health/metrics), pytest, mypy strict, ruff, uv.

**Команди:**

```bash
cd workers/cad
uv sync
uv run pytest
uv run mypy .
uv run ruff check .
uv run python -m flatcraft_cad.worker          # listen-mode
uv run python -m flatcraft_cad.cli render --template l_bracket --params @params.json --out ./out/
```

**Структура:**

```
workers/cad/
├── pyproject.toml
├── uv.lock
├── flatcraft_cad/
│   ├── worker.py                # BullMQ listener
│   ├── cli.py                   # CLI для розробки/тестів
│   ├── templates/               # параметричні моделі (l_bracket, z_bracket, …)
│   │   ├── base.py              # абстрактний клас Template
│   │   ├── l_bracket.py
│   │   └── z_bracket.py
│   ├── unfold.py                # розгортка з K-фактором
│   ├── export/
│   │   ├── dxf.py
│   │   ├── pdf.py
│   │   └── step.py
│   └── validate/                # сервер-side fallback валідатори
└── tests/
    ├── snapshots/               # фіксовані DXF-байти
    └── unit/
```

**Залежить від:** `bend-machine-esi.yaml` (через спільний шлях у `packages/cad-engine/data/`).

---

## packages/cad-engine — TS CAD утиліти

**Призначення:** валідатори (browser-side), завантажувач bend-machine-spec, K-фактор, формули bend allowance, типи.

**Стек:** TypeScript strict, Zod, OpenCascade.js (peer dependency).

**Команди:**

```bash
pnpm --filter @flatcraft/cad-engine test
pnpm --filter @flatcraft/cad-engine build
```

**Структура:**

```
packages/cad-engine/
├── src/
│   ├── spec.ts                  # завантаження + Zod-валідація bend-machine spec
│   ├── validators/
│   │   ├── bend.ts
│   │   ├── sheet.ts
│   │   └── holes.ts
│   ├── k-factor.ts
│   ├── unfold-math.ts           # bend allowance, neutral axis
│   ├── opencascade-bridge.ts    # adapter до OpenCascade.js
│   └── types.ts
├── data/
│   └── bend-machine-esi.yaml    # ОДИН ФАЙЛ ІСТИНИ (читається TS і Python)
└── tests/
```

---

## packages/db — Drizzle schema + migrations

**Призначення:** єдина схема БД, міграції, seed.

**Стек:** Drizzle ORM, drizzle-kit.

**Команди:**

```bash
pnpm --filter @flatcraft/db generate       # drizzle-kit generate
pnpm --filter @flatcraft/db migrate
pnpm --filter @flatcraft/db studio         # drizzle-kit studio (GUI)
pnpm --filter @flatcraft/db seed
```

**Структура:**

```
packages/db/
├── src/
│   ├── schema.ts                # ВСЯ схема в одному файлі
│   ├── seed.ts
│   ├── client.ts                # postgres-js + drizzle init
│   └── migrations/
└── drizzle.config.ts
```

---

## packages/types — спільні Zod-схеми та DTO

**Призначення:** типобезпечний шлюз між web/api/worker.

**Стек:** TypeScript strict, Zod, `@asteasolutions/zod-to-openapi`.

**Структура:**

```
packages/types/
└── src/
    ├── api/                     # AuthRequests, ExportRequests, …
    ├── domain/                  # Material, Template, Draft, Export, BOM
    ├── jobs/                    # BullMQ payload schemas (parsed і у Python через json schema)
    ├── templates/               # параметричні Zod-схеми шаблонів
    └── index.ts
```

**Правило:** жодних інших залежностей, окрім `zod` і `@asteasolutions/zod-to-openapi`.

---

## packages/ui — shadcn/ui + кастомні компоненти

**Призначення:** перевикористовувані React-компоненти.

**Стек:** React 19, TypeScript, Tailwind, shadcn/ui.

**Структура:**

```
packages/ui/
└── src/
    ├── primitives/              # shadcn (Button, Dialog, Input, Form, …)
    ├── 3d-viewport/             # react-three-fiber-обгортки
    │   ├── Viewport.tsx
    │   ├── OrbitCamera.tsx
    │   └── PartMesh.tsx
    ├── parameter-form/
    │   └── auto-form.tsx        # авто-генерація з Zod-схеми
    ├── bom-table/
    └── index.ts
```

---

## infra — IaC

**Призначення:** налаштування сервера Mirohost Cloud (Docker, docker-compose, .env, systemd, backups, firewall) через Ansible. Сам сервер створюється вручну в панелі Mirohost — Terraform-провайдера Mirohost не має (див. ADR-011). Cloudflare R2 + DNS налаштовуються через CLI/панель.

**Стек:** Ansible 2.16+.

**Команди:**

```bash
cd infra/ansible
ansible-playbook -i inventory.ini site.yml          # повне налаштування
ansible-playbook -i inventory.ini site.yml --tags deploy   # тільки re-deploy
```

**ВАЖЛИВО:** перед першим запуском — створити Cloud-сервер у панелі Mirohost і вписати його IP в `inventory.ini`. Секрети — у `1Password` / `vault`, не в репо. `inventory.ini` не комітимо.

---

## A8 — середовище автономної розробки

> **Статус: спроєктовано, НЕ розгорнуто** (станом на 2026-08-11). Контракт середовища —
> **ADR-039**; мануальна підготовка машини — `docs/19_A8_PREFLIGHT.md`; розгортання —
> master-run `docs/promts/master-a8-transition.md` (**ще не написаний**; крок 5 треку T5, `docs/02`).
> Імена шляхів і юнітів нижче — **домовленість цього ADR**, яку реалізує крок 5. Якщо
> реалізація обере інші імена, цей розділ оновлюється тим самим PR, а не «потім».

**Що це.** Домашня машина `a8` (Ubuntu Server 24.04), на якій живуть **недетерміновані**
частини конвеєра — агенти. Детерміновані оракули (10 job'ів `ci.yml`,
`deploy-staging.yml`, `release.yml`) лишаються у GitHub Actions (ADR-039 §1).
**На A8 немає prod-креденшалів** — ні пароля Ansible-vault, ні SSH-ключа до Mirohost,
ні GHCR-токена на запис (`docs/19` §7 п.1). Агент не деплоїть; деплоїть CI після merge.

**Розкладка (усе під користувачем `agent`, без sudo):**

| Що                 | Де                                                 | Призначення                                                                          |
| ------------------ | -------------------------------------------------- | ------------------------------------------------------------------------------------ |
| Демон-супервізор   | systemd-юніт `hart-orchestrator.service`           | тонкий детермінований цикл: взяти задачу → worktree → сесія → класифікувати вихід    |
| Черга задач        | `/home/agent/queue/{pending,running,done,failed}/` | по одному JSON-файлу на задачу; стан живе тут і в git, **ніколи в контексті моделі** |
| Головний клон      | `/home/agent/hart/`                                | джерело worktree'їв; сам ніколи не є робочим деревом агента                          |
| Worktree на задачу | `/home/agent/wt/<task-id>/`                        | ізоляція (ADR-039 §2); видаляється після merge/закриття PR                           |
| Контейнер агента   | образ `hart-agent:<tag>`, один запуск на задачу    | `--dangerously-skip-permissions` дозволений **ЛИШЕ тут**; allowlist вихідної мережі  |
| Журнали            | `/home/agent/logs/<task-id>/`                      | `run.jsonl` (потік сесії) + `summary.json` (запис супервізора: клас виходу, PR, час) |
| Kill switch        | файл `/home/agent/STOP`                            | перевіряється ПЕРЕД кожною задачею                                                   |

**Як подивитись стан:**

```bash
ssh yurii@a8
systemctl status hart-orchestrator                 # живий демон?
ls /home/agent/queue/pending | wc -l               # скільки задач у черзі
ls /home/agent/queue/running                       # що виконується зараз
tail -f /home/agent/logs/<task-id>/run.jsonl       # пульс конкретної задачі
jq . /home/agent/logs/<task-id>/summary.json       # чим закінчилось (клас виходу, PR)
```

Без SSH: канал Discord **`#на-перевірку`** (draft PR + прев'ю + «Як перевірити очима»)
і **`#інциденти`** (401, квота, машина впала, диск). Питання агента — у
`#питання-блокуючі` (клас A, без дефолту) і `#питання-дефолт` (клас B, таймер 6–12 год);
формат питання — шість обов'язкових полів, ADR-039 §6.

**Як зупинити (kill switch):**

```bash
touch /home/agent/STOP        # поточна задача дограє, нові НЕ беруться
systemctl stop hart-orchestrator   # жорстко: зупинити демон негайно
rm /home/agent/STOP           # зняти прапорець (демон сам не знімає)
```

**Межі, які середовище не переступає** (`docs/19` §7, ADR-039 §2, ADR-040 §1): міграції
БД, `infra/**`, `.github/workflows/**`, `CLAUDE.md`, `docs/03_DECISIONS.md`,
`packages/db/src/schema.ts`, bend-матриця і будь-яка зміна DXF/PDF-снапшотів — **завжди
через yurii**, незалежно від режиму auto-merge.

---

## tools/scripts — допоміжні скрипти

**Призначення:** генератори, перевірки, мікро-утиліти.

**Приклади:**

- `tools/scripts/generate-openapi.ts` — генерує `apps/api/openapi.json` з Zod.
- `tools/scripts/calibrate-k-factor.py` — допомагає переcalibrate K після пілота.
- `tools/scripts/check-cad-determinism.sh` — запускає експорт двічі і diff байт-у-байт.

---

## Загальні команди верхнього рівня

```bash
pnpm dev            # запуск всього (turbo)
pnpm build          # build усіх workspace
pnpm test           # всі тести (TS) + pytest
pnpm lint           # eslint + ruff
pnpm typecheck      # tsc + mypy
pnpm format         # prettier + ruff format
```
