# Master Run 16 — переїзд staging на новий сервер Mirohost (Польща)

> **Режим:** автономний headless-прогін на T470 (`claude -p`), уночі, без людини поруч.
> **Модель:** Opus — живий сервер, відновлення БД, рішення «STOP чи далі».
> **Гілка:** `fix/migrate-staging-pl` від свіжого `origin/main`, робоча тека `~/hart-wt/migrate-pl`.
> **Працюй за CLAUDE.md §0.**
>
> **Іменна згода yurii** на цей прогін: дії з новим сервером через псевдонім `flatcraft-pl`;
> `git rm infra/inventory.ini` і рядок у `.gitignore`; ADR-042 і примітка до ADR-011 у
> `docs/03_DECISIONS.md`; тексти `/privacy` (uk, en); `docs/08`, `docs/09`, `docs/13`.
> Ролі й змінні Ansible (`infra/ansible/roles/**`, `group_vars/**`) — **поза згодою**, крім
> одного випадку, названого в КРОЦІ 1 (fail2ban), і лише якщо його ввімкнено при запуску.

## 0. Що сталося і що має вийти

Київський сервер staging знищено. Новий сервер Mirohost у Польщі: Debian 12, hostname
`flatcraft-staging-pl`. yurii перед сном уже зробив (розділ «Перед запуском»): псевдонім
`flatcraft-pl` у `~/.ssh/config` (root, ключ), deploy-ключ сервера доданий на GitHub,
gitignored `infra/ansible/inventory.ini` із псевдонімом, файл зі шляхами до секретів.

**Мета ночі** — усе, що можна зробити без DNS і без секретів GitHub:

1. сервер налаштований Ansible-ролями, стек `Up`/`healthy`;
2. БД відновлена з останнього R2-бекапу, числа звірені;
3. сайт і API відповідають **на самому сервері** (через Caddy, в обхід DNS);
4. бекап з нового сервера доходить у R2;
5. draft PR із документацією, ADR-042, `/privacy`, звітом і ранковими кроками yurii.

**Уранці — yurii** (класу A, не твої): DNS у Cloudflare, `STAGING_HOST` у GitHub, запуск
деплою, пароль Umami, merge. Ти ці кроки лише описуєш.

## 1. Жорсткі правила

1. **IP сервера тобі не потрібен і ніде не пишеться.** Сервер — лише `flatcraft-pl`. Репо
   публічне, а Cloudflare-проксі й UFW (80/443 лише від CF) мають сенс, доки origin IP
   невідомий. IP живе тільки в `~/.ssh/config`, `~/.flatcraft/leak/origin-host`, у секреті
   `STAGING_HOST` і в Cloudflare. **Оракул витоку** — перед кожним `git push`, перед
   `gh pr create` і перед коментарем в issue:
   `git log -p origin/main..HEAD | grep -cFf ~/.flatcraft/leak/origin-host` → `0`; для тексту PR і
   коментаря — те саме через `gh pr view <N> --json body --jq .body | grep -cFf …` і файл
   чернетки. Не `0` → прибери, а не пуш. Сам файл `origin-host` не читай і не друкуй — лише
   `grep -f`.
2. **Секрети — лише шляхами з оточення:** `$VAULT_PASS_FILE`, `$AGE_KEY_FILE`. Не друкуй
   вміст жодного секрету: ні локально, ні на сервері. Заборонено: `ansible-vault view`,
   прапорці `-v…` в `ansible-playbook` (друкують аргументи модулів), читання
   `/srv/flatcraft/.env.prod`, `rclone.conf`, ключів. Неправильний vault-пароль сам зупинить
   `ansible-playbook` на завантаженні змінних, до будь-якої дії на сервері.
3. **На сервер — лише root через `flatcraft-pl`.** Ніколи `ssh deploy@…`: у T470 може не
   бути ключа deploy-користувача, а fail2ban після 3 невдалих входів банить IP на годину —
   і T470 втрачає доступ до сервера зовсім, разом із root.
4. **Ролі Ansible не «адаптуй».** Впало — STOP, крім одного випадку в КРОЦІ 1.
5. **STOP зі звітом, не обхід:**
   - будь-яка таска Ansible з `failed`/`unreachable` (крім випадку fail2ban, якщо його ввімкнено);
   - `pg_restore` із кодом ≠ 0 або з рядками `error`;
   - порожня таблиця там, де бекап не порожній;
   - потрібна дія поза дозволеним списком (відмова в дозволі) — у звіт дослівну команду, без
     «спробую інакше»;
   - потрібна дія класу A (DNS, секрети GitHub, налаштування репо) — це ранковий крок yurii.

   STOP означає: `BLOCKED.md` у корені гілки з тим, що зроблено, де зупинився, дослівний
   вивід помилки (без IP і секретів) і що робити далі → коміт → оракул витоку → push →
   `gh pr create --draft` з префіксом `[BLOCKED]` → кінець.

6. **Прогрес — рядками `ПРОГРЕС: …`** на початку рядка у твоїх повідомленнях, по одному на
   кожен крок і підкрок (yurii стежить за ними фільтром). Обов'язкові дослівно:
   `ПРОГРЕС: КРОК 0 — OK` і `ПРОГРЕС: КРОК 1 — почато` (за ними yurii вирішує, що можна
   спати). STOP — рядком `STOP: …`.
7. **Довгі команди.** Ліміт однієї команди — 60 хв (`BASH_MAX_TIMEOUT_MS`), став `timeout`
   явно. Великий вивід веди в `~/hart-logs/` через `tee ~/hart-logs/<ім'я>.log` і показуй
   лише хвіст (`tail -n 60`). Шлях пиши саме як `~/hart-logs/…`: так його пропускає дозвіл.
   **Кожна** команда `ansible-playbook` і `ansible-galaxy` — з `2>&1`: без нього в headless
   ansible падає з «Ansible requires blocking IO … <stderr>» (виміряно на T470 2026-09-24).
8. **Тексти для GitHub — файлами в `~/hart-logs/`:** тіло PR — `~/hart-logs/migrate-pl-pr-body.md`,
   коментар — `~/hart-logs/migrate-pl-78.md`. Оракул витоку на файл
   (`grep -cFf ~/.flatcraft/leak/origin-host <файл>` → `0`), потім
   `gh pr create --draft --base main --title "…" --body-file …` і
   `gh issue comment 78 -R stjurik/flatcraft --body-file …`. Порядок аргументів саме такий:
   так команди пропускає дозвіл.

## 2. КРОК 0 — preflight (лише читання)

Звіт — таблицею «перевірка / очікування / факт». Будь-яке «не так» — STOP.

| Перевірка                                                                                                                                                        | Очікування                                                                                                                                 |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `git status --porcelain`; `git merge-base HEAD origin/main` = `git rev-parse origin/main`                                                                        | чисто; гілка від свіжого `origin/main`                                                                                                     |
| `test -r "$VAULT_PASS_FILE" && test -r "$AGE_KEY_FILE" && test -r ~/.flatcraft/leak/origin-host && echo ok`                                                      | `ok` (лише наявність, не вміст)                                                                                                            |
| `ansible-playbook --version 2>&1`; `ansible-galaxy collection list 2>&1` (community.general, community.docker, ansible.posix); `age --version`; `gh auth status` | ansible-core 2.16.x; три колекції є                                                                                                        |
| `ssh flatcraft-pl 'hostname; cat /etc/debian_version; nproc; free -h; df -h /'`                                                                                  | `flatcraft-staging-pl`, `12.x`. **Цифри CPU / RAM / диск — у звіт і в ADR-042**                                                            |
| `ssh flatcraft-pl 'runuser -u deploy -- ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -T git@github.com'`                                             | «successfully authenticated» (код 1 для `-T` — норма). Інакше STOP: без цього ключа роль `flatcraft` впаде на `git clone` (`docs/08` §1.5) |
| `git check-ignore -v infra/ansible/inventory.ini`; `grep -c flatcraft-pl infra/ansible/inventory.ini`                                                            | ігнорується; `1`                                                                                                                           |
| `grep -rn "infra/inventory.ini" --exclude-dir=node_modules --exclude-dir=.git .`                                                                                 | лише два deny-рядки в `.claude/settings.a8.json` — це заборони, а не споживачі. Будь-що інше — STOP                                        |

Зафіксуй `RUN_START` з оточення — він потрібен у КРОЦІ 2.

## 3. КРОК 1 — налаштування сервера

1. `cd infra/ansible && ansible-playbook site.yml --syntax-check 2>&1`.
2. Повний прогін, `timeout` 3600000 мс:
   `cd infra/ansible && ansible-playbook -i inventory.ini site.yml --vault-password-file "$VAULT_PASS_FILE" 2>&1 | tee ~/hart-logs/migrate-pl-ansible-1.log | tail -n 60`.
   Оракул — `PLAY RECAP`: `failed=0 unreachable=0`.
3. **Єдиний дозволений виняток — fail2ban** (лише якщо при запуску `F2B_FIX=yes`): таска
   `Enable and start fail2ban` впала, а причина в лозі — відсутній лог sshd (на Debian 12 без
   rsyslog журнал лише в journald). Тоді в `infra/ansible/roles/base/tasks/main.yml`, у
   `content` таски `Configure fail2ban for sshd`, додай один рядок `backend = systemd` під
   `[sshd]` → окремий коміт `fix(ansible): fail2ban читає journald на Debian 12` → повтори
   пункт 2. Будь-яка інша причина або `F2B_FIX` ≠ `yes` — STOP.
4. Ідемпотентність і шлях GitHub-деплою: та сама команда, що в п.2, з `--tags deploy` (саме так
   деплоїть `deploy-staging.yml`), `2>&1` і логом `~/hart-logs/migrate-pl-ansible-2.log` → `failed=0`.
5. Стан: `ssh flatcraft-pl 'docker ps --format "{{.Names}} {{.Status}}"'` → усі `Up`, де є
   healthcheck — `healthy`. Ключ CI на сервері:
   `ssh flatcraft-pl 'grep -c flatcraft-ci /home/deploy/.ssh/authorized_keys'` → `1`.

## 4. КРОК 2 — відновлення БД з R2

Відмінності від `docs/08` §5.5 навмисні, кожна з причиною:

- **rclone — на сервері.** Роль `backups` уже поклала туди конфіг R2, локальний не потрібен.
- **Бекап — найновіший із часом РАНІШЕ за `RUN_START`.** Крон бекапу на новому сервері
  (03:00 Europe/Kyiv) міг уже вивантажити дамп майже порожньої бази. Найновіший файл у
  бакеті може виявитись саме ним.
- **Базу перестворюємо, а не `--clean`.** API на першому старті вже застосував міграції
  новіші за бекап. `--clean` видаляє лише об'єкти з дампу, нові таблиці лишаються. Журнал
  міграцій із бекапу каже «їх ще немає», тож на наступному старті міграція впаде на
  «relation already exists». Порожня база + restore → API на старті сам доганяє нові міграції
  (`infra/docker/api-entrypoint.sh`: migrate + seed на кожен старт).
- **`--single-transaction`:** або вся база, або нічого.
- **Відкритий дамп — у `/root`, не в `/tmp`:** `/tmp` читають усі користувачі сервера.

Нижче `<C>` — лише скорочення в цьому тексті для
`cd /srv/flatcraft && docker compose --env-file .env.prod -f infra/compose/docker-compose.prod.yml`.
У командах пиши його повністю: змінні оболонки між викликами не зберігаються. `rclone` на
сервері запускай від root із явним `--config /home/deploy/.config/rclone/rclone.conf`.

1. `ssh flatcraft-pl 'rclone --config /home/deploy/.config/rclone/rclone.conf lsl r2:flatcraft-backups/'`
   → обери файл за правилом вище (час у назві `flatcraft-db-<РРРРММДДTГГХХССZ>` порівнюється з
   `RUN_START` як рядок). У звіт: ім'я, час, розмір і розміри трьох попередніх. Різко менший
   за попередні — STOP.
2. Завантаж його на сервер у `/root/` (`rclone copy`) → `scp flatcraft-pl:/root/<файл> ~/.flatcraft/backups/`
   → на сервері `rm` зашифрованої копії. Зашифрована копія на T470 лишається: це позамайданна
   копія на випадок, якщо R2 її прибере.
3. Розшифруй локально: `age -d -i "$AGE_KEY_FILE" -o ~/.flatcraft/tmp/restore.dump ~/.flatcraft/backups/<файл>`.
4. `scp ~/.flatcraft/tmp/restore.dump flatcraft-pl:/root/restore.dump` →
   `ssh flatcraft-pl chmod 600 /root/restore.dump`.
5. `<C> stop api cad-worker web` на сервері (postgres і umami працюють далі: Umami має свою
   базу `umami`).
6. Перестворити базу застосунку в контейнері postgres: з'єднання з базою `postgres`,
   `DROP DATABASE "$POSTGRES_DB" WITH (FORCE)`, потім `CREATE DATABASE "$POSTGRES_DB" OWNER "$POSTGRES_USER"`.
   Змінні — ті, що вже є в оточенні контейнера (як у `docs/08` §5.5), значень не друкуй.
7. `pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --single-transaction` з
   `/root/restore.dump` на stdin через `<C> exec -T postgres sh -c '…'`. Код ≠ 0 або `error` —
   STOP (сайт ще не публічний: DNS дивиться на старий IP, шкоди немає).
8. `<C> up -d api cad-worker web` на сервері → дочекайся `healthy` в `api` (до 5 хв).
   У лозі `api` — рядки migrate/seed без помилок.
9. Числа: `select count(*)` з `templates`, `products`, `exports`, `export_feedback`, `events`.
   Відсутня таблиця — у звіт як факт. Порожні `exports` при непорожньому бекапі — STOP.
10. `shred -u ~/.flatcraft/tmp/restore.dump` і `ssh flatcraft-pl shred -u /root/restore.dump`.

Бази `umami` у бекапах немає: `backup.sh.j2` дампить лише `$POSTGRES_DB`. Umami стартує
з чистою історією — не виправляй, це пункт «Опитування».

## 5. КРОК 3 — перевірка на самому сервері (до DNS)

Через Caddy на сервері, в обхід DNS (UFW пускає 80/443 лише від Cloudflare, тож ззовні
сервер до перемикання DNS не видно):

- `ssh flatcraft-pl "curl -sk -o /dev/null -w '%{http_code}' --resolve staging.hart.crimea.ua:443:127.0.0.1 https://staging.hart.crimea.ua/"` → `200`;
- те саме для `https://api-staging.hart.crimea.ua/health` — тіло відповіді OK;
- `GET /v1/templates` (`docs/06`) через API → непорожній список (рахуй на сервері, напр.
  `grep -o '"slug"' | wc -l` усередині `ssh`: `jq` на сервері може не бути);
- бекап-оракул: `ssh flatcraft-pl 'runuser -u deploy -- env HOME=/home/deploy /usr/local/bin/flatcraft-backup.sh'`
  → `rclone lsl` показує новий `flatcraft-db-*.dump.age` із сьогоднішнім часом і розміром,
  близьким до відновленого. Так доведено, що наступна аварія не зітре дані.

## 6. КРОК 4 — draft PR `fix/migrate-staging-pl`

1. `git rm infra/inventory.ini` (застарілий IP київського сервера в публічному git) і рядок
   `infra/inventory.ini` у `.gitignore` поруч з іншими inventory. Deny-рядки в
   `.claude/settings.a8.json` не чіпай: заборона на неіснуючий файл нічого не ламає.
2. **ADR-042** у `docs/03_DECISIONS.md` «Staging у ДЦ Mirohost у Польщі після знищення
   київського сервера» + рядок в індексі:
   - контекст;
   - рішення;
   - виміряні CPU / RAM / диск з КРОКУ 0; назва тарифу — з `$SERVER_PLAN`, порожня → «НЕ ПЕРЕВІРЕНО», **не «MS21»**;
   - наслідки: юрисдикція ЄС для GDPR, затримка з України, втрата історії Umami, дані між
     останнім бекапом і аварією;
   - альтернативи.

   ADR-011 — примітка «частково змінено ADR-042»: вибір Mirohost і Ansible-підхід чинні, ДЦ і
   тариф — ні. ADR-041 (Proposed) — одне речення про зв'язок. Без IP.

3. `/privacy` (`apps/web/src/app/privacy/page.tsx` ≈61-62, `privacy/en/page.tsx` ≈57-58):
   «ДЦ Mirohost у Києві» → «ДЦ Mirohost у Польщі (ЄС)». «Суверенітет даних» перепиши чесно:
   хостер український, дані в ЄС. Банер «Драфт» лишається. e2e ці рядки не перевіряють
   (звірено `apps/web/tests/e2e/privacy.spec.ts`) — підтверди `grep`.
4. `docs/08`: §0.1 п.3 (ДЦ); §0.6 і §0.8 `api.staging` → `api-staging`. Ім'я з коду —
   `group_vars/all.yml`, `Caddyfile`, smoke у `deploy-staging.yml`: wildcard-сертифікат
   `*.hart.crimea.ua` покриває лише один рівень, тому `api.staging` не працював би. Абзац
   ризиків наприкінці «якщо ДЦ у Києві…» — ризик стався, опиши фактом. `docs/09`: ті самі
   `api.staging` і вибір ДЦ.
5. `docs/13_PROGRESS_LOG.md` — запис нагору. `CLAUDE.md` правити заборонено: готовий текст
   для §1 («тариф MS21…») і §13 (інваріант «Hosting: Mirohost Cloud MS21») дай у PR.
6. Перевірки: `pnpm install --frozen-lockfile`, `pnpm --filter web typecheck`,
   `pnpm --filter web test`, `pnpm exec prettier --check` на змінених файлах — числа в PR.
7. Оракул витоку (правило 1) → push → `gh pr create --draft --base main`.
8. Мануальні кроки → коментар в issue #78 («Черга yurii») одразу після створення PR, з
   посиланням на PR. Оракул витоку — і на текст коментаря.

**Розділи PR:**

- **Звіт:** таблиці КРОКІВ 0–3 з фактами, бекап (ім'я, час, розмір), числа restore.
- **Ранкові кроки yurii** — нумеровано, простими словами:
  1. Cloudflare → DNS: A-записи `staging` і `api-staging` → новий IP, **Proxied (оранжева
     хмара)**. `analytics` — **поки не чіпати** (крок 5). Переглянути, чи немає записів
     DNS-only зі старим IP (наприклад `staging-direct`): такий запис публічно показує origin
     IP — видалити.
  2. `gh secret set STAGING_HOST -R stjurik/flatcraft` — вставити IP, коли спитає (не
     аргументом команди: так IP не потрапить в історію терміналу).
  3. Запустити деплой і дочекатися зеленого smoke:
     `gh workflow run deploy-staging.yml -R stjurik/flatcraft`, потім `gh run watch`.
  4. «Як перевірити очима» (нижче).
  5. Umami: запис `analytics` → новий IP, Proxied, і **одразу** увійти на
     `analytics.hart.crimea.ua` (`admin` / `umami`) → змінити пароль. Нова база Umami має
     пароль за замовчуванням, і до зміни будь-хто може увійти в аналітику.
  6. GitHub → Settings → Deploy keys: видалити старий ключ київського сервера (новий
     лишається).
  7. PR → рецензія хмарною сесією Claude (безпековий/інфраструктурний PR, CLAUDE.md §0 п.2) → merge.
- **Опитування:**

  | #   | Питання                                                                                            | Варіанти                                    | ★   | Дефолт |
  | --- | -------------------------------------------------------------------------------------------------- | ------------------------------------------- | --- | ------ |
  | 1   | Додати БД `umami` у щоденний бекап?                                                                | (a) окремий PR ★ / (b) прийняти втрату      | (a) | (a)    |
  | 2   | Umami: новий `website_id` після чистої бази — старий більше не існує, трекер шле події в нікуди    | (a) issue: сайт в Umami → vault → rebuild ★ | (a) | (a)    |
  | 3   | Restore-тест бекапу за розкладом (TODO `roles/backups/README.md:41`) — сьогодні він пройшов уперше | (a) issue у T5 ★ / (b) лишити TODO          | (a) | (a)    |

- **Як перевірити очима:**
  1. https://staging.hart.crimea.ua відкривається, каталог шаблонів на місці.
  2. https://api-staging.hart.crimea.ua/health відповідає OK.
  3. Студія L-кронштейна → експорт → DXF і PDF скачуються.
  4. QR у PDF веде на `/f/<id>`, форма фідбеку відкривається.
  5. `/privacy` і `/privacy/en` кажуть «Польща (ЄС)» — **після merge цього PR і деплою**.
  6. `dig +short staging.hart.crimea.ua` — адреси Cloudflare, не новий IP.
  7. У R2 є бекап із сьогоднішньою датою.
  8. Actions → «Deploy to staging» — останній прогін зелений.
  9. У PR немає IP сервера (оракул витоку дав `0`).
- **Рецензія:** хто рецензує (шлях 2, CLAUDE.md §0 п.2).

## 7. Не роби

- DNS, секрети й налаштування GitHub, Cloudflare — ранкові кроки yurii (правило 5).
- Не мерджи, не роби PR готовим до рев'ю, не пуш у `main`, без `--force`.
- Не чіпай `CLAUDE.md`, `.github/`, `infra/compose/`, `group_vars/`, ролі (крім винятку fail2ban).
- Не видаляй зашифрований бекап з R2 і з `~/.flatcraft/backups/`.

---

## Перед запуском (yurii, ~20 хв, до сну)

Робить yurii, не агент. Кожен блок — з очікуваним виводом; якщо вивід інший — не запускати.

**0. ansible-core 2.16, як у CI** (`deploy-staging.yml`: `ansible-core>=2.16,<2.17`; `docs/08`
§1.1 — через pipx). На інших версіях ролі не проганялись, і КРОК 0 зупиниться:

```bash
ansible-playbook --version 2>&1 | head -1 && ansible-galaxy collection list 2>&1 | grep -E '^(community\.general|community\.docker|ansible\.posix) '
```

Очікування: `ansible-playbook [core 2.16.x]` і три рядки колекцій. Інша версія →
`python3 -m pip uninstall -y --break-system-packages ansible-core && pipx install --force "ansible-core==2.16.*"`
і повторити перевірку. Колекцій немає (після зміни версії їх може не бути видно) →
`ansible-galaxy collection install community.general community.docker ansible.posix`.

**1. Псевдонім сервера й файл для оракула витоку.** IP вводиться лише тут, у терміналі:

```bash
read -r -p "IP нового сервера: " NEWIP && mkdir -p ~/.flatcraft/backups ~/.flatcraft/tmp ~/.flatcraft/leak ~/hart-logs && chmod 700 ~/.flatcraft ~/.flatcraft/tmp ~/.flatcraft/leak &&
printf '%s\n' "$NEWIP" > ~/.flatcraft/leak/origin-host && chmod 600 ~/.flatcraft/leak/origin-host &&
{ grep -q '^Host flatcraft-pl$' ~/.ssh/config 2>/dev/null || printf '\nHost flatcraft-pl\n  HostName %s\n  User root\n  IdentityFile ~/.ssh/id_ed25519\n  IdentitiesOnly yes\n' "$NEWIP" >> ~/.ssh/config; } &&
chmod 600 ~/.ssh/config && ssh flatcraft-pl 'hostname; cat /etc/debian_version'
```

Очікування: `flatcraft-staging-pl` і `12.x`.

**2. Deploy-ключ сервера для GitHub** (`docs/08` §1.5; без нього роль `flatcraft` не
завантажить код):

```bash
ssh flatcraft-pl 'id deploy >/dev/null 2>&1 || useradd -m -s /bin/bash deploy; install -d -m 700 -o deploy -g deploy /home/deploy/.ssh; test -f /home/deploy/.ssh/id_ed25519 || runuser -u deploy -- ssh-keygen -q -t ed25519 -N "" -C deploy@flatcraft-staging-pl -f /home/deploy/.ssh/id_ed25519; cat /home/deploy/.ssh/id_ed25519.pub'
```

Показаний рядок `ssh-ed25519 …` → GitHub → репозиторій → Settings → Deploy keys → Add deploy
key: назва `flatcraft-staging-pl`, **Allow write access — вимкнено**. Перевірка:

```bash
ssh flatcraft-pl 'runuser -u deploy -- ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -T git@github.com'
```

Очікування: `Hi stjurik/flatcraft! You've successfully authenticated…`

**3. Шляхи до секретів** (лише шляхи; сам age-ключ — з менеджера паролів у файл із правами
600, після ночі видалити):

```bash
read -r -e -p "Файл з vault-паролем: " VP && test -r "$VP" &&
read -r -e -p "Файл з age private key: " AK && test -r "$AK" &&
read -r -p "Назва тарифу (можна порожньо): " PLAN &&
printf 'VAULT_PASS_FILE=%q\nAGE_KEY_FILE=%q\nSERVER_PLAN=%q\n' "$VP" "$AK" "$PLAN" > ~/.flatcraft/migrate-pl.env && chmod 600 ~/.flatcraft/migrate-pl.env && echo "env OK"
```

**4. Робоча тека, промпт, inventory з псевдонімом:**

```bash
cd ~/hart && git fetch -q origin main claude/agent-orchestration-planning-w06nh9 &&
git worktree add -q ~/hart-wt/migrate-pl -b fix/migrate-staging-pl origin/main &&
git show origin/claude/agent-orchestration-planning-w06nh9:docs/promts/master-run-16-migrate-staging-pl.md > ~/.flatcraft/migrate-pl.prompt.md &&
printf '[staging]\nstaging-server ansible_host=flatcraft-pl ansible_user=root\n\n[staging:vars]\nansible_python_interpreter=/usr/bin/python3\n' > ~/hart-wt/migrate-pl/infra/ansible/inventory.ini &&
git -C ~/hart-wt/migrate-pl check-ignore -q infra/ansible/inventory.ini && echo "inventory OK, git його ігнорує"
```

**5. Ноутбук не засинає до ранку** (від мережі; кришку не закривати):

```bash
powershell.exe -NoProfile -Command "powercfg /change standby-timeout-ac 0; powercfg /change hibernate-timeout-ac 0" && echo "сон вимкнено"
```

## Запуск

`F2B_FIX=yes` — дозвіл на єдиний виняток КРОКУ 1 (fail2ban). Без нього — `F2B_FIX=no`.

```bash
cd ~/hart-wt/migrate-pl && set -a && . ~/.flatcraft/migrate-pl.env && set +a &&
export RUN_START="$(date -u +%Y%m%dT%H%M%SZ)" F2B_FIX=yes BASH_DEFAULT_TIMEOUT_MS=1800000 BASH_MAX_TIMEOUT_MS=3600000 &&
ALLOW=(Read Glob Grep Edit Write "Write(~/hart-logs/**)" "Edit(~/hart-logs/**)"
  "Bash(git:*)" "Bash(cd:*)" "Bash(ls:*)" "Bash(test:*)" "Bash(grep:*)" "Bash(tail:*)" "Bash(wc:*)"
  "Bash(date:*)" "Bash(echo:*)" "Bash(ssh flatcraft-pl *)" "Bash(scp flatcraft-pl:/root/*)" "Bash(scp ~/.flatcraft/tmp/* flatcraft-pl:/root/*)"
  "Bash(ansible-playbook:*)" "Bash(ansible-galaxy collection list*)" "Bash(age -d *)" "Bash(age --version)"
  "Bash(shred -u *)" "Bash(tee ~/hart-logs/*)" "Bash(mkdir -p ~/.flatcraft/*)" "Bash(pnpm:*)"
  "Bash(gh auth status*)" "Bash(gh pr create --draft *)" "Bash(gh pr view *)" "Bash(gh pr list *)"
  "Bash(gh issue comment 78 *)") &&
DENY=("Bash(git push --force*)" "Bash(git push -f*)" "Bash(git push * --force*)" "Bash(git push origin main*)"
  "Bash(git push * HEAD:main*)" "Bash(gh pr merge*)" "Bash(gh pr ready*)" "Bash(gh secret*)" "Bash(gh api*)"
  "Bash(gh workflow*)" "Bash(gh repo*)" "Bash(gh auth login*)" "Bash(gh auth refresh*)" "Bash(docker*)"
  "Bash(sudo*)" "Bash(ansible-vault*)" "Bash(ansible-playbook *a8*)" "Bash(agy*)" "Bash(pnpm discord:apply*)"
  "Read(~/.ssh/**)" "Edit(~/.ssh/**)" "Write(~/.ssh/**)"
  "Edit(~/.flatcraft/**)" "Write(~/.flatcraft/**)" "Edit(~/.claude/**)" "Write(~/.claude/**)"
  "Edit(~/.gemini/**)" "Write(~/.gemini/**)" "Edit(~/.config/**)" "Write(~/.config/**)"
  "Edit(~/.bashrc)" "Write(~/.bashrc)" "Edit(~/hart/**)" "Write(~/hart/**)"
  "Edit(CLAUDE.md)" "Write(CLAUDE.md)" "Edit(.github/**)" "Write(.github/**)" "Edit(.claude/**)" "Write(.claude/**)"
  "Edit(packages/db/src/migrations/**)" "Write(packages/db/src/migrations/**)" "Edit(packages/db/src/schema.ts)"
  "Edit(workers/cad/tests/snapshots/**)" "Write(workers/cad/tests/snapshots/**)"
  "Edit(packages/cad-engine/data/bend-machine-esi.yaml)" "Edit(docs/12_TEMPLATE_CONTRACT.md)"
  "Edit(infra/compose/**)" "Write(infra/compose/**)" "Edit(infra/docker/**)" "Edit(infra/ansible/group_vars/**)"
  "Write(infra/ansible/group_vars/**)" "Edit(infra/ansible/inventory*)" "Write(infra/ansible/inventory*)"
  "Edit(infra/ansible/*.yml)" "Edit(infra/ansible/roles/a8/**)" "Edit(infra/ansible/roles/backups/**)"
  "Edit(infra/ansible/roles/docker/**)" "Edit(infra/ansible/roles/firewall/**)"
  "Edit(infra/ansible/roles/flatcraft/**)" "Edit(infra/ansible/roles/monitoring/**)") &&
echo "налаштування OK, RUN_START=$RUN_START"
[[ -n "${RUN_START:-}" ]] && nohup setsid claude -p --model opus --permission-mode acceptEdits --max-turns 300 \
  --add-dir ~/hart-logs ~/.flatcraft/leak \
  --output-format stream-json --verbose --allowedTools "${ALLOW[@]}" --disallowedTools "${DENY[@]}" \
  < ~/.flatcraft/migrate-pl.prompt.md > ~/hart-logs/migrate-pl-$RUN_START.jsonl 2>&1 &
echo "запущено: ~/hart-logs/migrate-pl-$RUN_START.jsonl"
```

Очікування: `налаштування OK, RUN_START=…` і `запущено: …`. Якщо першого рядка немає —
не запустилось нічого, пришліть вивід.

Чому саме так (виміряно оркестратором на T470 2026-09-24 короткими headless-прогонами):

- `--add-dir`: `grep`, `tee` і подібні команди Claude Code пускає лише до файлів у робочих
  теках сесії. `~/hart-logs` — для логів і текстів PR, `~/.flatcraft/leak` — лише для файла з
  IP (оракул витоку). Увесь `~/.flatcraft` не додається: там розшифрований дамп.
- `scp`: правило, що закінчується на `:*`, — це префікс, після якого йде пробіл. Тому
  `scp flatcraft-pl:*` не пропускає `scp flatcraft-pl:/root/…`, а `*` посередині такого правила —
  просто символ. Правила з `*` у кінці без двокрапки працюють як шаблон.
- Заборони `Read` для файла з IP немає: вона блокує і `grep -f`. Не читати IP — правило
  промпту; якщо IP потрапить у git чи PR, його зловить оракул.

Без `--dangerously-skip-permissions` (CLAUDE.md §6.2): чого немає в `ALLOW`, те агентові
відмовлено, і він зупиняється зі звітом. **Чесно про межі:** це запобіжник від помилок, а не
пісочниця. `git`, `pnpm` і `ssh` на сервер уміють виконати довільний код, тож рішучого агента
список не зупинить. Від випадкової дії він береже: від `merge`, force-push, секретів GitHub,
правки `CLAUDE.md`, ролей Ansible і домашніх тек.

**Стежити** (показує лише рядки `ПРОГРЕС`/`STOP`; вихід — Ctrl+C, прогін не зупиняється):

```bash
tail -n +1 -f ~/hart-logs/migrate-pl-*.jsonl | jq --unbuffered -rR 'fromjson? | select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' | grep --line-buffered -E '^(ПРОГРЕС|STOP)'
```

**Можна спати**, коли з'явились `ПРОГРЕС: КРОК 0 — OK` і `ПРОГРЕС: КРОК 1 — почато`
(зазвичай 5–10 хв). `STOP` у КРОЦІ 0 — лагодимо до сну.

**Уранці:** `gh pr list -R stjurik/flatcraft --draft --head fix/migrate-staging-pl` → PR,
розділ «Ранкові кроки yurii».
