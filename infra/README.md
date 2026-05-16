# infra/

> Інфраструктура як код. Сервер створюється вручну в панелі Mirohost (Terraform-провайдера Mirohost не має — див. ADR-011), усе налаштування — декларативно через Ansible.

## Цільова інфраструктура

- **Сервер:** Mirohost Cloud, тариф **MS21** — 2 vCPU / 4 GB RAM / 40 GB SSD, дата-центр Київ. Root-доступ.
- **Сховище артефактів і бекапів:** Cloudflare R2 (S3-compatible). На 40 ГБ диска сервера зростаючі DXF/PDF/STEP **не зберігаємо** — тільки в R2.
- **DNS + проксі + SSL + WAF:** Cloudflare (геоблок RU/BY, приховування origin-IP, DDoS-захист).
- **Домен:** `hart.crimea.ua`.

## Структура

```
infra/
├── docker/
│   ├── web.Dockerfile
│   ├── api.Dockerfile
│   └── cad-worker.Dockerfile
├── compose/
│   ├── docker-compose.dev.yml      # для local dev
│   ├── docker-compose.prod.yml     # для сервера Mirohost Cloud
│   └── docker-compose.test.yml     # для CI integration tests
└── ansible/
    ├── inventory.ini.example       # IP сервера вписується вручну, реальний inventory не комітимо
    ├── site.yml                    # головний playbook
    ├── group_vars/
    │   └── all.yml.example         # змінні (без секретів)
    └── roles/
        ├── base/                   # пакети, swap (важливо при 4 GB RAM), unattended-upgrades
        ├── docker/                 # Docker + docker-compose plugin
        ├── firewall/               # ufw: дозволити лише 22, 80, 443 (Cloudflare IP ranges)
        ├── flatcraft/              # клон repo, .env з vault, docker compose up, systemd unit
        └── backups/                # cron + age + rclone → R2
```

## Передумови (один раз, вручну)

1. **Створити Cloud-сервер у панелі Mirohost** — тариф MS21, ОС Debian 12, SSH-ключ.
2. **Створити акаунт Cloudflare:**
   - R2 buckets: `flatcraft-artifacts`, `flatcraft-backups`.
   - Додати домен `hart.crimea.ua`, перемкнути NS на Cloudflare.
   - Country block для RU/BY (WAF rule).
3. **Запитати техпідтримку Mirohost**, чи дозволено/підтримується Docker на цьому тарифі (з root має бути ок).
4. Вписати IP сервера у `infra/ansible/inventory.ini` (скопіювати з `.example`).

## Запуск (Phase 5)

```bash
cd infra/ansible

# Повне налаштування сервера з нуля
ansible-playbook -i inventory.ini site.yml

# Тільки re-deploy коду (після Phase 5)
ansible-playbook -i inventory.ini site.yml --tags deploy
```

Після цього на сервері:

```bash
ssh deploy@<server-ip>
cd /srv/flatcraft
docker compose -f infra/compose/docker-compose.prod.yml pull
docker compose -f infra/compose/docker-compose.prod.yml up -d
```

## Особливості через обмеження тарифу MS21

- **RAM 4 GB** — Ansible role `base` обов'язково налаштовує swap (2 GB). У `docker-compose.prod.yml` CAD-worker має `CAD_WORKER_CONCURRENCY=1`.
- **Диск 40 GB** — role `base` ставить моніторинг disk usage з алертом на 80%. Артефакти й бекапи — тільки в R2. Docker — регулярний `docker image prune`.
- **Без Terraform** — якщо колись зміниться провайдер на той, що має TF-провайдер (Hetzner, AWS), додамо `infra/terraform/`. Поки — тільки Ansible.

## Секрети

- Ніколи не комітимо `inventory.ini`, `group_vars/all.yml` з реальними значеннями, `.env` з реальними секретами.
- Усі секрети — у 1Password / Bitwarden / `pass`. Назва запису = шлях у репо.
- На сервері `.env` створює Ansible з шаблону + Vault (`ansible-vault`).

## Backups

Щоденно (cron на сервері, role `backups`):

1. `pg_dump` → стиснення → шифрування `age` → upload у R2 bucket `flatcraft-backups` (через `rclone`).
2. Ретенція: 30 днів rolling (lifecycle rule на R2 bucket).
3. Раз на місяць — restore-test у staging.

Артефакти (DXF/PDF/STEP) у R2 bucket `flatcraft-artifacts` — lifecycle rule: видалення через 90 днів від останнього доступу (див. `docs/05_DATA_MODEL.md`, розділ ретенції).
