# flatcraft

> Безкоштовна онлайн-платформа для проєктування деталей з листового металу і генерації виробничих креслень (DXF + PDF + STEP) — без CAD-навичок.

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
![Status](https://img.shields.io/badge/status-pre--MVP-orange)

## Що це таке

Користувач без навичок CAD заходить на сайт, вибирає типовий виріб (L-кронштейн, кутник, полиця, перфо-панель, …), крутить повзунки розмірів і матеріалу, бачить миттєвий 3D-прев'ю і скачує готові DXF + PDF + STEP, з якими можна йти на будь-яке локальне виробництво лазерного різання та гибки.

**До 10 експортів на місяць безкоштовно. Далі — добровільний донат від 200 грн на ЗСУ → +1 місяць безкоштовного користування.**

Платформа неприбуткова, open source (MIT).

## Як це працює

```
[Browser]
  ├─ Параметрична форма (Next.js + react-three-fiber)
  ├─ 3D-прев'ю в реальному часі (OpenCascade.js)
  └─ Live-валідація проти технологічних обмежень
        ↓
[Fastify API]
  ├─ Auth.js (email + Google OAuth)
  ├─ Лічильник 10 безкоштовних / місяць
  └─ Постановка задачі у чергу (BullMQ)
        ↓
[Python CAD Worker (CadQuery)]
  ├─ Точна розгортка з K-фактором
  ├─ Експорт DXF (з шарами під лазер) + PDF (з ізометрією і BOM) + STEP
  └─ Завантаження у Cloudflare R2
        ↓
[Browser отримує presigned URL → завантаження]
```

## Швидкий старт (локально)

Передумови: Docker Desktop, Node.js 20+ (через `nvm`), pnpm 9+, Python 3.12 (через `uv`).

```bash
# 1. Клон і setup
git clone https://github.com/stjurik/flatcraft.git
cd flatcraft
pnpm install
cp .env.example .env

# 2. Підняти інфраструктуру (Postgres + Redis + MinIO)
docker compose up -d

# 3. Міграції + seed
pnpm db:migrate
pnpm db:seed

# 4. Стартуємо
pnpm dev    # підіймає web (3000) + api (4000) + cad-worker

# 5. Відкриваємо
open http://localhost:3000
```

Усе — за 5 хв. Якщо щось пішло не так — див. `docs/troubleshooting.md` (буде).

## Документація

- [`CLAUDE.md`](CLAUDE.md) — головний контекст для Claude Code (читайте першим)
- [`AGENTS.md`](AGENTS.md) — опис підпроєктів
- [`docs/00_OPEN_QUESTIONS.md`](docs/00_OPEN_QUESTIONS.md) — невирішені питання
- [`docs/02_ROADMAP.md`](docs/02_ROADMAP.md) — план до MVP (12 тижнів)
- [`docs/03_DECISIONS.md`](docs/03_DECISIONS.md) — Architecture Decision Records
- [`docs/04_RISKS.md`](docs/04_RISKS.md) — реєстр ризиків
- [`docs/05_DATA_MODEL.md`](docs/05_DATA_MODEL.md) — схема БД
- [`docs/06_API_CONTRACT.md`](docs/06_API_CONTRACT.md) — REST API
- [`docs/07_BEND_MACHINE_SPEC.md`](docs/07_BEND_MACHINE_SPEC.md) — обмеження листозгинальної машини

## Стек

| Шар                  | Технологія                                                                         |
| -------------------- | ---------------------------------------------------------------------------------- |
| Frontend             | Next.js 15 + TypeScript + react-three-fiber + Tailwind + shadcn/ui                 |
| Backend API          | Fastify + TypeScript + Zod                                                         |
| CAD-engine (browser) | OpenCascade.js                                                                     |
| CAD-worker (server)  | Python 3.12 + CadQuery + FastAPI                                                   |
| База даних           | PostgreSQL 16 + Drizzle ORM                                                        |
| Storage              | Cloudflare R2 (S3-compatible) / MinIO у dev                                        |
| Cache & Queue        | Redis + BullMQ                                                                     |
| Auth                 | Auth.js v5                                                                         |
| Container            | Docker + docker-compose                                                            |
| Hosting              | Mirohost Cloud (тариф MS21: 2 vCPU / 4 GB / 40 GB, ДЦ Київ) + Cloudflare DNS/proxy |
| Observability        | Sentry + Plausible                                                                 |
| CI/CD                | GitHub Actions                                                                     |
| IaC                  | Ansible (Terraform не використовуємо — Mirohost не має провайдера; див. ADR-011)   |

## Структура

```
flatcraft/
├── apps/
│   ├── web/              # Next.js
│   └── api/              # Fastify
├── workers/
│   └── cad/              # Python CadQuery
├── packages/
│   ├── cad-engine/       # CAD utilities, validators, k-factor
│   ├── db/               # Drizzle schema + migrations + seed
│   ├── types/            # Zod schemas, shared DTOs
│   └── ui/               # shadcn/ui + custom components
├── infra/
│   ├── docker/
│   ├── compose/
│   └── ansible/          # налаштування Mirohost Cloud сервера
├── docs/                 # ADR, roadmap, data model, …
├── tools/scripts/
├── CLAUDE.md
├── AGENTS.md
└── README.md
```

## Внесок

Проєкт open source, MIT. Ласкаво просимо PR-и, але:

1. Прочитайте [`CLAUDE.md`](CLAUDE.md) і [`docs/02_ROADMAP.md`](docs/02_ROADMAP.md).
2. Кожен PR має тести (TDD).
3. Conventional Commits (`feat:`, `fix:`, …).
4. Squash merge у `main`.

Discord для координації: _(посилання буде після створення сервера)_

## Соціальна модель

Платформа — соціальний проєкт без юрособи на старті. Усі донати йдуть напряму через офіційні фонди:

- 🇺🇦 Monobank банка _(посилання буде)_
- 🌍 [UNITED24](https://u24.gov.ua/)

Платформа _не_ виступає одержувачем коштів. Розблокування ліміту після донату — це знак подяки, а не зустрічна послуга.

## Ліцензія

MIT — див. [`LICENSE`](LICENSE).

---

_Зроблено для DIY-ентузіастів, малого бізнесу та локальних виробників. Слава ЗСУ._
