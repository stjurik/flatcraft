# role: base

**Що робить:** базова підготовка Debian 12 сервера до запуску flatcraft-стеку.

## Кроки

1. **Apt + security**: оновлює пакети, ставить `fail2ban`, вмикає `unattended-upgrades` для security-only автозастосування CVE-патчів.
2. **Timezone + locale**: `Europe/Kyiv` + UTF-8.
3. **Swap 2 GB**: створює `/swapfile`, прописує в `fstab`, опускає `vm.swappiness` до 10. **Критично** — без swap'у на MS21 (4 GB RAM) при пікових експортах CadQuery OOM-killer вибиває postgres.
4. **Deploy user**: створює юзера `deploy` з SSH-ключами з vault, додає у sudoers (NOPASSWD на staging). Подальші Ansible-run'и підключаються як `deploy`, а не `root`.
5. **SSH hardening**: вимикає password-аутентифікацію, ChallengeResponse, дозволяє root login лише по ключу.
6. **Fail2ban**: banить IP після 3 невдалих SSH-спроб на 1 год — гасить шум від brute-force ботів.
7. **Каталоги**: `/srv/flatcraft`, `/var/lib/flatcraft/backups`, `/var/log/flatcraft`, `/etc/caddy/cf-origin/` (root-only 0700 — містить private key).

## Чому це окрема роль (не вмонтовано у `flatcraft`)

- Виконується лише при першому provision'і (`--tags provision`).
- Re-deploy через `--tags deploy` НЕ переторкається сюди — швидше, безпечніше.
- Будь-який інший проєкт у тому ж стилі може reuse'нути base без модифікацій.

## Що не робить (свідомо)

- **Не ставить Docker** — окрема роль `docker`.
- **Не відкриває firewall** — окрема роль `firewall` (запускається ПІСЛЯ створення deploy-юзера, бо ssh_allowed_ips має включати ваш IP).
- **Не торкається GitHub deploy keys** — це робиться вручну (один раз через `ssh-keygen` на сервері та copy-paste у GitHub repo settings).
