[Phase 3.3.b — Активація телеметрії: Umami-контейнер + prod-env wiring]

КОНТЕКСТ

- ОБОВ'ЯЗКОВО прочитай: CLAUDE.md (§6, §8, §13), AGENTS.md, ADR-032 у
  docs/03_DECISIONS.md, docs/11_OBSERVABILITY.md (TODO-рядок про деплой Umami),
  docs/08_DEPLOYMENT.md, infra/compose/docker-compose.prod.yml, Caddyfile,
  infra/ansible/ (ролі flatcraft/monitoring), .env.example.
- ПЕРЕДУМОВА-GATE: перевір git log — Phase 3.3 (PR #54-#60) має бути змержена
  у main, CLAUDE.md §13 містить «Feature 3.3». Якщо ні — STOP і повідом.
- Стан: код телеметрії у main, але в проді все no-op: нема Umami-інстансу і
  нема env (SENTRY*DSN, NEXT_PUBLIC_UMAMI*\*, DIGEST_WEBHOOK_URL).
- ЯВНА ЗГОДА yurii: у МЕЖАХ ЦЬОГО завдання дозволено правити
  infra/compose/docker-compose.prod.yml, Caddyfile та infra/ansible/ (CLAUDE.md §6).

МЕТА
Один PR, після якого `ansible-playbook --tags deploy` за runbook'ом піднімає
Umami на staging.hart.crimea.ua і телеметрія (Sentry/Umami/digest) оживає
від самих env-значень — без подальших правок коду.

ОБМЕЖЕННЯ

- Umami: офіційний образ umami-software/umami (postgresql), БД — ОКРЕМА база
  у НАЯВНОМУ Postgres-контейнері (ADR-032 §4; нового datastore НЕ створювати).
- RAM-бюджет MS21 (4 GB): mem_limit для umami ≤ 384m. Покажи у плані таблицю
  сумарних mem_limits усіх контейнерів — сума ≤ 3.2 GB, інакше STOP і обговорення.
- Секрети (APP_SECRET, SENTRY_DSN, DIGEST_WEBHOOK_URL, website_id) — ТІЛЬКИ
  через vault/.env; у репо — лише плейсхолдери в .env.example.
- Жодних міграцій drizzle (база umami — не наша schema; створення БД — Ansible-task
  або задокументований SQL, обґрунтуй вибір у плані).
- Жодних змін у apps/, packages/, workers/ (код готовий; якщо виявиш, що щось
  таки треба міняти в коді — STOP і повідом).
- Гілка infra/phase-3-3b-umami-deploy, Conventional Commits, один PR.

ДЕЛІВЕРАБЛИ
A. docker-compose.prod.yml: сервіс umami (image, env DATABASE_URL на окрему БД,
APP_SECRET з env, mem_limit, healthcheck, restart policy, залежність від postgres).
B. Caddyfile: analytics.hart.crimea.ua → umami (той самий патерн CF Origin Cert,
що й для основного сайту).
C. Ansible: створення БД umami у postgres (idempotent), нові env у темплейтах
.env (SENTRY_DSN ×3 сервіси, NEXT_PUBLIC_UMAMI_SRC=https://analytics.hart.crimea.ua/script.js,
NEXT_PUBLIC_UMAMI_WEBSITE_ID, DIGEST_WEBHOOK_URL, UMAMI_APP_SECRET) —
значення з vault, у репо плейсхолдери.
D. .env.example — ті самі ключі з коментарями.
E. docs/08_DEPLOYMENT.md — новий розділ «Телеметрія»: чеклист активації
(див. МАНУАЛЬНІ КРОКИ) + як перевірити, що все живе.
F. docs/11_OBSERVABILITY.md — TODO про деплой → done/статус. ПОПУТНО у §11
виправ статус PR 2 на ✅ (косметичний хвіст merge-ланцюга Phase 3.3:
самопозначку #55 було дропнуто при rebase).
G. Цей файл (docs/promts/phase-3-3-b-activation.md) — включити у PR
(конвенція: промпти фаз живуть у docs/promts/).

МАНУАЛЬНІ КРОКИ YURII (виведи наприкінці як чеклист у PR description):

1. Cloudflare DNS: A/CNAME analytics.hart.crimea.ua (proxied).
2. Sentry: створити 3 проєкти (web/api/worker) → DSN → vault.
3. Discord: створити webhook каналу для digest → vault.
4. openssl rand -base64 32 → UMAMI_APP_SECRET → vault.
5. ansible-playbook ... --tags deploy.
6. В Umami UI: створити website → скопіювати website_id → vault → повторний deploy.
7. Перевірка: відкрити staging, клікнути по студії → подія у Umami dashboard;
   кинути тестовий error → Sentry; дочекатись нд 18:00 → digest у Discord.

ТЕСТИ

- ansible-lint --profile production + --syntax-check зелені (як у CI).
- docker compose -f infra/compose/docker-compose.prod.yml config — валідний.
- Existing CI (lint/test) — нуль регресій (код не чіпаємо).

ПОЧАТОК

1. Покажи ПЛАН: diff-намітки по A-G + RAM-таблиця + спосіб створення БД umami.
2. Дочекайся OK від yurii. 3. Виконуй. 4. gh pr create --fill з чеклистом
   мануальних кроків. 5. STOP — деплой виконує yurii руками за docs/08.
