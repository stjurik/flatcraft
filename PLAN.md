# WP2 — Umami-активація + launch-runbook (infra/phase-3-3b-umami-deploy)

Package 2 з master-run'у (`docs/promts/master-softlaunch-run.md`). Виконує `docs/promts/phase-3-3-b-activation.md` (deliverables A-G) + go-live checklist з master §WP2.

## Deliverables

| ID    | Файл                                                  | Зміна                                                                                                                                  |
| ----- | ----------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| **A** | `infra/compose/docker-compose.prod.yml`               | +service `umami` (image ghcr.io/umami-software/umami:postgresql-latest, mem 192m, healthcheck, restart on-failure:5, depends postgres) |
| **B** | `infra/compose/Caddyfile`                             | +vhost `analytics.hart.crimea.ua` → `umami:3000` (той самий CF Origin Cert)                                                            |
| **C** | `infra/ansible/roles/flatcraft/tasks/main.yml`        | +tasks: ensure umami DB (idempotent, `docker exec ... psql`)                                                                           |
| **C** | `infra/ansible/roles/flatcraft/templates/env.prod.j2` | +UMAMI*APP_SECRET, NEXT_PUBLIC_UMAMI*\*, DIGEST_WEBHOOK_URL (плейсхолдери → vault)                                                     |
| **C** | `infra/ansible/group_vars/all.yml`                    | +`umami_domain: analytics.hart.crimea.ua`, `umami_image` версія                                                                        |
| **C** | `infra/ansible/group_vars/all.vault.yml.example`      | +vault-ключі-hints (не значення)                                                                                                       |
| **D** | `.env.example`                                        | +UMAMI_APP_SECRET з коментарем `openssl rand -base64 32`                                                                               |
| **E** | `docs/08_DEPLOYMENT.md`                               | +§«Телеметрія» (чекліст активації) + §«Go-live checklist (soft-launch)» (7 мануальних кроків + KPI + rollback)                         |
| **F** | `docs/11_OBSERVABILITY.md`                            | TODO про Umami-deploy → done; PR 2 `⏳` → `✅`                                                                                         |
| **G** | —                                                     | Файл `phase-3-3-b-activation.md` вже track'нуто в WP1; не дублюю тут                                                                   |

## RAM budget (target ≤ 3.2 GB з phase-3-3-b; compose-коментар ≤ 3.5 GB)

| Container       | mem_limit           | Real typical                   |
| --------------- | ------------------- | ------------------------------ |
| postgres        | 512m                | ~200m                          |
| redis           | 256m                | ~50m                           |
| cad-worker      | 1500m               | 400-1200m (peak при CAD)       |
| api             | 512m                | ~200m                          |
| web             | 512m                | ~200m                          |
| caddy           | 128m                | ~50m                           |
| **umami (new)** | **192m**            | ~120m                          |
| **TOTAL**       | **3612m ≈ 3.53 GB** | typical: ~1.5 GB, peak ~2.4 GB |

**Перевищення 3.2 GB target на 330m** (те, що вимагав phase-3-3-b) — на 3% над compose-документованим 3.5 GB.

Обґрунтування прийняття:

- MS21 = 4 GB RAM + 2 GB swap. Головний OS overhead ~500 MB → app-space ~3.5 GB.
- `mem_limit` — це **hard cap**, не сталий usage. Реальне одночасне пікування всіх контейнерів на max неможливе (наприклад CAD-worker peak-ить під час експорту, коли web/api idle між request'ами).
- Умами 192m — це `ghcr.io/umami-software/umami:postgresql-*` мінімум (Umami — Next.js server + PostgreSQL client; heavy compute — у нашому Postgres).
- Альтернатива: знизити `cad-worker` до 1300m (7% менший буфер над реальним peak 1200m — ризиковано для важких моделей). **Не роблю** — це regression risk.

**Питання до yurii у PR:** прийнятне рішення 3.53 GB, чи знижуємо cad-worker до 1300m?

## Створення БД umami — Ansible-task, а не compose init-script

- Compose `init.d/*.sql` спрацьовує тільки при **першому** створенні data-volume postgres. У нас volume вже існує (postgres up 2+ тижні). Init-script буде проігнорований.
- **Ansible-task через `docker exec ... psql`** (idempotent: `SELECT 1 FROM pg_database WHERE datname='umami'` → `CREATE DATABASE umami` при відсутності). Той самий постгрес-user (flatcraft), окрема БД umami.
- Умами сам створить свою schema при першому старті (drizzle-міграцій нашого коду не торкаємо — інший scope).

## Тести

- `ansible-playbook --syntax-check site.yml` — pass.
- `ansible-lint --profile production` — pass.
- `docker compose -f infra/compose/docker-compose.prod.yml config -q` — valid.
- Existing CI (unit tests) — без регресій (код не чіпаємо, лише infra + docs).

## Обмеження

- Гілка `infra/phase-3-3b-umami-deploy` від `origin/main` (не стакати з WP1).
- Жодних змін у `apps/`, `packages/`, `workers/`.
- Секрети — тільки vault/env; у репо — плейсхолдери.
- Draft PR у фіналі, **НЕ merge**.

## Питання до yurii

Зберу під час виконання. Preview:

1. RAM budget 3.53 GB прийнятний, чи знижуємо cad-worker до 1300m?
2. Umami image tag — я візьму `postgresql-latest` (стабільна гілка); чи pin'ити на конкретний semver (`v2.19.0-postgresql`) для reproducibility?
3. `analytics.hart.crimea.ua` — коли yurii налаштує DNS CF, потрібно чи ще щось (крім самого A/CNAME)? DNSSEC? Rate-limit?
