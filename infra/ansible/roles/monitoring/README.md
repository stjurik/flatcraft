# role: monitoring

**Що робить:** простий бідняцький моніторинг без node_exporter/Grafana — bash-скрипт + cron + Discord webhook. Достатньо для одного staging-сервера.

## Що тригерить алерт

1. **`/` filesystem > 80%** (`monitor_disk_threshold_pct` у `all.yml`). Перевагу прискіпливості над ризиком повного диску на 40 GB MS21.
2. **Будь-який контейнер зі стека з health != "healthy"** (і != "starting" — щоб не спамити при роллах).
3. **Stack повністю лежить** (0 контейнерів з prefix'ом `flatcraft-`).

## State tracking — щоб не спамити

Скрипт пам'ятає попередній стан у `/tmp/flatcraft-monitor.state`:

- При першому виявленні проблеми → шле алерт у Discord.
- Поки проблема триває — мовчить (раз на 5 хв одного й того ж — це шум).
- Коли recover'илось → шле "recovered" повідомлення.

## Cron'и, що ставимо

1. `*/5 * * * *` — `flatcraft-monitor.sh` (кожні 5 хв).
2. `0 4 * * 0` — `docker image prune -af --filter 'until=168h'` (щонеділі 04:00; після backup'у 03:00). Звільняє ~2-5 GB після тижня release'ів.

## Discord webhook

Створити: канал → Settings → Integrations → Webhooks → New Webhook → копіювати URL у `vault_discord_webhook_url` (`group_vars/all.vault.yml`).

Скрипт шле embed із severity-color'ом і timestamp'ом:

- 🚨 червоний — нова проблема
- ✅ зелений — recover

## Чому НЕ node_exporter

- node_exporter + Prometheus + Grafana — 3 додаткових контейнери, ~300 MB RAM, окремий ingress, login.
- На MS21 з 4 GB RAM кожен MB рахується. Для 1 staging-сервера простий bash достатній.
- Якщо інфра масштабується (Phase 6+) — додамо node_exporter і Grafana Cloud (free tier).

## Логи

`/var/log/flatcraft/monitor.log` — кожен run, з підсумком. `prune.log` — щотижневий image cleanup. Logrotate тримає 4 тижні.
