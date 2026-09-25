# BLOCKED — Master Run 16: переїзд staging на сервер Mirohost у Польщі

- Прогін: `RUN_START=20260925T081035Z`, гілка `fix/migrate-staging-pl` від `861f387` (`origin/main`).
- Сервер — лише псевдонім `flatcraft-pl`. IP у цьому файлі немає (оракул витоку — у PR).
- **Де зупинився:** КРОК 1, п.2 — повний прогін `site.yml` впав на ролі `monitoring`.
- **Що ще з'ясовано (лише читання):** бакет R2 `flatcraft-backups` **порожній** — навіть після
  ремонту КРОКУ 1 відновлювати БД (КРОК 2) нема з чого.
- **Код не змінено.** У гілці — лише цей файл. Ролі Ansible не чіпались, виняток fail2ban не
  застосовано (чому — нижче).

## 1. КРОК 0 — preflight: OK

| Перевірка                                          | Очікування                     | Факт                                                                                                         |
| -------------------------------------------------- | ------------------------------ | ------------------------------------------------------------------------------------------------------------ |
| `git status --porcelain`; merge-base               | чисто; від свіжого `main`      | чисто; merge-base = `origin/main` = `861f387`                                                                |
| vault-pass, age.key, leak/origin-host              | `ok`                           | `ok`                                                                                                         |
| ansible-core; колекції; age; gh                    | 2.16.x; 3 колекції             | core 2.16.19; ansible.posix 2.2.2, community.docker 4.8.8, community.general 11.4.9; age 1.1.1; gh — stjurik |
| сервер                                             | `flatcraft-staging-pl`, `12.x` | `flatcraft-staging-pl`, Debian 12.15                                                                         |
| CPU / RAM / диск (для ADR-042)                     | —                              | **4 vCPU, 7.7 GiB RAM, swap 0 (до Ansible), диск 79 GB (вільно 75 GB)**                                      |
| deploy-ключ → GitHub                               | successfully authenticated     | `Hi stjurik/flatcraft! You've successfully authenticated…`, код 1                                            |
| `infra/ansible/inventory.ini`                      | ігнорується; `1`               | `.gitignore:83`; `1`                                                                                         |
| посилання на `infra/inventory.ini`                 | лише 2 deny-рядки              | лише `.claude/settings.a8.json:29,30`                                                                        |
| `tee ~/hart-logs/…`; оракул витоку на порожній діф | `ok`; `0`                      | `ok`; `0`                                                                                                    |

## 2. КРОК 1 — STOP

`ansible-playbook site.yml --syntax-check` → `playbook: site.yml`. Повний прогін
(`~/hart-logs/migrate-pl-ansible-1.log`), дослівно:

```text
TASK [monitoring : Install monitor script] *************************************
An exception occurred during task execution. To see the full traceback, use -vvv. The error was: . Missing end of comment tag
fatal: [staging-server]: FAILED! => {"changed": false, "msg": "AnsibleError: template error while templating string: Missing end of comment tag. String: #!/usr/bin/env bash\n# {{ ansible_managed }}\n# flatcraft health monitor. … (далі весь текст шаблону — обрізано)"}

PLAY RECAP *********************************************************************
staging-server             : ok=71   changed=49   unreachable=0    failed=1    skipped=1    rescued=0    ignored=0
```

Це не випадок fail2ban → за правилами прогону STOP. П.3–5 КРОКУ 1 (виняток fail2ban,
`--tags deploy`) не виконувались.

### 2.1. Причина: `{#` у bash-шаблоні

`infra/ansible/roles/monitoring/templates/monitor.sh.j2:66`:

```bash
if [ ${#CURRENT_PROBLEMS[@]} -gt 0 ]; then
```

Для Jinja `{#` — початок коментаря, а кінця `#}` немає. Рядок у файлі з першого коміту
(`e19e5bf`, 2026-05-27, PR #1) і відтоді не змінювався, тож таска падає за будь-якого запуску
ролі `monitoring`. CI цього не бачить: job `ansible-validate` (`.github/workflows/ci.yml:163-188`)
робить лише `--syntax-check` і `ansible-lint`, а вони шаблонів не рендерять. Деплой із GitHub
(`--tags deploy`) роль `monitoring` не зачіпає.

**Відтворено локально, без сервера:** одноразовий playbook (`hosts: localhost`,
`connection: local`, фіктивні змінні) рендерить цей шаблон → та сама помилка, `failed=1`.

**Виправлення перевірено тим самим способом** на копії шаблону (у репо не записано: ролі поза
згодою цього прогону) — `failed=0`, у результаті рядок 66 дає правильний bash:

```diff
-if [ ${#CURRENT_PROBLEMS[@]} -gt 0 ]; then
+if [ {% raw %}${#CURRENT_PROBLEMS[@]}{% endraw %} -gt 0 ]; then
```

Інших `{#` у `infra/**/*.j2` немає (`grep`).

**Регресійний тест (§0 п.6), пропозиція:** крок у `ci.yml`, що рендерить кожен
`infra/ansible/roles/*/templates/*.j2` на localhost із фіктивними змінними. `.github/` —
поза згодою цього прогону.

### 2.2. Друга вада в тому самому скрипті (знайдено читанням; скрипт не запускався)

`monitor.sh.j2:57` кладе в поле `Health` значення `{{.Status}}`. На цьому сервері `.Status` має
вигляд `Up 22 minutes (healthy)` (вивід `docker ps` нижче). Рядок 54 порівнює його з `healthy`,
`starting` і `none` — отже, після ремонту Jinja **кожен** контейнер вважатиметься проблемним.
Скрипт один раз надішле алерт, залишиться в стані `PROBLEM` і більше не сповіщатиме, зокрема про
справжню аварію. Варіанти виправлення — розбирати `(healthy)` зі `.Status` або брати
`docker inspect -f '{{.State.Health.Status}}'`; жоден не перевірено.

### 2.3. fail2ban: не працює, але виняток не застосовано

Таска `Enable and start fail2ban` дала `changed`, **не `failed`**: systemd повертає керування
до того, як fail2ban падає на асинхронному читанні конфігурації. Сервіс мертвий, дослівно:

```text
$ systemctl status fail2ban
     Active: failed (Result: exit-code) since Fri 2026-09-25 11:15:30 EEST
   Main PID: 14376 (code=exited, status=255/EXCEPTION)
$ journalctl -u fail2ban
fail2ban [14376]: ERROR   Failed during configuration: Have not found any log file for sshd jail
fail2ban [14376]: ERROR   Async configuration of server failed
$ ls -l /var/log/auth.log
ls: cannot access '/var/log/auth.log': No such file or directory
$ dpkg -l rsyslog
un  rsyslog        <none>       <none>       (no description available)
```

Причина та, яку передбачав промпт (Debian 12 без rsyslog, журнал sshd лише в journald). Але
виняток дозволено за умови «таска впала», а вона не впала; до того ж STOP уже настав через
`monitoring`, і виправлення fail2ban сам прогін не розблокував би. Тому `backend = systemd` під
`[sshd]` у `roles/base/tasks/main.yml` **не додано**. Це ще один випадок «зелений ≠ виконаний
інваріант»: Ansible звітує OK, а сервіс мертвий. Пропозиція — після хендлерів додати таску, яка
перевіряє `fail2ban-client status sshd`.

Ризик, поки fail2ban не працює, низький: вхід за паролем вимкнено (роль `base`, лише ключі).

## 3. Бакет R2 порожній — КРОК 2 неможливий

Лише читання, з сервера, конфігом, який поклала роль `backups`. Дослівно:

```text
$ rclone --config /home/deploy/.config/rclone/rclone.conf lsl r2:flatcraft-backups/ | wc -l
0
$ rclone --config /home/deploy/.config/rclone/rclone.conf size r2:flatcraft-backups/
Total objects: 0 (0)
Total size: 0 B (0 Byte)
$ rclone --config /home/deploy/.config/rclone/rclone.conf lsd r2:
ERROR : : error listing: AccessDenied: Access Denied
	status code: 403, request id: , host id:
```

Тобто ключі з vault мають доступ до бакета `flatcraft-backups`, і бакет порожній. Переглянути
всі бакети ключам заборонено: токен обмежено переліченими бакетами (`docs/08` §0.4).

Можливі пояснення — **НЕ ПЕРЕВІРЕНО**, це гіпотези:

- (а) lifecycle «Expire 30 днів» (`docs/08` §0.3) прибрав усі дампи, бо старий сервер перестав
  їх робити понад 30 днів тому;
- (б) старий сервер жодного разу не вивантажив бекап: пункт чеклиста
  «R2 `flatcraft-backups` має хоч один файл `*.dump.age`» (`docs/08:1152`) не відмічений, а
  restore-тест досі в TODO (`roles/backups/README.md:41`);
- (в) бекапи лежать в іншому акаунті Cloudflare, ніж той, на який вказує R2-endpoint у vault.

Локальна тека `~/.flatcraft/backups/` на T470 — **НЕ ПЕРЕВІРЕНО**: команда `ls` для неї
потребувала дозволу, якого в цьому прогоні немає.

Бекап-оракул КРОКУ 3 (`flatcraft-backup.sh`) не запускався: він вивантажив би в R2 дамп
порожньої бази.

## 4. Стан сервера зараз

- Ролі `base`, `docker`, `firewall`, `flatcraft`, `backups` пройшли. `monitoring` зупинився на
  другій тасці: скрипта монітора, cron монітора, cron `docker image prune` і logrotate для них
  **немає**.
- Контейнери (`docker ps`): `caddy`, `web`, `api`, `umami`, `cad-worker`, `postgres`, `redis` —
  усі `Up … (healthy)`.
- БД застосунку — **свіжа**: лише міграції й seed, які API робить на старті. Даних користувачів
  немає.
- Ключ CI: `grep -c flatcraft-ci /home/deploy/.ssh/authorized_keys` → `1`.
- UFW: `Status: active`, `Default: deny (incoming)`; 66 правил для 80/443, жодне не
  `Anywhere`; 22/tcp відкритий. DNS досі вказує на старий IP, тож ззовні сайту й Umami не видно.
  Umami має пароль за замовчуванням: до перемикання DNS це не ризик, після — ризик (ранковий
  крок 5 з промпту лишається в силі).
- Cron бекапу `0 3 * * *` (deploy) **встановлено**: щоночі о 03:00 за Києвом у R2 піде дамп
  **свіжої** бази. Старих бекапів це не зачіпає: скрипт лише копіює в R2 і нічого там не
  видаляє (`backup.sh.j2:49-55`). Якщо бекап знайдеться деінде, правило «найновіший раніше за
  `RUN_START`» з КРОКУ 2 відсіче ці нові дампи.
- fail2ban — `failed` (п. 2.3). Swap створено (роль `base`).

## 5. Не зроблено

КРОК 1 п.3–4; КРОКИ 2 і 3 повністю; з КРОКУ 4 — ADR-042, примітка до ADR-011, `/privacy`,
`docs/08`, `docs/09`, `docs/13`, `git rm infra/inventory.ini`, коментар в issue #78 з ранковими
кроками. Ранкові кроки з промпту (DNS, `STAGING_HOST`, деплой) **зараз виконувати не варто**:
перемикання DNS опублікує staging із порожньою базою — див. опитування, п. 3.

## 6. Опитування

| #   | Питання                                                                      | Варіанти й наслідки                                                                                                                                                                                                                                                                                    | ★   | Дефолт при мовчанні                     | Оборотність                                        |
| --- | ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --- | --------------------------------------- | -------------------------------------------------- |
| 1   | Як лагодити `monitoring`?                                                    | (a) окремий PR: `{% raw %}` у рядку 66, виправлення рядка 57, рендер-тест шаблонів у CI; потім повтор Master Run 16 з КРОКУ 1 — ролі й CI правляться під рев'ю ★ / (b) повтор прогону з `--skip-tags monitoring`, ремонт окремо — переїзд швидше, але сервер без моніторингу невизначений час          | (a) | (a)                                     | обидва оборотні                                    |
| 2   | Застосувати `backend = systemd` для fail2ban, хоча таска формально не впала? | (a) так, у тому самому PR, що й п.1, плюс таска-перевірка `fail2ban-client status sshd` ★ / (b) окремий PR — ще одне рев'ю                                                                                                                                                                             | (a) | (a)                                     | оборотно                                           |
| 3   | Бекапу в R2 немає. Що з даними staging?                                      | (a) спершу шукати: CF dashboard → R2 (обидва бакети, lifecycle, історія об'єктів), інші акаунти, `~/.flatcraft/backups/`; прогін продовжувати лише після цього ★ / (b) прийняти втрату: КРОК 2 пропустити, ADR-042 фіксує втрату даних, QR-посилання `/f/{exportId}` у вже виданих PDF поведуть на 404 | (a) | **немає** — клас A, чекає рішення yurii | (b) незворотне, коли старі дані остаточно зникнуть |

## 7. Як продовжити

1. Відповісти на питання 3 (дані). Від нього залежить, чи буде КРОК 2 взагалі.
2. PR з виправленням `monitoring` (і fail2ban, якщо п.2 = a) → рев'ю → merge.
3. Повторити Master Run 16 з КРОКУ 1. Ролі ідемпотентні, сервер уже частково налаштований.
   Якщо бекап знайдеться, процедура КРОКУ 2 (перестворення бази + `pg_restore`) лишається
   правильною: API вже застосував свіжі міграції, саме цей випадок вона і покриває.
4. Лише після цього — ранкові кроки з промпту (DNS, `STAGING_HOST`, деплой, пароль Umami).

## 8. Як перевірити очима

1. `~/hart-logs/migrate-pl-ansible-1.log`, кінець файла: `PLAY RECAP … failed=1`, над ним
   `Missing end of comment tag`.
2. `infra/ansible/roles/monitoring/templates/monitor.sh.j2`, рядок 66: `${#` посередині рядка.
3. `ssh flatcraft-pl 'systemctl is-active fail2ban'` → `failed`.
4. Cloudflare → R2 → `flatcraft-backups` → Objects: 0 об'єктів (або вже є один дамп після
   03:00 — із сервера, він свіжої бази).
5. `ssh flatcraft-pl 'docker ps'` → сім контейнерів `healthy`.
6. У PR змінено лише `BLOCKED.md`.
7. У PR немає IP сервера (оракул витоку дав `0` на коміти і на текст PR).

## 9. Рецензія

Це звіт STOP: коду не змінено, рецензія не проводилась. Виправлення з п.2 і п.6 мають пройти
рецензію у своєму PR (CLAUDE.md §0 п.2: `agy` або окрема сесія Claude — інфраструктурний PR).
