# role: backups

**Що робить:** ставить cron-job, що щодня о 03:00 робить `pg_dump`, шифрує `age`-ом, заливає в R2 bucket `flatcraft-backups`, і прибирає старе локально.

## Pipeline

```
pg_dump (docker exec) → gzip → age encrypt → rclone copy → r2://flatcraft-backups/
                                                       \--→ local /var/lib/flatcraft/backups/ (3 дні)
```

## Чому age, а не GPG

- **Single-key encrypt:** age — це WireGuard-у-світі-шифрування. Файл шифрується одним public key, розшифровується одним private key. Жодних web-of-trust, key servers, expiration headaches.
- **Mало моментів збою:** GPG має ~50 років legacy і десятки крайніх випадків (failing trust, broken pubring, etc). age — 10kB binary, не падає.
- **Поглядно текстове форматування рекомендованих ключів** (`age1...`) зручне для vault.

## R2 retention

Lifecycle rule налаштовується у CF dashboard вручну (Ansible не має валідного API для R2 lifecycle поки): bucket `flatcraft-backups` → Settings → Lifecycle → Expire objects → 30 days. Зробити це **одноразово** під час підготовки інфраструктури (див. `docs/08_DEPLOYMENT.md` E.0).

## Recovery

```bash
# 1. Pull encrypted dump з R2
rclone --config rclone.conf copy r2:flatcraft-backups/flatcraft-db-20260518T030000Z.sql.gz.age ./

# 2. Decrypt (приватний age-key — у Bitwarden, НЕ у vault'і)
age -d -i ~/secrets/age.key -o flatcraft-db-20260518.sql.gz \
    flatcraft-db-20260518T030000Z.sql.gz.age

# 3. Restore у Postgres (на свіжу базу!)
gunzip -c flatcraft-db-20260518.sql.gz | \
    docker compose -f docker-compose.prod.yml exec -T postgres \
    pg_restore -U flatcraft -d flatcraft --clean --if-exists
```

Раз на місяць — restore-test у staging. (TODO: автоматизувати через cron на іншому сервері.)

## Залежності

- **age** (apt-get install age, доступний з Debian 12).
- **rclone** (apt-get install rclone, конфіг рендериться у `/home/deploy/.config/rclone/rclone.conf` з vault'у).

## Що шукати у логах

`/var/log/flatcraft/backup.log` — кожен run, з timestamp і розміром dump'у. Logrotate тримає 4 тижні compress'ом.
