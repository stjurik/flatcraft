# role: flatcraft

**Що робить:** деплоїть flatcraft-стек на підготовлений сервер. Запускається на `--tags deploy` (включається у повний run).

## Кроки

1. **Git checkout `{{ app_dir }}`**: `git clone` / `git pull` приватний repo `git@github.com:stjurik/flatcraft.git` гілки `main`. Потрібен лише для `infra/compose/docker-compose.prod.yml` + `infra/compose/Caddyfile`. Сам код програми — у docker images з ghcr.io.
2. **Render `.env.prod`** з template + vault. Файл owned by deploy, perms `0600` (тільки deploy + root читають).
3. **Install CF Origin Cert** у `/etc/caddy/cf-origin/{cert,key}.pem`. Key — root-only `0600`, cert — `0644` (он буде exposed через TLS handshake однаково).
4. **GHCR credential hygiene (крок 3b)** — `docker manifest inspect` перевіряє, чи наявний на хості креденшал ghcr.io взагалі працює; якщо відповідь `denied`/`unauthorized` — креденшал знімається (`docker_login: state=absent`), і pull іде анонімно. Умова звужена до цих двох сигнатур навмисно: мережевий збій не має права зносити справний токен. _Навіщо: 14–17.09.2026 три deploy'ї підряд впали з `error from registry: denied` на **публічному** образі — протермінований PAT, записаний при провізіонінгу 27.05, надсилався замість анонімного запиту._
5. **`docker compose pull`** окремо від up — якщо ghcr rate-limit'нуло, живий стек не валиться.
6. **`docker compose up -d`** з `remove_orphans` (прибрати старі сервіси, які зникли з compose-файлу).
7. **Wait for api healthy** — блокуємо повернення Ansible'у успіху до того, як стек реально обслуговує. До 60с polling (`docker inspect ... .State.Health.Status`).

## Handler

`Restart flatcraft stack` — спрацьовує при зміні `.env.prod` або CF cert. Робить `docker compose restart` (читає файли заново). НЕ `down + up`, щоб не лишати downtime > 5s.

## Чому git pull, а не template/copy для compose-файлу

Альтернатива — копіювати `docker-compose.prod.yml` + `Caddyfile` через Ansible `template/copy`. Обрали git pull тому що:

- **Один source of truth** — версія compose-файлу прив'язана до git SHA, який видно у CI release.
- **Easy rollback** — `git checkout <sha> && ansible-playbook --tags deploy`.
- **Auditability** — `git log` на сервері показує, що там реально стоїть.

Cost: потрібен GitHub deploy key (SSH ключ deploy-юзера → repo collaborator зі read-only access).

## Pre-flight (один раз)

1. На сервері: `sudo -u deploy ssh-keygen -t ed25519 -C deploy@hart` → запам'ятати pub key.
2. GitHub → Repo settings → Deploy keys → Add → paste pub key (read-only).
3. Тепер `git pull` під deploy-юзером працює без vault'у.
