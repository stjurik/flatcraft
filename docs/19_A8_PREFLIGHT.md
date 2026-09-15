# 19. A8 Preflight — автономне середовище розробки

> **Що це.** Мануальний чеклист для yurii: усе, що вимагає фізичного доступу, інтерактивного
> логіна або кнопки в чужій панелі. Аналог `docs/09_STAGING_PREFLIGHT.md`, але для машини A8.
>
> **Чого тут НЕМАЄ.** Ansible-роль `a8`, контейнер агента, демон-оркестратор, systemd-юніти,
> прев'ю-стек, бекап-скрипти, правки workflows — це робить master-run за промтом
> `docs/promts/master-a8-transition.md` (§6). Правило CLAUDE.md §0 п.5: руками — лише те,
> що не автоматизується.
>
> **Статус:** draft, підготовлено 2026-08-07. Джерело рішень — Опитування Q1–Q13 (§0.2).

---

## §0. Контекст

### 0.1. Що на виході

Після виконання цього документа існує машина A8, на якій:

1. Ubuntu Server 24.04 LTS, вмикається автоматично після зникнення живлення, не засинає.
2. Три системні користувачі з різними правами: `yurii` (адмін), `runner` (CI), `agent` (агенти).
3. Docker + toolchain (Node 22, pnpm, uv, системні залежності Playwright).
4. Зареєстрований self-hosted GitHub Actions runner — **лише після** переходу репо в private.
5. Робочі інтерактивні логіни: `claude setup-token`, `agy` (Gemini), `cloudflared`, Discord-бот.
6. Жодного відкритого вхідного порту з інтернету. Уся зв'язність — вихідна.
7. **Немає** пароля Ansible-vault, SSH-ключа до Mirohost і GHCR-токена на запис (§7 — інваріант).

Наступний крок після цього документа — master-run, який розгортає середовище агентів.

### 0.2. Рішення, прийняті до цього документа

| #   | Рішення                        | Значення                                              |
| --- | ------------------------------ | ----------------------------------------------------- |
| Q1  | Repo visibility                | **private зараз** (T5-1) → ADR-038                    |
| Q2  | Обсяг переносу CI              | лише важкі job на self-hosted                         |
| Q3  | Розморозка «Відкладено до A8»  | перші два пункти одразу                               |
| Q4  | Поріг рішення по prod-переїзду | зафіксувати числом ДО збору даних                     |
| Q5  | Співвідношення з Run 7         | A8-трек паралельно (файли не перетинаються)           |
| Q6  | Двигун агентів                 | локальний демон-супервізор, не Actions-джоба          |
| Q7  | Дефолт при мовчанні (клас B)   | так, таймер 6–12 год                                  |
| Q8  | Auto-merge                     | ★переглянуто на Q11                                   |
| Q9  | Ліміт автономії                | денний ліміт задач + kill switch                      |
| Q10 | Ізоляція агента                | контейнер + skip-permissions **всередині** контейнера |
| Q11 | Auto-merge у тестовому режимі  | оборотний клас + auto-revert; скасовується на launch  |
| Q12 | Прев'ю-середовища              | так, на A8 через Cloudflare Tunnel                    |
| Q13 | Оркестратор                    | тонкий супервізор + свіжа сесія на задачу             |

Ці рішення оформлюються як **ADR-038** (visibility), **ADR-039** (автономне середовище),
**ADR-040** (auto-merge у тестовому режимі з тригером скасування). ADR пише master-run —
цей документ на них лише посилається.

### 0.3. Порядок і залежності

```
Крок 0 (інвентаризація)  ──┐
                           ├─► Track A (Ubuntu) ─► Track B (база) ─► Track C (Docker)
Track D0 (deploy key)  ────┘                                              │
                                                                          ▼
Track D1 (private) ──────────────────────────────► Track D2 (runner) ─► Track D3-D6
                                                                          │
                                                                          ▼
                                                              master-run (§6)
```

**Жорсткі залежності (порушення = зламаний деплой або дірка в безпеці):**

- Runner реєструється **тільки після** переходу репо в private. Self-hosted runner на
  публічному репо означає, що чужий PR виконує довільний код на вашій машині.
- Перехід у private — **тільки після** перевірки D0 (deploy key живий).
- Токен runner'а живе ~1 годину: не генеруйте його заздалегідь.

**Можна робити паралельно:** Крок 0 і D0 — до всього; Track A–C не залежать від рішення
про visibility.

**Оцінка часу:** Крок 0 — 10 хв; Track A — 40–60 хв (з встановленням); Track B — 30 хв;
Track C — 30 хв (+ час завантаження образів); Track D — 40 хв. Разом ~3 години з паузами.

---

## §1. Крок 0 — інвентаризація A8 (ДО встановлення)

Від цих чисел залежать рішення в §6 (скільки прев'ю-середовищ тримати, чи вистачить
диска на кеші). Виконати з поточної ОС або з live-USB.

```bash
# CPU / ядра
lscpu | grep -E "Model name|^CPU\(s\)|Thread"

# RAM
free -h

# Диски
lsblk -o NAME,SIZE,TYPE,ROTA,MODEL      # ROTA=0 → SSD, ROTA=1 → HDD

# Мережа
ip -br a
ip route | head -3
```

**Запишіть відповіді (вони підуть у ADR-039 як факти, а не припущення):**

| Питання                          | Ваша відповідь |
| -------------------------------- | -------------- |
| CPU / ядра / потоки              |                |
| RAM                              |                |
| Диск: обсяг і тип (SSD/HDD)      |                |
| Форм-фактор: десктоп чи ноутбук  |                |
| Підключення: Ethernet чи Wi-Fi   |                |
| UPS / ДБЖ є?                     |                |
| Машина може бути ввімкнена 24/7? |                |

**Пороги, за якими план коригується:**

- **RAM < 16 GB** — прев'ю-середовища (Q12) доведеться обмежити одним і зупиняти агента
  на час прев'ю. Скажіть — перерахую.
- **Диск < 250 GB SSD** — кеші pnpm/uv, Playwright-браузери, docker-образи і прев'ю-стеки
  займуть більше, ніж лишиться. Мінімум робочий — 250 GB; комфортний — 500 GB.
- **HDD замість SSD** — CI-прогін розтягнеться в рази; сенс переносу з hosted-раннерів
  частково зникає.
- **Wi-Fi замість Ethernet** — працюватиме, але додає клас нічних збоїв, які ви
  діагностуватимете зранку. Дротове підключення бажане.

---

## §2. Track A — Ubuntu Server 24.04 LTS

> **Чому Ubuntu, а не Debian 12** (як пропонувалось у липневому аналізі): паритет із вашим
> dev-середовищем (WSL Ubuntu-24.04) — ті самі імена пакетів, ті самі версії toolchain,
> менше розбіжностей «у мене працює». LTS-підтримка до квітня 2029.

### A.1. Носій

Завантажте **Ubuntu Server 24.04.x LTS** (не Desktop) з ubuntu.com. Запишіть на флешку:
Rufus (Windows) або `dd` (Linux). Перевірте SHA256 з сайту перед записом.

### A.2. BIOS/UEFI — три налаштування, які роблять машину автономною

Заходите у BIOS (Del/F2 при старті) і знаходите за змістом (назви різняться):

1. **Restore on AC Power Loss → Power On.** Без цього після відключення світла машина
   лишиться вимкненою, і ви дізнаєтесь про це, коли зранку не прийде дайджест.
   Це найважливіший пункт усього треку.
2. **Wake on LAN → Enabled** (опційно, але корисно: дозволяє підняти машину з локальної
   мережі, якщо вона все ж вимкнеться).
3. **Secure Boot** — лишайте як є. Вимикати треба лише якщо драйвери мережевої карти
   відмовляться вантажитись; тоді повернетесь сюди.

### A.3. Встановлення

- Тип: **Ubuntu Server (minimized)** — без GUI.
- Ім'я хоста: `a8`
- Користувач: `yurii` (це буде адмін-акаунт).
- **Install OpenSSH server: так.** Імпорт ключа з GitHub — зручно (`Import SSH identity →
from GitHub → stjurik`), але перевірте потім, що це саме ваш актуальний ключ.
- Розмітка: **вся дискова ємність, LVM**. Окремі розділи під `/var` не робіть — docker
  з'їдає непередбачувано, і жорстка межа зашкодить більше, ніж допоможе.
- Snap-пакети на етапі встановлення: **жодного** (docker ставимо з офіційного репозиторію,
  snap-версія має відомі проблеми з правами й монтуванням).

### A.4. Перший вхід і оновлення

```bash
ssh yurii@<ip-a8>
sudo apt update && sudo apt full-upgrade -y
sudo reboot
```

### A.5. Заборонити сон і реакцію на кришку

Критично для машини, яка має працювати вночі без вас.

```bash
# Заборонити всі види сну
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

# ЯКЩО A8 — ноутбук: закрита кришка не має нічого вимикати
sudo tee -a /etc/systemd/logind.conf >/dev/null <<'EOF'
HandleLidSwitch=ignore
HandleLidSwitchDocked=ignore
HandleLidSwitchExternalPower=ignore
EOF
sudo systemctl restart systemd-logind
```

### A.6. Стабільна адреса

Найпростіше і найнадійніше — **DHCP-резервація на роутері** за MAC-адресою A8
(`ip -br link` покаже MAC). Статичну адресу в netplan прописувати не треба: одна помилка
в конфізі — і машина недоступна, а монітор до неї ви вже відключили.

### ✅ Checkpoint A

```bash
# A1: версія і мінімальність
lsb_release -ds                      # Очікувано: Ubuntu 24.04.x LTS
systemctl get-default                # Очікувано: multi-user.target

# A2: сон замасковано
systemctl status sleep.target | head -3   # Очікувано: Loaded: masked

# A3: SSH працює по ключу, пароль не потрібен
# (з робочої машини, НЕ з A8)
ssh -o BatchMode=yes yurii@<ip-a8> 'echo OK'   # Очікувано: OK

# A4: адреса не змінюється після ребуту
sudo reboot   # і через хвилину — той самий ssh на ту саму адресу
```

---

## §3. Track B — база і безпека

### B.1. Три користувачі з різними правами

Розділення не косметичне: `agent` не має sudo саме тому, що всередині контейнера
працюватиме зі знятими підтвердженнями (Q10).

```bash
# CI-раннер: без sudo, у групі docker
sudo adduser --disabled-password --gecos '' runner
sudo usermod -aG docker runner        # група з'явиться після Track C — повторіть тоді

# Агенти: без sudo, у групі docker
sudo adduser --disabled-password --gecos '' agent
sudo usermod -aG docker agent

# Перевірка: жоден з них не в sudo
groups runner agent
```

⚠ Членство в групі `docker` фактично дорівнює root на хості. Це усвідомлений компроміс:
альтернатива (rootless docker) додає клас проблем із мережею й монтуванням, який ви
діагностуватимете тижнями. Компенсація — жодних prod-креденшалів на машині (§7).

### B.2. SSH — тільки ключі

```bash
sudo tee /etc/ssh/sshd_config.d/99-hardening.conf >/dev/null <<'EOF'
PasswordAuthentication no
PermitRootLogin no
KbdInteractiveAuthentication no
EOF
sudo systemctl restart ssh
```

⚠ **Не закривайте поточну SSH-сесію**, поки не перевірите вхід у новому вікні.

### B.3. UFW — нічого вхідного з інтернету

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
# SSH — лише з локальної мережі (підставте свою підмережу з `ip -br a`)
sudo ufw allow from 192.168.0.0/16 to any port 22 proto tcp
sudo ufw enable
sudo ufw status verbose
```

Runner, `cloudflared` і агенти працюють **лише вихідними** з'єднаннями — прокидати порти
на роутері не треба. Якщо колись з'явиться спокуса «просто відкрити 80/443 на A8» —
це і буде момент, коли домашня машина стане мішенню.

### B.4. Автоматичні security-оновлення

```bash
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure --priority=low unattended-upgrades   # відповісти Yes
```

### B.5. Swap

Той самий аргумент, що й на MS21 (ADR-011): CadQuery/OpenCascade під час експорту
тримають 800–1200 MB, і піки збігаються з CI-прогоном.

```bash
sudo fallocate -l 8G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
sudo sysctl -w vm.swappiness=10
echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swap.conf
```

### B.6. Час і локаль

```bash
sudo timedatectl set-timezone Europe/Kyiv
timedatectl                      # Очікувано: Time zone: Europe/Kyiv, NTP synchronized: yes
```

### ✅ Checkpoint B

```bash
# B1: пароль не приймається
ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no yurii@<ip-a8>
# Очікувано: Permission denied (publickey)

# B2: ззовні LAN нічого не відкрито
sudo ufw status | grep -c ALLOW      # Очікувано: 1 (лише SSH з LAN)

# B3: swap живий
free -h | grep Swap                  # Очікувано: 8.0Gi

# B4: агент і раннер без sudo
sudo -u agent sudo -n true 2>&1      # Очікувано: помилка "a password is required" / not in sudoers
```

---

## §4. Track C — Docker і toolchain

### C.1. Docker CE з офіційного репозиторію

```bash
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# тепер група docker існує — повторіть додавання з B.1
sudo usermod -aG docker runner agent
```

### C.2. Ліміт логів Docker (інакше диск з'їдять контейнери прев'ю)

```bash
sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF
sudo systemctl restart docker
```

### C.3. Node 22 і менеджери пакетів

> `actions/setup-node` завантажує Node сам, тож системний Node потрібен не раннеру, а
> агентам і ручним перевіркам. Ставимо 22 LTS — це та сама версія, на яку в черзі T1
> стоїть міграція `NODE_VERSION` (зараз у `ci.yml` і `discord-snapshot.yml` — 20.11.0,
> Node 20 досяг EOL 30.04.2026).

```bash
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs git build-essential
sudo corepack enable && sudo corepack prepare pnpm@latest --activate

# uv для Python-воркера
curl -LsSf https://astral.sh/uv/install.sh | sudo -u agent sh
```

### C.4. Системні залежності Playwright

Ставляться один раз, root'ом; самі браузери потім качає кожен користувач у свій кеш.

```bash
sudo npx --yes playwright install-deps
sudo -u runner npx --yes playwright install chromium firefox webkit
sudo -u agent  npx --yes playwright install chromium
```

### ✅ Checkpoint C

```bash
node -v && pnpm -v && git --version     # Очікувано: v22.x, 9.x/10.x, 2.4x
sudo -u agent docker run --rm hello-world | grep -c "Hello from Docker"   # Очікувано: 1
df -h / | tail -1                       # Вільного має лишатись ≥ 150 GB
```

---

## §5. Track D — облікові записи, токени, перемикання

> Усе в цьому треку робиться в браузері або вимагає інтерактивного логіна. Порядок
> обов'язковий.

### D.0. Перевірити deploy key ДО перемикання visibility

Липневий аналіз вважав це блокером. Перевірка по коду показала інше: `repo_url` в
`infra/ansible/group_vars/all.yml` — SSH (`git@github.com:…`), а `docs/08` §1.5 фіксує
створений read-only deploy key. Deploy keys працюють на private репо однаково.
Але перевірити треба фактично, а не за документом:

```bash
ssh root@<mirohost_ip> 'sudo -u deploy ssh -o StrictHostKeyChecking=accept-new -T git@github.com'
# Очікувано: Hi stjurik/flatcraft! You've successfully authenticated...
```

Образи тягнуться автентифіковано (роль `docker` робить `docker login ghcr.io` під
`vault_ghcr_token` для root і для `deploy`) — private-пакети зламати pull не можуть.

⚠ Якщо перевірка не пройшла — **стоп**, не перемикайте visibility. Спочатку відновіть
ключ за `docs/08` §1.5.

### D.1. Перемикання репозиторію в private

GitHub → repo → Settings → General → Danger Zone → Change visibility → Private.

Одразу після цього:

- перевірте, що `deploy-staging.yml` проходить (workflow_dispatch);
- пам'ятайте: MIT-права на вже роздані знімки безвідкличні, наявні форки лишаються
  видимими. Приватність захищає майбутнє, не минуле.

Правки сайту/доків (trust-row, /about, README, CLAUDE.md §2.6, R-07) робить master-run —
руками нічого не переписуйте.

### D.2. Реєстрація self-hosted runner

GitHub → repo → Settings → Actions → Runners → **New self-hosted runner** → Linux x64.
Скопіюйте команди зі сторінки (**токен живе ~1 годину**) і виконайте від `runner`:

```bash
sudo -iu runner
mkdir actions-runner && cd actions-runner
# curl -o actions-runner-linux-x64-<версія>.tar.gz -L <url зі сторінки>
# tar xzf ./actions-runner-linux-x64-<версія>.tar.gz
./config.sh --url https://github.com/stjurik/flatcraft --token <TOKEN> \
            --name a8 --labels self-hosted,linux,x64,a8 --work _work
exit

# systemd-сервіс (від адміна)
cd /home/runner/actions-runner
sudo ./svc.sh install runner
sudo ./svc.sh start
sudo ./svc.sh status        # Очікувано: active (running)
```

⚠ Які job переїжджають на A8 — вирішує master-run окремим PR (Q2: лише важкі).
`deploy-staging.yml` і `release.yml` **лишаються на GitHub-hosted** — інакше на A8
опиняться vault-пароль, SSH-ключ до Mirohost і GHCR-токен на запис, а це ламає
інваріант §7.

### D.3. `claude setup-token`

Інтерактивний логін. Виконується від `agent`:

```bash
sudo -iu agent
claude setup-token          # відкриє URL — авторизуєте у браузері на іншій машині
```

Токен зберігається локально для агентів. **Окремо** покладіть його в GitHub Secret
`CLAUDE_CODE_OAUTH_TOKEN`, якщо лишаєте `ai-fix.yml` як запасний шлях:

```bash
gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo stjurik/flatcraft
```

⚠ Це те саме значення, недійсність якого коштувала п'яти падінь тріажу
(`401 Invalid bearer token`). Токен протухає — «перелогінити claude на A8» стає
пунктом обслуговування, і демон має вміти відрізняти 401 від вичерпаної квоти
(це вже в ADR-039).

### D.4. `agy` / Gemini на headless-машині

**Спочатку — одна команда.** Вона перевіряє весь ланцюг, потрібний оркестратору
(тека довірена → `agy` стартує → `read_file` → `write_file` → повернув саме те, що
просили → нічого стороннього не зачепив), і друкує однозначний вердикт:

```bash
cd ~/hart && tools/scripts/check-agy-headless.sh
```

| exit | Вердикт                                                  | Що робити                                                 |
| ---- | -------------------------------------------------------- | --------------------------------------------------------- |
| 0    | ✅ ланцюг працює — Gemini-пул на цій машині можливий     | нічого, D.4 закритий                                      |
| 1    | ❌ інструменти заблоковані allow-list'ом (**не** логін!) | `permissions.allow` у `settings.json`, не перелогін       |
| 2    | ⚠️ потрібен браузер                                      | варіанти 2-3 нижче                                        |
| 3    | ❌ креденшали недійсні                                   | перелогін `agy`                                           |
| 4    | ❌ таймаут                                               | `--timeout`, тоді розбір лога                             |
| 5    | ❌ відповів, але завдання не виконав                     | дефект промпту або моделі, не доступу                     |
| 6    | ⚠️ писав поза `docs/promts/inputs/**`                    | інцидент Master Run 8 — звірити й відкотити               |
| 7    | **знято 2026-09-15** — більше не повертається            | було: «тека поза `trustedWorkspaces`»; чому знято — нижче |

Гілки 1 і 2 плутають найлегше: заблокований інструмент валить `agy` **тихо**, і це
виглядає як проблема логіна. Саме тому їх розділяє окрема сигнатура в лозі
(`soft-denying`), а не око людини.

**Результат на T470 (WSL, `~/hart`), 2026-09-13: exit 0 — ✅ PASS.** Дослівно:
`read_file + write_file працюють, nonce повернувся дослівно`, `scope: OK`. Тобто
headless-виклик `agy` (`-p`, без bash-інструментів, передача контексту файлом) —
працездатний механізм, а не гіпотеза.

**Чого цей PASS НЕ доводить:** креденшали на T470 отримані через браузер. Тому на A8
відкритим лишається саме **логін**, а не механіка виклику. Прогоніть ту саму команду
на A8 — вона дасть відповідь одним запуском:

1. **exit 0** — креденшали приймаються, D.4 закритий, Gemini-пул є.
2. **exit 2 або 3** — скопіюйте `~/.gemini/` з T470 (разом із
   `antigravity-cli/settings.json`) і повторіть команду.
3. **Знову exit 2 або 3** — API-ключ з aistudio.google.com у змінну оточення
   користувача `agent`, і повторіть команду.

Що спрацювало — впишіть сюди: від цього залежить, чи зможе демон використовувати
Gemini-пул як резерв при вичерпаній Claude-квоті (ADR-039 §5).

> ⚠️ **`trustedWorkspaces` і worktree — ВІДКРИТА суперечність, два виміри не
> зводяться.** Не шукайте тут «правду»: нижче обидві точки, і наступний, хто
> побачить браузерний OAuth з worktree, має знайти обидві, а не одну.
>
> Контекст: `autorun.sh` створює worktree у `$HOME/hart-wt/<...>`
> (`WT_ROOT`), а ADR-039 §2 будує ізоляцію саме на «власному worktree на
> задачу»; §5 — на Gemini як другому квотному пулі. Якщо список гейтить доступ,
> ці дві вимоги конфліктують; якщо ні — конфлікту немає.
>
> **Вимір 1 — 2026-09-14** (Стадія 0). Довіра НЕ успадковується від батька:
>
> | `trustedWorkspaces`    | cwd                    | Результат        |
> | ---------------------- | ---------------------- | ---------------- |
> | `~/hart-wt`            | `~/hart-wt/a8-stage-0` | браузерний OAuth |
> | `~/hart`               | `~/hart`               | exit 0 PASS      |
> | `~/hart-wt/a8-stage-0` | `~/hart-wt/a8-stage-0` | exit 0 PASS      |
>
> **Вимір 2 — 2026-09-15** (4 виклики, дослівний вивід у PR #109). Список не
> гейтить режим `-p` **узагалі** — ні виклик моделі, ні інструменти:
>
> | `trustedWorkspaces`                     | cwd                                  | Результат                                                       |
> | --------------------------------------- | ------------------------------------ | --------------------------------------------------------------- |
> | `~/hart-wt` (лише батько)               | `~/hart-wt/a8-stage-0`               | exit 0, `TRUST-PROBE-OK`                                        |
> | `~/hart-wt` (лише батько)               | `~/hart-wt/architectural-dead-end` ¹ | exit 0, `CLEAN-PROBE-OK`                                        |
> | `~/lun_monitor` (ні теки, ні батька)    | `~/hart-wt/architectural-dead-end`   | exit 0, `UNTRUSTED-PROBE`                                       |
> | `~/lun_monitor` (те саме) + інструменти | те саме                              | `read_file`+`write_file` OK, nonce дослівно, `soft-denying` — 0 |
>
> ¹ тека, якої у списку не було **ніколи** — контроль на кешування довіри.
>
> **Що з цього встановлено твердо, а що ні.**
> Твердо: вердикт **7** у PR #108 давав НАШ власний гейт у
> `check-agy-headless.sh` (звірка точного збігу ДО виклику `agy`), а не `agy`.
> Тому гейт знято 2026-09-15 — скрипт, який відмовляється міряти, не може
> нічого довести, і блокування було хибним за будь-якої гіпотези: точний збіг
> відхиляв і підтеки справді довірених коренів.
> НЕ встановлено: причина браузерного OAuth у вимірі 1. Другий вимір її не
> об'єднує і не скасовує.
>
> **Що з цього зроблено.** `tools/scripts/trust-worktree.sh`
> (`check`/`add`/`remove`, ідемпотентний, реєструє корінь git навіть коли
> передали підтеку) + виклик `add` в `autorun.sh` одразу після `worktree add` —
> **страховка, не передумова**: нічого не блокує, `exit 2` (немає `settings.json`)
> прогін не валить. Якщо довіра колись таки має значення, це знімає найдорожчий
> симптом — недовірена тека просить браузерний OAuth і виглядає як
> протермінований логін.

Заразом врахуйте, що `write_file(*)` у `~/.gemini/antigravity-cli/settings.json`
ширший за задум — звуження до `docs/promts/inputs/` є в черзі «Відкладено до A8».
До того часу межу тримає `tools/scripts/check-agy-scope.sh` (порівняння `git status`
до/після виклику).

### D.5. Cloudflare Tunnel (для прев'ю-середовищ, Q12)

Cloudflare dashboard → Zero Trust → Networks → Tunnels → Create a tunnel →
Cloudflared → назва `a8-preview` → скопіюйте команду встановлення з токеном:

```bash
sudo cloudflared service install <TOKEN>
sudo systemctl status cloudflared    # Очікувано: active (running)
```

DNS-запис (наприклад `*.dev.hart.crimea.ua` → tunnel) і маршрути на конкретні порти
налаштує master-run. Портів на роутері не відкриваємо — тунель робить вихідне з'єднання.

### D.6. Discord — чотири канали і бот

Канали заводяться **не руками**, а через ваш IaC (`infra/discord/`, ADR-023) — master-run
додасть їх у конфіг, ви застосуєте `pnpm discord:apply` (manual-only команда, CLAUDE.md §6):

- `#питання-блокуючі` — клас A, без дефолту;
- `#питання-дефолт` — клас B, таймер 6–12 год (Q7);
- `#на-перевірку` — draft PR + посилання на прев'ю + «Як перевірити очима»;
- `#інциденти` — 401, квота, машина впала, диск.

Руками від вас потрібен лише **токен бота** з правом читати реакції (Discord Developer
Portal → ваш застосунок → Bot → Reset Token) — покладете у vault.

### ✅ Checkpoint D

```bash
# D1: репо private
gh repo view stjurik/flatcraft --json visibility      # Очікувано: {"visibility":"PRIVATE"}

# D2: runner видно у GitHub
gh api repos/stjurik/flatcraft/actions/runners --jq '.runners[].name,.runners[].status'
# Очікувано: a8, online

# D3: деплой не зламався
gh workflow run deploy-staging.yml && sleep 60 && gh run list --workflow=deploy-staging.yml --limit 1
# Очікувано: completed / success

# D5: тунель живий
systemctl is-active cloudflared                       # Очікувано: active
```

---

## §6. Що ви НЕ ставите руками

Нижче — робота master-run'а за промтом `docs/promts/master-a8-transition.md`. Якщо
почнете робити це руками, ви створите конфігурацію, якої немає в git, і повторите
клас помилки «артефакт існує лише на диску» (правило недільного `git status`).

- Ansible-роль `infra/ansible/roles/a8/` — усе з Track B–C як код, щоб машину можна було
  перевстановити за годину.
- Контейнер агента: образ із Claude Code + `agy`, монтування worktree, allowlist мережі,
  `--dangerously-skip-permissions` **всередині** контейнера (Q10).
- Демон-оркестратор: systemd-юніт, черга задач на диску, класифікатор виходу
  (квота / 401 / реальний збій), денний ліміт і kill switch (Q9), журнал прогонів.
- Прев'ю-середовища на гілку: `docker compose` per-branch + маршрут у тунелі (Q12).
- Auto-merge оборотного класу + auto-revert по smoke-тесту (Q11) і ADR-040 з тригером
  скасування на launch.
- Правки workflows: `runs-on: self-hosted` для важких job, `NODE_VERSION` 20 → 22.
- Портативні deny-правила в `.claude/settings.json` (у git!), включно з відсутнім нині
  `Edit(infra/**)` і виправленим глобом `packages/db/src/migrations/**`; приведення
  `docs/16` §1 у відповідність до реальності.
- Бекап-роль: щоденний `git clone --mirror` + копія pg_dump з R2 (компенсація R-07 після
  закриття коду) і healthcheck-cron A8 → `#інциденти`.

---

## §7. Інваріанти, які цей етап не має зламати

1. **На A8 немає prod-креденшалів.** Ні пароля Ansible-vault, ні SSH-ключа до Mirohost,
   ні GHCR-токена на запис. Тому `deploy-staging.yml` і `release.yml` лишаються на
   GitHub-hosted раннерах. Агент не деплоїть — деплоїть CI після merge.
2. **Жодного вхідного порту з інтернету на A8.** Runner, `cloudflared`, агенти — лише
   вихідні з'єднання.
3. **Незворотне лишається за yurii завжди:** міграції БД, `infra/`, bend-матриця і все,
   що торкається `docs/07`, перехід у prod. Auto-merge (Q11) поширюється **тільки** на
   оборотний клас і тільки поки сайт у тестовому режимі.
4. **Deny-правила портативні.** Правило, якого немає в git, не захищає CI, інший клон і
   headless-прогін на A8.
5. **Kill switch і денний ліміт існують до першого автономного прогону**, а не після.

---

## §8. Чеклист для issue #78

Скопіюйте у «Чергу yurii» — це ваші мануальні кроки, і за ADR-036 §4 вони мають жити там,
а не лише в цьому документі.

```markdown
## Додано 2026-08-07 (A8 preflight, docs/19)

- [ ] Крок 0 — інвентаризація A8, заповнити таблицю §1 (CPU/RAM/диск/мережа/UPS)
- [ ] Track A — Ubuntu Server 24.04 LTS, BIOS «Restore on AC Power Loss → Power On»,
      сон замасковано, DHCP-резервація. Checkpoint A зелений
- [ ] Track B — користувачі runner/agent без sudo, SSH key-only, UFW deny incoming,
      unattended-upgrades, swap 8 GB. Checkpoint B зелений
- [ ] Track C — Docker CE, Node 22, pnpm, uv, Playwright deps. Checkpoint C зелений
- [ ] D.0 — перевірити deploy key з Mirohost-сервера (БЛОКУЄ D.1)
- [ ] D.1 — перемкнути репо в private
- [ ] D.2 — зареєструвати runner `a8` (ТІЛЬКИ після D.1)
- [ ] D.3 — `claude setup-token` на A8 + оновити GitHub Secret
- [ ] D.4 — на A8 виконати `cd ~/hart && tools/scripts/check-agy-headless.sh`; exit 0 =
      готово, exit 2/3 → варіанти 2-3 §D.4. Механіка headless-виклику вже перевірена
      на T470 (✅ PASS, 2026-09-13) — на A8 відкритий лише логін
- [ ] D.5 — Cloudflare Tunnel `a8-preview`
- [ ] D.6 — токен Discord-бота у vault
- [ ] Запустити master-run `docs/promts/master-a8-transition.md` (§6)
```

---

_Створено 2026-08-07. Джерело рішень — Опитування Q1–Q13 (§0.2). Оформлення рішень в
ADR-038/039/040 — за master-run'ом, не цим документом._
