# 09. Staging Preflight Checklist

> **Кому це:** yurii перед першим `ansible-playbook`.
>
> **Що це:** усе, що треба зробити **руками** у браузері/CLI — замовити сервер, налаштувати Cloudflare, R2, згенерувати секрети. Після завершення цього файлу — інфра готова до §1 з `docs/08_DEPLOYMENT.md` (Ansible run).
>
> **Час:** **3-7 днів реального календарного часу**, з них активного — ~3-4 години. Limiting factor — пропагація NS у Cloudflare (1-24h) + час між замовленням Mirohost і email'ом "сервер готовий" (зазвичай 1-2 год, рідко до доби).
>
> **Як читати:** документ розбито на **7 треків (A-G)**. Деякі можна робити паралельно (позначено). Усередині треку кроки **строго послідовні**. У кінці кожного треку — **Checkpoint** з кількома `✓` для перевірки, що всі підпункти зайшли. Не йди далі без зеленого checkpoint'у.
>
> **Якщо щось пішло не так** — у кінці є секція **§Х. Troubleshooting**.

---

## Огляд: що буде на виході

Після проходження цього файлу у тебе буде:

- ☁ Mirohost MS21 сервер, доступний по SSH як `root`
- 🌐 Домен `hart.crimea.ua`, перемкнений на Cloudflare (NS propagated)
- 📦 Два R2 bucket'и (`flatcraft-artifacts`, `flatcraft-backups`) з lifecycle rules
- 🔑 R2 API token (Object R+W на ці 2 bucket'и)
- 🛡 CF Origin Certificate (15 років, RSA-2048 або ECC-P256, wildcard)
- 🛡 WAF Country Block для RU/BY
- 📡 DNS records `staging.hart.crimea.ua` + `api-staging.hart.crimea.ua` (proxied)
- 🔐 SSL/TLS Mode = Full (strict), Always HTTPS = On
- 🎲 15 згенерованих secrets у password manager (паролі + age keypair)
- 🐙 GitHub PAT з `read:packages` scope

Після цього → `docs/08_DEPLOYMENT.md §1` запустить Ansible і за 15хв розгорне стек.

---

## Графік паралельних треків

```
Track A (CF account + domain) ──→ wait NS 1-24h ─┐
Track B (Mirohost server)      ────────────────┐ │
Track C (generate secrets)     ─ any time     │ │
                                              │ │
        ┌─────────── Checkpoint A+B+C ────────┘ ┘
        ↓
Track D (CF infra: R2 + Cert + WAF + SSL)
        ↓
Track E (DNS records — потребує IP з B)
        ↓
Track F (GitHub PAT)
        ↓
Track G (Password manager final inventory)
        ↓
Готово → §1 з 08_DEPLOYMENT.md
```

**Найшвидший шлях:** запусти A, B, C паралельно у трьох вкладках браузера. Потім чекай NS пропагації, далі D-E-F-G послідовно.

---

# Track A — Cloudflare акаунт + домен

**Тривалість:** активного часу ~10 хв + 1-24h очікування NS-пропагації.
**Передумова:** доступ до DNS-панелі реєстратора, що тримає `hart.crimea.ua`.

## A.1. Реєстрація на Cloudflare

1. Відкрий https://dash.cloudflare.com у браузері.
2. Натисни **Sign Up**. Введи email + сильний пароль (збережи у password manager окремим записом `cloudflare.account.password`).
3. Підтвердь email (Cloudflare надішле verification link).
4. На наступному екрані — пропусти "Add your first website" поки що.

## A.2. Увімкни 2FA на CF акаунт (КРИТИЧНО)

1. Top-right avatar → **My Profile** → **Authentication**.
2. **Two-Factor Authentication** → Enable.
3. Скануй QR через Aegis/Authy/Bitwarden TOTP.
4. **Збережи backup codes** у password manager → `cloudflare.account.backup-codes`.

Чому критично: CF тримає Origin Cert private key (видається один раз), DNS, R2 keys. Без 2FA — компрометація email = повний контроль над інфрою.

## A.3. Додати домен `hart.crimea.ua`

1. На головній dashboard натисни **Add a site** (або **Add a domain**).
2. Введи `hart.crimea.ua` (без `www`).
3. Обери план **Free** ($0).
4. CF скане існуючі DNS-записи (можеш пропустити імпорт, ми все одно потім вручну налаштуємо).
5. На екрані "Change your nameservers" CF покаже два nameserver'и, виглядає типу:
   ```
   nina.ns.cloudflare.com
   mateo.ns.cloudflare.com
   ```
   (Імена унікальні для кожного акаунту.)
6. **Скопіюй обидва nameserver'и у текстовий файл** — наступний крок.

## A.4. Змінити NS у реєстратора crimea.ua

1. Зайди у панель реєстратора (зазвичай через сайт `imena.ua`, `ukraine.com.ua` чи інший — залежно від того, де реєстрували).
2. Знайди domain `hart.crimea.ua` → **DNS-сервери / Nameservers / NS**.
3. Видали ВСІ існуючі NS-записи.
4. Додай два CF NS з кроку A.3.5.
5. Збережи.

⚠ **Не паралель з іншими DNS-провайдерами.** Тільки CF NS.

## A.5. Очікування пропагації

Це момент, коли можна запустити Track B + C у паралельних вкладках.

- Зазвичай 1-2 години (нові NS бачить уся країна).
- У найгіршому випадку до 24 год (старі DNS resolver'и кешують довго).

**Перевіряй періодично (раз на 30 хв):**

```bash
dig +short NS hart.crimea.ua
```

Поки бачиш старих NS реєстратора — чекай. Як побачив `*.ns.cloudflare.com` (обидва ваші імена) — пропагація завершена.

## ✅ Checkpoint A — CF account + domain

Усі три мають бути `OK`:

```bash
# A1: NS resolves до CF
dig +short NS hart.crimea.ua | sort
# Очікувано: дві стрічки з ".ns.cloudflare.com." (через крапку наприкінці), і саме ті, які CF показав у A.3.5

# A2: CF dashboard визнав домен Active
# → У браузері: dash.cloudflare.com → твій домен в списку → статус ≠ "Pending Nameserver Update"
# → Має бути "Active" (зелений значок)

# A3: 2FA на акаунті
# → My Profile → Authentication → "Two-Factor Authentication" enabled, backup codes збережено
```

Якщо A1 показує старі NS після 24 год — див. **Troubleshooting §X.1**.

---

# Track B — Mirohost MS21 сервер

**Тривалість:** замовлення ~15 хв + 1-2 год очікування email'у з IP.
**Можна паралельно з Track A.** Залежність — лише на власний публічний SSH-ключ (потрібен ДО замовлення).

## B.1. Підготувати SSH-ключ

Якщо у тебе вже є `~/.ssh/id_ed25519.pub` — пропусти. Якщо нема:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N '' -C "yurii@flatcraft-staging"
cat ~/.ssh/id_ed25519.pub
# Скопіюй вивід — він піде у Mirohost order і пізніше в Ansible vars.
```

⚠ **Це твій робочий ключ для ssh-доступу.** НЕ той, що для GitHub deploy (той окремий, генеруватимемо на сервері).

## B.2. Замовлення MS21

1. Відкрий https://mirohost.net/cloud
2. Зайди в акаунт (зареєструйся, якщо нема). 2FA вмикати — рекомендую, але не критично (Mirohost не зберігає secret material'у крім root паролю, який ми все одно прибираємо).
3. Обери тариф **MS21** (2 vCPU / 4 GB / 40 GB).
   - Якщо не знайдеш точно цей — шукай 2x4x40 SSD KVM (можуть перейменувати).
4. На сторінці замовлення:
   - **ОС:** Debian 12 (Bookworm) 64-bit. **НЕ Ubuntu** (наш Ansible тестований на Debian).
   - **ДЦ / Region:** Київ (`EU-IEV-1` або `Kyiv`).
   - **SSH key:** встав публічний ключ з B.1 (поле "Add SSH key" або подібне).
   - **Pre-installed software:** жодного.
   - **Backup:** опціонально (внутрішній Mirohost backup — не наш, ми робимо свій у R2; вимикай для економії, якщо є опція).
5. Оплати (Mirohost MS21 ~700-800 грн/міс).

## B.3. Очікування email "Сервер готовий"

Зазвичай 5-30 хв, рідко до доби. У листі буде:

- IPv4 адреса (запиши!)
- root пароль (НЕ використовуй — у нас key-based auth)
- panel URL

## B.4. Перший SSH тест

Як прийде email з IP:

```bash
# Тест без strict host check (перший раз):
ssh -o StrictHostKeyChecking=accept-new root@<server_ip> 'echo "hello from $(hostname)"; uname -a; cat /etc/debian_version; free -h | head -2; df -h / | tail -1; nproc'
```

Очікуваний вивід (приблизно):

```
hello from cloud-12345
Linux cloud-12345 6.1.0-x-amd64 ... GNU/Linux
12.x
               total        used        free
Mem:           3.8Gi       100Mi       3.6Gi
/dev/vda1       40G   2.5G   36G   7% /
2
```

⚠ Якщо `Permission denied (publickey)` — Mirohost не зчитав твій SSH ключ при замовленні. Зайди в Mirohost панель → server → "SSH keys" → додай вручну. Або відкрий тикет.

## ✅ Checkpoint B — Server alive

```bash
# B1: SSH працює і ключ прийнято
ssh root@<server_ip> 'true' && echo "✓ SSH OK"
# Очікувано: "✓ SSH OK"

# B2: Сервер відповідає тим, що замовляли
ssh root@<server_ip> 'uname -m; cat /etc/debian_version; nproc; free -h | awk "/Mem:/ {print \$2}"; df -h / | awk "NR==2 {print \$2}"'
# Очікувано:
#   x86_64
#   12.x
#   2
#   3.8Gi   (приблизно — RAM показано після allocation overhead)
#   40G

# B3: IP записано
echo "Server IP: <IP>"   # збережи у password manager → flatcraft-staging.host
```

Запиши IP як запис `flatcraft-staging.host` у password manager.

---

# Track C — Згенерувати secrets локально

**Тривалість:** ~10 хв.
**Можна паралельно з A і B.**

## C.1. Встановити інструменти (один раз)

```bash
# Ubuntu/Debian/WSL:
sudo apt update
sudo apt install -y age openssl

# macOS:
brew install age openssl

# Verify:
age --version    # 1.x
openssl version  # OpenSSL 3.x
```

## C.2. Згенерувати 4 password-style secrets

```bash
echo "Postgres password:"
openssl rand -hex 32
# → password manager: flatcraft-staging.postgres-password

echo ""
echo "AUTH_SECRET (для Auth.js JWT signing):"
openssl rand -hex 32
# → flatcraft-staging.auth-secret

echo ""
echo "Admin seed password (Phase 3, seed admin user):"
openssl rand -hex 16
# → flatcraft-staging.admin-password

echo ""
echo "Ansible vault password (encrypt'итиме group_vars/all.vault.yml):"
openssl rand -hex 32
# → flatcraft-staging.vault-password
```

Скопіюй кожне у password manager **відразу**. `openssl rand` не зберігає вивід ніде — як закриєш термінал, він пропав.

## C.3. Згенерувати age keypair (для шифрування бекапів)

```bash
age-keygen -o /tmp/flatcraft-age.key
cat /tmp/flatcraft-age.key
```

Виведе щось типу:

```
# created: 2026-05-22T14:30:00+03:00
# public key: age1abc123def...xyz
AGE-SECRET-KEY-1ABCDEF...XYZ
```

Потрібно зберегти **обидва ключі**:

1. **Публічний** (`age1...` з рядка `# public key:`) → password manager: `flatcraft-staging.age-public-key`
2. **Приватний** (повний рядок `AGE-SECRET-KEY-...`) → password manager: `flatcraft-staging.age-private-key`

Також збережи **весь файл цілком** як attachment до запису `flatcraft-staging.age-private-key` (на випадок recovery з командного рядка зручніше мати файл).

**Видали з диска одразу:**

```bash
shred -u /tmp/flatcraft-age.key
# (або на macOS: rm -P /tmp/flatcraft-age.key)
```

⚠ **Якщо втратиш приватний age-key — втрачені ВСІ бекапи.** Це fail-fail. Зберігай в 2+ місцях: 1Password/Bitwarden + щось офлайн (USB-ключ у сейфі, наприклад).

⚠ **НЕ кладіть приватний ключ у Ansible vault.** Якщо vault скомпрометовано — компроментується ВСЕ. age private key — окремо. Vault бере лише публічний (`vault_age_public_key`).

## ✅ Checkpoint C — Secrets в pass manager

Перевір у password manager — мають бути ці 6 записів:

```
☐ flatcraft-staging.postgres-password    (64 hex chars)
☐ flatcraft-staging.auth-secret          (64 hex chars)
☐ flatcraft-staging.admin-password       (32 hex chars)
☐ flatcraft-staging.vault-password       (64 hex chars)
☐ flatcraft-staging.age-public-key       ("age1..." ~62 chars)
☐ flatcraft-staging.age-private-key      ("AGE-SECRET-KEY-1..." ~75 chars + повний файл як attachment)
```

Sanity-check, що нічого не лишилось у `/tmp`:

```bash
ls /tmp/*age* /tmp/*flatcraft* 2>&1
# Очікувано: "No such file or directory"
```

---

# 🔄 Pre-Track-D Gate: чекаємо Checkpoint A

Перш ніж переходити у D — переконайся, що **Checkpoint A зелений**:

```bash
dig +short NS hart.crimea.ua | head -1
# Має бути *.ns.cloudflare.com — НЕ старі NS реєстратора.
```

Якщо ще не пропагувалось — чекай. Без цього кроки D не пройдуть.

---

# Track D — Cloudflare infrastructure

**Тривалість:** ~30 хв активного клікання.
**Передумова:** Checkpoint A зелений (CF володіє доменом).

Track D має 5 підтреків: D1 R2 buckets, D2 R2 token, D3 Origin Cert, D4 WAF, D5 SSL/TLS.

## D.1. R2 buckets `flatcraft-artifacts` + `flatcraft-backups`

### D.1.1. Активувати R2 (один раз на акаунт)

1. CF dashboard → **R2** у sidebar (значок couldy storage).
2. Перший раз — кнопка **Purchase R2 Plan**. Так-так, "purchase" — насправді безкоштовно до 10 GB зберігання + 1 млн class A operations / міс. Введи billing info (картка обов'язкова для активації, навіть якщо не платитимеш).
3. Підтвердь "I agree to terms" → Subscribe.

### D.1.2. Створити перший bucket — `flatcraft-artifacts`

1. R2 → **Create Bucket**.
2. **Name:** `flatcraft-artifacts` (lowercase, тире — стандарт для S3 naming).
3. **Location:** Automatic (CF сам обирає; для нашої аудиторії EU доцільно — Frankfurt чи Amsterdam).
4. **Storage Class:** Standard.
5. Натисни Create.

### D.1.3. Додати lifecycle rule на `flatcraft-artifacts`

1. Зайди в bucket → **Settings** → **Object lifecycle rules** → **Add rule**.
2. **Rule name:** `expire-after-90d`
3. **Scope:** Apply to all objects (no prefix filter).
4. **Action:** **Delete objects**.
5. **Trigger:** "**X days after the object was last accessed**" → `90`.
6. Save.

### D.1.4. Створити другий bucket — `flatcraft-backups`

Повтори D.1.2 для `flatcraft-backups`.

### D.1.5. Lifecycle rule на `flatcraft-backups`

1. Bucket → Settings → Object lifecycle rules → Add rule.
2. **Rule name:** `expire-after-30d`
3. **Scope:** all objects.
4. **Action:** Delete objects.
5. **Trigger:** "**X days after upload**" → `30`. (Не "last accessed" — backup'и зазвичай не читають, тільки при recovery; нам треба фіксована політика 30д.)
6. Save.

## D.2. R2 API token (scoped до цих двох bucket'ів)

1. CF dashboard → R2 → **Manage R2 API Tokens** (зверху або в Account-меню).
2. **Create API Token**.
3. **Token name:** `flatcraft-staging-rw`
4. **Permissions:** **Object Read & Write** (НЕ admin).
5. **Specify buckets:** **Apply to specific buckets only** → встав ОБИДВА:
   - `flatcraft-artifacts`
   - `flatcraft-backups`
6. **TTL:** **Forever** (ротуємо вручну раз на рік).
7. **Client IP filter:** залиш порожнім (інакше CF GH Actions runner'и обламаються).
8. Натисни **Create API Token**.

CF покаже екран із **трьома** значеннями — **скопіюй усі три ОДРАЗУ** (вони більше не покажуться):

```
Token value                    (~40+ chars, AWS-style — це secret access key)
Access Key ID                  (~20 hex chars)
Secret Access Key              (~40+ chars — те саме що token value, або інше — обидва зберігай)
```

Також з URL у browser'і скопіюй **Account ID** (формат: `dash.cloudflare.com/<account_id>/r2`).

→ password manager:

- `flatcraft-staging.r2.access-key-id`
- `flatcraft-staging.r2.secret-access-key`
- `flatcraft-staging.r2.account-id`
- `flatcraft-staging.r2.endpoint` = `https://<account_id>.r2.cloudflarestorage.com`

## D.3. Cloudflare Origin Certificate

1. CF dashboard → твій домен `hart.crimea.ua` → **SSL/TLS** (sidebar) → **Origin Server**.
2. **Create Certificate**.
3. **Generate private key and CSR with Cloudflare:** залиш увімкненим (default; CF згенерує приватний ключ для тебе).
4. **Key type:** **ECC** (P-256) — сучасніший, менший cert. Якщо боїшся compatibility — обери **RSA 2048**.
5. **Hostnames:**
   ```
   hart.crimea.ua
   *.hart.crimea.ua
   ```
   (зірочка покриває `staging`, `api.staging`, майбутній `prod`, і всі ще-не-вигадані піддомени)
6. **Certificate Validity:** **15 years** (максимум).
7. Натисни **Create**.

CF покаже два text-area:

- **Origin Certificate** (починається `-----BEGIN CERTIFICATE-----`)
- **Private Key** (починається `-----BEGIN PRIVATE KEY-----`)

⚠ **Private Key показується ОДИН РАЗ.** Закриєш вкладку — все, генеруй заново. Скопіюй **зараз** обидва PEM'и в password manager:

- `flatcraft-staging.cf-origin-cert` — повний текст cert'у, включно з `BEGIN` і `END` рядками
- `flatcraft-staging.cf-origin-key` — повний текст private key, включно з `BEGIN` і `END`

Перевір локально, що скопіювалось не зіпсованим:

```bash
# Збережи cert у tmp файл і перевір:
cat > /tmp/cf-cert.pem
# (paste cert + Ctrl+D)

openssl x509 -in /tmp/cf-cert.pem -noout -subject -dates -ext subjectAltName 2>&1
```

Очікувано:

```
subject=O=CloudFlare, Inc., OU=CloudFlare Origin CA, CN=CloudFlare Origin Certificate
notBefore=...2026...
notAfter=...2041...
X509v3 Subject Alternative Name:
    DNS:hart.crimea.ua, DNS:*.hart.crimea.ua
```

Якщо `unable to load certificate` — копія зіпсована, повертайся в CF UI (якщо ще не закрив) або перегенеруй.

```bash
shred -u /tmp/cf-cert.pem  # видали з диска
```

## D.4. WAF — Country Block RU/BY

1. CF dashboard → твій домен → **Security** → **WAF** → **Custom rules**.
2. **Create rule**.
3. **Rule name:** `block-ru-by`
4. **If incoming requests match** → перемкни на режим **Edit expression** (текстове поле) і встав:
   ```
   (ip.geoip.country eq "RU") or (ip.geoip.country eq "BY")
   ```
5. **Then take action:** **Block**.
6. **Place at:** First (priority 1).
7. **Deploy**.

## D.5. SSL/TLS mode + Always HTTPS

### D.5.1. Encryption mode

1. CF dashboard → твій домен → **SSL/TLS** → **Overview**.
2. **SSL/TLS encryption mode:** обери **Full (strict)**.

Що це робить:

- **Full (strict)** — CF приймає https від origin, тільки якщо origin має валідний cert (наш Origin Cert підпадає).
- _Flexible / Off_ — CF→origin без TLS, plain HTTP. Не для production.
- _Full (без strict)_ — CF приймає будь-який cert, включно з self-signed. Дозволяє MITM.

### D.5.2. Edge Certificates settings

CF dashboard → SSL/TLS → **Edge Certificates** (вкладка):

- **Always Use HTTPS:** **On** (CF робить 301 redirect з http://...).
- **HTTP Strict Transport Security (HSTS):** залиш на default (Off) поки що — увімкнемо після того, як стек справді живий і staging валідовано. HSTS preload — пасткова річ для рекавері з broken cert.
- **Minimum TLS Version:** **TLS 1.2**.
- **TLS 1.3:** **On** (увімкнено за замовчуванням).
- **Automatic HTTPS Rewrites:** **On**.
- **Opportunistic Encryption:** залиш default On.

## ✅ Checkpoint D — CF infrastructure

```bash
# D.1: R2 buckets існують
# → CF dashboard → R2 → списком мають бути обидва:
#   flatcraft-artifacts (з lifecycle expire-after-90d)
#   flatcraft-backups (з lifecycle expire-after-30d)

# D.2: R2 token у password manager
# → перевір 4 записи:
#   flatcraft-staging.r2.access-key-id      (20 hex)
#   flatcraft-staging.r2.secret-access-key  (40+ chars)
#   flatcraft-staging.r2.account-id         (32 hex з URL)
#   flatcraft-staging.r2.endpoint           ("https://<account_id>.r2.cloudflarestorage.com")

# D.3: Origin Cert у password manager
# → 2 записи:
#   flatcraft-staging.cf-origin-cert (PEM, ~1500 chars)
#   flatcraft-staging.cf-origin-key  (PEM, ~1700 chars)

# D.4: WAF rule активна
# → CF dashboard → Security → WAF → Custom rules → "block-ru-by" зі статусом "On"

# D.5: SSL/TLS mode правильний
# → CF dashboard → SSL/TLS → Overview → "Full (strict)" виділено
# → SSL/TLS → Edge Certificates → "Always Use HTTPS" = On
```

### Bonus verify (R2 token реально працює)

Якщо вже встановив `rclone` (зробимо в §1, але можна зараз для перевірки):

```bash
# Створи tmp-config:
cat > /tmp/r2-test.conf <<EOF
[r2test]
type = s3
provider = Cloudflare
access_key_id = <paste flatcraft-staging.r2.access-key-id>
secret_access_key = <paste flatcraft-staging.r2.secret-access-key>
endpoint = <paste flatcraft-staging.r2.endpoint>
EOF

rclone --config /tmp/r2-test.conf lsd r2test:
# Очікувано: дві стрічки:
#           -1 2026-05-22 14:30:00        -1 flatcraft-artifacts
#           -1 2026-05-22 14:32:00        -1 flatcraft-backups

# Test upload + download:
echo "hello r2" > /tmp/r2-test.txt
rclone --config /tmp/r2-test.conf copy /tmp/r2-test.txt r2test:flatcraft-backups/
rclone --config /tmp/r2-test.conf cat r2test:flatcraft-backups/r2-test.txt
# Очікувано: "hello r2"

# Cleanup:
rclone --config /tmp/r2-test.conf delete r2test:flatcraft-backups/r2-test.txt
rm /tmp/r2-test.conf /tmp/r2-test.txt
```

Якщо `403 Forbidden` — token має не ті permissions або не той scope. Повернися в D.2 і перестворити з правильним bucket scope.

---

# Track E — DNS records

**Тривалість:** 5 хв.
**Передумова:** Checkpoint A + Checkpoint B (тобі потрібен IP сервера з B.4).

## E.1. Створити `staging.hart.crimea.ua` (A-запис, proxied)

1. CF dashboard → твій домен → **DNS** → **Records**.
2. **Add record**.
3. **Type:** A
4. **Name:** `staging` (CF додасть `.hart.crimea.ua` сам)
5. **IPv4 address:** `<server_ip з Checkpoint B>`
6. **Proxy status:** **Proxied** (orange cloud увімкнено) — КРИТИЧНО.
7. **TTL:** Auto.
8. **Comment** (опційно): `flatcraft staging`.
9. Save.

## E.2. Створити `api-staging.hart.crimea.ua`

Повтори E.1, лише:

- **Name:** `api.staging`
- IP — той самий.
- Proxied — теж On.

## ✅ Checkpoint E — DNS resolves через CF

```bash
# E.1: staging показує CF IP, НЕ твій origin
dig +short staging.hart.crimea.ua
# Очікувано: 1-2 рядки з 104.16.x.x, 104.17.x.x, 162.159.x.x, 172.64.x.x, або 173.245.x.x
# (це Cloudflare ranges)
# Якщо побачив справжній IP свого сервера (з B.4) — proxied OFF; повернись у E.1 і ввімкни orange cloud.

# E.2: api.staging — те саме
dig +short api-staging.hart.crimea.ua
# Очікувано: ті ж IP-и (CF проксі для обох записів використовує одні й ті ж edge IP'и)

# E.3: HTTPS на CF edge відповідає (хоч origin ще не піднятий)
curl -sI https://staging.hart.crimea.ua/ 2>&1 | head -3
# Очікувано: HTTP/2 522 або 521 — це CF "Web server is down" page, БО origin ще не настроєний.
# 5xx тут — нормально. Що НЕ нормально: connection refused, timeout без CF page.
```

⚠ Якщо `dig` показує origin IP — DNS-record не proxied. Виправ перед тим як йти у §1 Ansible — інакше UFW з CF-only allowlist блокує власне HTTP трафік (бо приходить з origin клієнта, не з CF).

---

# Track F — GitHub Personal Access Token

**Тривалість:** 5 хв.
**Передумова:** GitHub акаунт `stjurik` з access до `stjurik/flatcraft` repo.

## F.1. Створити PAT для GHCR pull

1. GitHub → top-right avatar → **Settings**.
2. **Developer settings** (внизу sidebar).
3. **Personal access tokens** → **Tokens (classic)** (НЕ fine-grained — fine-grained ще не підтримує `read:packages` повноцінно).
4. **Generate new token (classic)**.
5. GitHub може попросити перевірити пароль / 2FA.
6. **Note:** `flatcraft-staging-ghcr-pull`
7. **Expiration:** **90 days** — постав нагадування у календарі на ротацію.
8. **Scopes:** Постав галочку **тільки на `read:packages`**. Жодних інших.
9. Натисни **Generate token**.

Скопіюй token (`ghp_...`) ОДРАЗУ. Він покажеться один раз.

→ password manager:

- `flatcraft-staging.ghcr-token` = `ghp_...`
- `flatcraft-staging.ghcr-username` = `stjurik`

## F.2. Verify token працює

```bash
echo "<paste your ghp_token>" | docker login ghcr.io -u stjurik --password-stdin
# Очікувано: "Login Succeeded"

docker logout ghcr.io   # cleanup local credentials
```

⚠ Якщо `denied: requested access to the resource is denied` — ти не маєш доступу до `stjurik/flatcraft` repo packages. Перевір: GitHub → repo → Settings → "Packages" tab. Якщо репо приватне — token має бути від акаунта з access. Якщо публічне — взагалі не треба токен для pull.

## ✅ Checkpoint F — GitHub PAT

```
☐ flatcraft-staging.ghcr-token у password manager
☐ flatcraft-staging.ghcr-username = "stjurik"
☐ docker login ghcr.io -u stjurik --password-stdin <token> → "Login Succeeded"
```

---

# Track G — Discord webhook (для monitoring алертів)

**Тривалість:** 5 хв.
**Передумова:** Discord акаунт + сервер, де можеш створювати webhook (типово твій власний "personal" server).

## G.1. Створити канал

1. Discord → твій server → правий клік на категорії → **Create Channel**.
2. **Type:** Text channel.
3. **Name:** `flatcraft-alerts` (або вільно).
4. **Private channel:** опційно — якщо server публічний, краще private + invite собі.

## G.2. Webhook у каналі

1. Правий клік на канал → **Edit Channel** → **Integrations** (sidebar) → **Webhooks**.
2. **New Webhook** → **Copy Webhook URL**.

→ password manager: `flatcraft-staging.discord-webhook` = `https://discord.com/api/webhooks/...`

## G.3. Verify

```bash
curl -s -X POST '<paste webhook URL>' \
  -H 'Content-Type: application/json' \
  -d '{"content":"flatcraft staging preflight test ✅"}'
# Очікувано: HTTP 204 (empty response) + у Discord каналі з'явиться повідомлення
```

Якщо `401 Unauthorized` — URL зіпсований при copy/paste. Згенеруй заново.

---

# Track H — GitHub Deploy Key (відкладено)

⚠ **Цей крок робиться ПІСЛЯ §1.2 (clone repo) і ПЕРЕД першим Ansible run'ом** — НЕ зараз. Лишаю тут як reminder, що його не пропустити.

Деталі — у `docs/08_DEPLOYMENT.md` §1.5.

Суть: на сервері `sudo -u deploy ssh-keygen`, public ключ → GitHub Repo settings → Deploy keys (read-only).

---

# 🎯 Фінальний Checkpoint — все готово до §1 Ansible

Розкрий password manager і перевір, що є **всі** записи:

```
Інфра:
☐ flatcraft-staging.host                    (IPv4 з Track B)
☐ cloudflare.account.password               (2FA вже on)
☐ cloudflare.account.backup-codes

R2:
☐ flatcraft-staging.r2.access-key-id        (20 hex)
☐ flatcraft-staging.r2.secret-access-key    (40+ chars)
☐ flatcraft-staging.r2.account-id           (32 hex)
☐ flatcraft-staging.r2.endpoint             ("https://<account_id>.r2.cloudflarestorage.com")

CF Origin Cert:
☐ flatcraft-staging.cf-origin-cert          (PEM ~1500 chars)
☐ flatcraft-staging.cf-origin-key           (PEM ~1700 chars)

App secrets:
☐ flatcraft-staging.postgres-password       (64 hex)
☐ flatcraft-staging.auth-secret             (64 hex)
☐ flatcraft-staging.admin-password          (32 hex)

Backups (age):
☐ flatcraft-staging.age-public-key          ("age1...")
☐ flatcraft-staging.age-private-key         ("AGE-SECRET-KEY-1..." + файл як attachment)

Ansible:
☐ flatcraft-staging.vault-password          (64 hex — буде ANSIBLE_VAULT_PASSWORD GH secret)

GitHub:
☐ flatcraft-staging.ghcr-username           ("stjurik")
☐ flatcraft-staging.ghcr-token              ("ghp_...")

Monitoring:
☐ flatcraft-staging.discord-webhook         ("https://discord.com/api/webhooks/...")
```

**Final smoke test через CLI (опційно, але кльово):**

```bash
# 1) NS на CF
dig +short NS hart.crimea.ua | grep -q '\.cloudflare\.com\.$' && echo "✓ A" || echo "✗ A"

# 2) Server alive
ssh root@<server_ip> 'true' 2>&1 && echo "✓ B" || echo "✗ B"

# 3) DNS proxied (CF IP, не origin)
SERVER_IP="<paste з flatcraft-staging.host>"
DIG_IP=$(dig +short staging.hart.crimea.ua | head -1)
if [ "$DIG_IP" = "$SERVER_IP" ]; then
    echo "✗ E (DNS показує origin IP — proxied вимкнено)"
else
    echo "✓ E (CF proxy on)"
fi

# 4) WAF block RU/BY: візуально у CF dashboard

# 5) GHCR token валідний
echo "<paste ghcr token>" | docker login ghcr.io -u stjurik --password-stdin 2>&1 | grep -q "Succeeded" && echo "✓ F" || echo "✗ F"
docker logout ghcr.io
```

5 ✓ → ти готовий до `docs/08_DEPLOYMENT.md §1` (Ansible setup).

---

# §X. Troubleshooting

## X.1. NS не пропагуються > 24 год

**Симптом:** `dig +short NS hart.crimea.ua` все ще показує старі NS після 24 год.

**Причини:**

1. **TTL старого NS-запису був високий** (наприклад 86400). Resolver'и можуть кешувати до повного TTL. Часом — до 48 год.
2. **Реєстратор не зберіг зміну.** Зайди в панель реєстратора → перевір, що NS дійсно `*.ns.cloudflare.com`. Часом UI зберігає, а внутрішня очередь — ні. Зміни ще раз.
3. **Glue records.** Деякі реєстратори тримають окремі glue-records, які треба руками очистити. Опен support ticket до реєстратора.
4. **Кешований локальний DNS.** Спробуй через зовнішній resolver:
   ```bash
   dig +short NS hart.crimea.ua @8.8.8.8        # Google
   dig +short NS hart.crimea.ua @1.1.1.1        # Cloudflare
   ```
   Якщо external resolver вже бачить CF NS, але твій локальний — ні: чисти DNS cache:
   ```bash
   sudo systemd-resolve --flush-caches          # Ubuntu/Debian systemd
   # macOS:
   sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
   ```

## X.2. CF Origin Cert — закрив вкладку, private key пропав

**Що робити:** перегенерувати.

1. CF → SSL/TLS → Origin Server → знайди cert у списку → **Revoke**.
2. **Create Certificate** заново.
3. Цього разу **СПОЧАТКУ скопіюй private key**, потім cert. Або краще — скопіюй обидва у tmp-файл і зберігай у pass manager одразу.

## X.3. R2 token revoke (підозра leak)

CF dashboard → R2 → Manage R2 API Tokens → знайди token → **Roll** (генерує новий secret) або **Delete**. Стара secret_access_key одразу інвалідна.

Після rotate — оновити vault, re-deploy (див. `docs/08_DEPLOYMENT.md §6.2`).

## X.4. Mirohost SSH "Permission denied"

1. Перевір що `ssh -v root@<ip>` показує правильний ключ (`identity file: /home/yurii/.ssh/id_ed25519`).
2. У Mirohost панелі: знайди опцію "SSH keys" → додай pub key вручну.
3. Або в Mirohost є опція "Reset root password" — установи тимчасовий пароль, увійди по password'у, ввімкни PubkeyAuthentication, потім захищайся ключем.

## X.5. Cloudflare показує "522 Connection timed out" після deploy

Це НЕ DNS/CF issue — це означає, що CF не може дотягтися до origin. Чек-листа:

1. На сервері: `sudo ufw status` — чи відкриті 80/443?
2. На сервері: `docker ps` — чи Caddy running and healthy?
3. На сервері: `docker compose logs caddy --tail=50` — чи були помилки cert/binding?
4. З сервера на сервер: `curl -k https://localhost/` (з валідним host header — `curl -k --resolve staging.hart.crimea.ua:443:127.0.0.1 https://staging.hart.crimea.ua/`).
5. З Cloudflare у браузері: Security → Events — чи бачить CF, що твій IP блокує його запити?

Якщо firewall блокує CF IPs — `community.general.ufw` `cloudflare_ipv4.txt` оновився з 2026-05 (файл у repo). Підтягни з Cloudflare актуальний список і re-run `--tags firewall`.
