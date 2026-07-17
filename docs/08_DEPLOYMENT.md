# 08. Deployment Runbook — staging.hart.crimea.ua

> Цільова інфра: **Mirohost Cloud MS21** (2 vCPU / 4 GB RAM / 40 GB SSD, ДЦ Київ) + **Cloudflare** (DNS + проксі + SSL + WAF) + **Cloudflare R2** (артефакти + бекапи). Без Terraform — сервер створюється вручну, налаштовується Ansible'ом. Див. ADR-011, ADR-014.
>
> **Цей документ — копіпаст-able інструкція.** Кожен крок має команду + блок `✓ Verify:`. Якщо verify не сходиться — стоп, не йди далі.
>
> **Час на повний прохід "з нуля":** ~3-7 днів (limiting factor — пропагація NS у Cloudflare 1-24h + людський час на R2 token'и).

---

## §0. Передполітна підготовка (manual, у браузері/CLI)

Це робить **yurii перед першим `ansible-playbook`**. Решта системи — автоматизована.

> 💡 **Детальніша версія** з паралельними треками, click-by-click інструкціями, troubleshooting'ом і фінальним 5-точковим checkpoint'ом — у `docs/09_STAGING_PREFLIGHT.md`. Цей §0 — компактна reference-версія. Якщо ти проходиш препідготовку вперше — читай **09 натомість**.

### 0.1. Замовити Mirohost Cloud MS21

1. Зайди на https://mirohost.net/cloud → тариф **MS21** (2 vCPU / 4 GB / 40 GB).
2. ОС — **Debian 12** (Bookworm), 64-bit.
3. ДЦ — **EU-IEV-1** (Київ).
4. На етапі замовлення завантаж свій **публічний SSH-ключ** (саме той, з якого будеш запускати Ansible).
5. Дочекайся email "Сервер готовий" — там буде IPv4-адреса.

**✓ Verify:**

```bash
ssh root@<server_ip> 'uname -a && cat /etc/debian_version && free -h && df -h / && nproc'
# Очікувано:
#   Linux <hostname> 6.1.x  ...
#   12.x
#   Mem: 3.8Gi / Swap: 0 (swap створиться Ansible'ом)
#   /: 40G
#   2
```

Збережи IP у password manager → запис `flatcraft-staging.host` (буде GH secret `STAGING_HOST`).

---

### 0.2. Cloudflare акаунт + домен `hart.crimea.ua`

1. https://dash.cloudflare.com → Sign Up (якщо ще нема).
2. **Add a site** → `hart.crimea.ua` → Free plan.
3. CF покаже два **nameserver'и** (типу `nina.ns.cloudflare.com`, `mateo.ns.cloudflare.com`).
4. Зайди до реєстратора crimea.ua і змінь NS на ці два. Дочекайся пропагації (1-24h).

**✓ Verify (через 1-2 год після зміни NS):**

```bash
dig +short NS hart.crimea.ua
# Очікувано: дві стрічки з *.ns.cloudflare.com
```

Також у CF dashboard біля домену зникне "Pending Nameserver Update" — стане "Active".

---

### 0.3. R2 buckets `flatcraft-artifacts` + `flatcraft-backups`

CF dashboard → **R2** (sidebar) → **Create Bucket**.

| Bucket                | Location                   | Lifecycle                    |
| --------------------- | -------------------------- | ---------------------------- |
| `flatcraft-artifacts` | Automatic / EU (Frankfurt) | Expire 90д after last access |
| `flatcraft-backups`   | Automatic / EU (Frankfurt) | Expire 30д after upload      |

**Налаштування lifecycle:**

1. Створи bucket → Settings → **Object lifecycle rules** → Add rule.
2. Для `flatcraft-artifacts`: Action = Expire, Trigger = "90 days since last accessed".
3. Для `flatcraft-backups`: Action = Expire, Trigger = "30 days since uploaded".

**✓ Verify:**

```
CF dashboard → R2 → flatcraft-artifacts → Settings → Object lifecycle rules
  має бути 1 правило, тип Expire, період 90д.
CF dashboard → R2 → flatcraft-backups → Settings → Object lifecycle rules
  має бути 1 правило, тип Expire, період 30д.
```

---

### 0.4. R2 API token (scoped до 2 bucket'ів)

CF dashboard → **R2** → **Manage R2 API Tokens** → Create API Token.

- **Token name**: `flatcraft-staging-rw`
- **Permissions**: **Object Read & Write**
- **Specify buckets**: `flatcraft-artifacts`, `flatcraft-backups` (НЕ "All buckets" — мінімум доступу)
- **TTL**: лиши порожнім (token не expire'ить; ротуємо вручну раз/рік)

Після Create — копіюй ОДРАЗУ:

- **Access Key ID** (≈20 hex chars)
- **Secret Access Key** (≈40 hex chars)
- **Account ID** (з URL у browser'і: `dash.cloudflare.com/<account_id>/r2`)
- **S3 API endpoint** — формат `https://<account_id>.r2.cloudflarestorage.com`

Збережи в password manager → запис `flatcraft-staging.r2`.

**✓ Verify** (з робочої машини, потребує rclone — встановиш у §1):

```bash
# Після §1.1, не зараз.
rclone --config /tmp/r2-test.conf config create r2 s3 \
  provider=Cloudflare \
  access_key_id=<paste> \
  secret_access_key=<paste> \
  endpoint=https://<account_id>.r2.cloudflarestorage.com
rclone --config /tmp/r2-test.conf lsd r2:
# Очікувано: дві стрічки `flatcraft-artifacts` і `flatcraft-backups`
rm /tmp/r2-test.conf
```

---

### 0.5. Cloudflare API token (опційно, для майбутньої автоматизації DNS)

Не використовується активно цією інфрою — закладаємо як placeholder для post-MVP. **Можна пропустити цей крок зараз.**

CF dashboard → My Profile → API Tokens → Create Token → Template "Edit zone DNS" → Zone Resources = `hart.crimea.ua` only.

Збережи у password manager → `flatcraft-staging.cf-api-token`. Не потрапляє у vault зараз.

---

### 0.6. Cloudflare Origin Certificate (15 років)

CF dashboard → `hart.crimea.ua` → **SSL/TLS** → **Origin Server** → **Create Certificate**.

- **Key type**: RSA-2048 (універсальніше) або ECC-P256 (сучасніше; вибирай ECC)
- **Hostnames** (через кому):
  ```
  hart.crimea.ua, *.hart.crimea.ua
  ```
  (зірочка покриває `staging`, `api.staging`, майбутній `prod`)
- **Validity**: **15 years**
- Натисни Create

CF покаже два текстові поля:

- **Origin Certificate** (PEM, `-----BEGIN CERTIFICATE-----...`)
- **Private Key** (PEM, `-----BEGIN PRIVATE KEY-----...`)

⚠ **Private Key показується ОДИН раз.** Скопіюй обидва в password manager → записи `flatcraft-staging.cf-origin-cert` і `flatcraft-staging.cf-origin-key`.

**✓ Verify** (вміст cert'у валідний):

```bash
# Збережи cert у тимчасовий файл і перевір:
cat > /tmp/cf-cert.pem <<'EOF'
-----BEGIN CERTIFICATE-----
...paste here...
-----END CERTIFICATE-----
EOF
openssl x509 -in /tmp/cf-cert.pem -noout -subject -dates -ext subjectAltName
# Очікувано:
#   subject=O=CloudFlare, Inc., OU=CloudFlare Origin CA, CN=CloudFlare Origin Certificate
#   notBefore=... 2026
#   notAfter=... 2041
#   X509v3 Subject Alternative Name: DNS:hart.crimea.ua, DNS:*.hart.crimea.ua
rm /tmp/cf-cert.pem
```

---

### 0.7. WAF Country Block для RU/BY

CF dashboard → `hart.crimea.ua` → **Security** → **WAF** → **Custom rules** → Create rule.

- **Rule name**: `block-ru-by`
- **When incoming requests match**: `(ip.geoip.country eq "RU") or (ip.geoip.country eq "BY")`
- **Then action**: Block

Save + Deploy.

**✓ Verify** (через 1-2 хв):

```bash
# Має повертати CF block-page, не апку. Використай VPN з RU exit
# АБО просто перевір у CF dashboard → Security → Events:
# після першого блоку (трапиться сам, бо боти зайдуть протягом години)
# побачиш Event з Country=RU/BY і Action=block.
```

---

### 0.8. DNS records — `staging` + `api.staging` (proxied)

CF dashboard → `hart.crimea.ua` → **DNS** → **Records** → Add record.

| Type | Name          | Content              | Proxy                      | TTL  |
| ---- | ------------- | -------------------- | -------------------------- | ---- |
| A    | `staging`     | `<server_ip з §0.1>` | **Proxied** (orange cloud) | Auto |
| A    | `api.staging` | `<server_ip з §0.1>` | **Proxied**                | Auto |

**Чому Proxied (НЕ DNS-only):** саме proxy ховає origin IP і пускає WAF + DDoS protection. DNS-only показує IP у публічному dig'у — тоді UFW-allow-from-CF не врятує.

**✓ Verify:**

```bash
dig +short staging.hart.crimea.ua
# Очікувано: IP з 173.245.x.x АБО 104.16.x.x — це Cloudflare ranges, НЕ твій сервер
dig +short api-staging.hart.crimea.ua
# Очікувано: те саме
```

Якщо побачив origin IP — record не proxied; повернись у Records і ввімкни orange cloud.

---

### 0.9. SSL/TLS mode + Always HTTPS

CF dashboard → `hart.crimea.ua` → **SSL/TLS** → **Overview**:

- **SSL/TLS encryption mode**: **Full (strict)**

Чому **Full (strict)**, не Flexible/Full:

- _Flexible_: CF↔origin без TLS. Подивляться все, що йде через інтернет.
- _Full_: CF приймає будь-який cert, в т.ч. self-signed.
- _Full (strict)_: вимагає, щоб origin мав валідний cert (наш CF Origin Cert підпадає).

CF dashboard → **SSL/TLS** → **Edge Certificates**:

- **Always Use HTTPS**: **On** (CF робить 301 redirect 80→443).
- **Minimum TLS Version**: TLS 1.2.
- **TLS 1.3**: On.
- **Automatic HTTPS Rewrites**: On.

**✓ Verify** (після §2 коли стек живий):

```bash
curl -sI http://staging.hart.crimea.ua/ | head -1
# Очікувано: HTTP/1.1 301 Moved Permanently   ← CF робить redirect
curl -sI https://staging.hart.crimea.ua/ | head -1
# Очікувано: HTTP/2 200
```

---

### 0.10. Згенерувати secrets

З робочої машини (`yurii@workstation`):

```bash
# Postgres password
openssl rand -hex 32
# Зберегти у password manager → flatcraft-staging.postgres-password

# Auth secret (для Auth.js, Phase 3+)
openssl rand -hex 32
# → flatcraft-staging.auth-secret

# Admin password (Phase 3 seed)
openssl rand -hex 16
# → flatcraft-staging.admin-password

# Vault password (для ansible-vault encrypt)
openssl rand -hex 32
# → flatcraft-staging.vault-password (буде GH secret ANSIBLE_VAULT_PASSWORD)

# Age keypair для backups
brew install age   # або apt install age
age-keygen -o /tmp/flatcraft-age.key
cat /tmp/flatcraft-age.key
# Виведе:
#   # created: 2026-05-22T...
#   # public key: age1xyz...     ← це піде у vault як vault_age_public_key
#   AGE-SECRET-KEY-1...          ← це у password manager (НЕ у vault!)
# Збережи в pass mgr → flatcraft-staging.age-private-key (повний файл).
# Public частину (age1xyz...) — також збережи окремо, простіше пастити у vault.
shred -u /tmp/flatcraft-age.key   # видали з диску
```

⚠ **Age private key — окремо від vault'у.** Якщо репо+vault скомпрометовано, доступ до бекапів все ще залишається безпечним.

---

### 0.11. GHCR Personal Access Token

GitHub → top-right avatar → Settings → Developer settings → Personal access tokens → **Tokens (classic)** → Generate new token (classic).

- **Note**: `flatcraft-staging-ghcr-pull`
- **Expiration**: 90 days (поставимо ротацію в календар)
- **Scope**: `read:packages` ONLY (нічого більше)

Скопіюй token (`ghp_...`). Він покажеться один раз.

→ password manager: `flatcraft-staging.ghcr-token`.

**✓ Verify:**

```bash
echo "<token>" | docker login ghcr.io -u stjurik --password-stdin
# Очікувано: "Login Succeeded"
docker logout ghcr.io
```

---

### 0.12. Зведена таблиця secrets

Перед §1 переконайся, що в password manager є:

| Назва (у pass mgr)                         | Куди йде                                                               | Розмір            |
| ------------------------------------------ | ---------------------------------------------------------------------- | ----------------- |
| `flatcraft-staging.host`                   | GH secret `STAGING_HOST` + Ansible inventory                           | IPv4              |
| `flatcraft-staging.r2.access-key-id`       | vault `vault_s3_access_key_id`                                         | ~20 hex           |
| `flatcraft-staging.r2.secret-access-key`   | vault `vault_s3_secret_access_key`                                     | ~40 hex           |
| `flatcraft-staging.r2.endpoint`            | vault `vault_s3_endpoint`                                              | URL               |
| `flatcraft-staging.cf-origin-cert`         | vault `vault_cf_origin_cert`                                           | PEM cert          |
| `flatcraft-staging.cf-origin-key`          | vault `vault_cf_origin_key`                                            | PEM key           |
| `flatcraft-staging.postgres-password`      | vault `vault_postgres_password`                                        | 64 hex            |
| `flatcraft-staging.auth-secret`            | vault `vault_auth_secret`                                              | 64 hex            |
| `flatcraft-staging.admin-password`         | vault `vault_seed_admin_password`                                      | 32 hex            |
| `flatcraft-staging.age-public-key`         | vault `vault_age_public_key`                                           | `age1...`         |
| `flatcraft-staging.age-private-key`        | password manager only (НЕ vault!)                                      | full age.key file |
| `flatcraft-staging.ghcr-token`             | vault `vault_ghcr_token`                                               | `ghp_...`         |
| `flatcraft-staging.discord-webhook`        | vault `vault_discord_webhook_url`                                      | URL               |
| `flatcraft-staging.vault-password`         | GH secret `ANSIBLE_VAULT_PASSWORD` + локальний ~/.flatcraft-vault-pass | 64 hex            |
| `flatcraft-staging.ssh-deploy-private-key` | GH secret `SSH_PRIVATE_KEY`                                            | ed25519 priv      |

13 vault-полів + 3 окремих secret'и (host, vault password, ssh deploy key).

---

## §1. One-time setup на робочій машині

### 1.1. Залежності

```bash
# Ubuntu/Debian/WSL:
sudo apt update
sudo apt install -y python3-pip python3-venv age rclone

# Ansible через pipx (щоб не конфліктувати з system Python):
sudo apt install -y pipx
pipx install ansible-core==2.16.*
pipx install ansible-lint==24.*

# Ansible collections (один раз):
ansible-galaxy collection install community.general community.docker ansible.posix
```

**✓ Verify:**

```bash
ansible --version | head -1     # ansible-core 2.16.x
ansible-lint --version | head -1 # ansible-lint 24.x
age --version                    # 1.x
rclone version | head -1         # rclone v1.6x+
```

---

### 1.2. Clone repo

```bash
cd ~
git clone git@github.com:stjurik/flatcraft.git
cd flatcraft
```

**✓ Verify:**

```bash
git log --oneline -5
ls infra/ansible/site.yml   # exists
```

---

### 1.3. Vault password file (для passwordless ansible run'у)

```bash
# Запиши vault password у файл, який Ansible читає замість --ask-vault-pass:
cat > ~/.flatcraft-vault-pass <<< "<paste from password manager: flatcraft-staging.vault-password>"
chmod 600 ~/.flatcraft-vault-pass
export ANSIBLE_VAULT_PASSWORD_FILE=~/.flatcraft-vault-pass
# Додай у ~/.bashrc щоб не вводити кожного разу:
echo 'export ANSIBLE_VAULT_PASSWORD_FILE=~/.flatcraft-vault-pass' >> ~/.bashrc
```

---

### 1.4. Render inventory + vars + vault

```bash
cd ~/flatcraft/infra/ansible

# Inventory (з реальним IP):
cp inventory.ini.example inventory.staging.ini
$EDITOR inventory.staging.ini
# Розкоментуй staging-server рядок, встав <server_ip з §0.1>.

# Non-secret vars:
cp group_vars/all.yml.example group_vars/all.yml
$EDITOR group_vars/all.yml
# - вписати свій публічний SSH-ключ у deploy_authorized_keys
# - (опційно) звузити ssh_allowed_ips з 0.0.0.0/0 до конкретного IP

# Vault (secrets):
cp group_vars/all.vault.yml.example group_vars/all.vault.yml
$EDITOR group_vars/all.vault.yml
# Замінити кожний __REPLACE_*__ на значення з password manager.
# Для vault_cf_origin_cert / vault_cf_origin_key — multi-line PEM (зберегти `|` блок!).
```

**✓ Verify (перед encrypt — плейн ще читабельний):**

```bash
# Жодних __REPLACE_*__ не лишилось:
grep -n '__REPLACE_' group_vars/all.vault.yml
# Очікувано: empty output (exit 1)
```

**Encrypt vault:**

```bash
ansible-vault encrypt group_vars/all.vault.yml
# Файл тепер $ANSIBLE_VAULT;1.1;AES256... — безпечно комітити.

# Sanity check — vault password працює:
ansible-vault view group_vars/all.vault.yml | head -3
# Має показати plain YAML.
```

**✓ Verify повне rendering (lint + syntax):**

```bash
cd ~/flatcraft/infra/ansible
ansible-playbook site.yml --syntax-check
ansible-lint --offline
# Обидва — 0 errors. У ansible-lint має бути "Last profile that met the validation criteria was 'production'".
```

---

### 1.5. GitHub Deploy Key для git clone на сервері

Сервер потребує SSH-ключа з read-access до flatcraft repo (щоб `git pull` працював у роль flatcraft).

**Зайди ssh root@<server_ip>**:

```bash
# Ще ДО першого ansible-playbook'у — створимо deploy-key:
ssh root@<server_ip>

# На сервері:
adduser --disabled-password --gecos '' deploy
sudo -u deploy ssh-keygen -t ed25519 -f /home/deploy/.ssh/id_ed25519 -N '' -C 'deploy@flatcraft-staging'
cat /home/deploy/.ssh/id_ed25519.pub
# Скопіюй пуб ключ.
exit
```

**На GitHub**: Repo settings → Deploy keys → Add deploy key.

- **Title**: `flatcraft-staging-deploy`
- **Key**: paste pub key
- **Allow write access**: ❌ (тільки read; deploy'у write не треба)

**✓ Verify** (з сервера):

```bash
ssh root@<server_ip> 'sudo -u deploy ssh -o StrictHostKeyChecking=accept-new -T git@github.com'
# Очікувано: "Hi stjurik/flatcraft! You've successfully authenticated, but GitHub does not provide shell access."
```

⚠ Якщо першого ansible run'у пропустиш цей крок — роль flatcraft впаде на `ansible.builtin.git` (Permission denied publickey).

---

## §2. Перший повний deploy

> Передумова: §0 і §1 завершено. Сервер — голий Debian 12. Жоден ansible run ще не виконувався.

### 2.1. Зібрати образи staging

З робочої машини запусти `release.yml`:

```bash
# GitHub UI варіант (рекомендований):
# 1. Repo → Actions → Release images → "Run workflow"
# 2. Branch: main, Reason: "first staging build"
# 3. Run workflow

# Або CLI (gh):
gh workflow run release.yml -f reason="first staging build"
```

Workflow білдить 3 образи (~5-10 хв) і пушить:

- `ghcr.io/stjurik/flatcraft-api:staging`
- `ghcr.io/stjurik/flatcraft-web:staging`
- `ghcr.io/stjurik/flatcraft-cad-worker:staging`
- Кожен також з тегом `sha-<full>`.

**✓ Verify:**

```bash
gh run list --workflow=release.yml --limit=1
# Очікувано: STATUS=completed, CONCLUSION=success

# Перевірити, що образи у GHCR:
docker pull ghcr.io/stjurik/flatcraft-api:staging
docker pull ghcr.io/stjurik/flatcraft-web:staging
docker pull ghcr.io/stjurik/flatcraft-cad-worker:staging
docker images | grep flatcraft
```

---

### 2.2. Повний Ansible run (provision + deploy)

```bash
cd ~/flatcraft/infra/ansible

ansible-playbook -i inventory.staging.ini site.yml
# Якщо НЕ налаштував ANSIBLE_VAULT_PASSWORD_FILE — додай --ask-vault-pass
```

Тривалість: 5-15 хв (apt updates, swap creation, docker install, image pulls).

**Що відбувається пошагово:**

1. **base** — apt update, ставить fail2ban/age/rclone, /swapfile 2GB, deploy-user, SSH hardening
2. **docker** — Docker engine + compose plugin, ghcr login
3. **firewall** — UFW deny + Cloudflare IP allow
4. **flatcraft** — git pull, render .env.prod, CF certs, `docker compose up -d`
5. **backups** — cron 03:00 + rclone config
6. **monitoring** — cron 5min + Discord webhook

**✓ Verify посеред run'у (інший термінал):**

```bash
# Дивись прогрес ssh sessions:
ssh deploy@<server_ip> 'docker ps --format "table {{.Names}}\t{{.Status}}"'
# Після ~3-5хв має з'явитись 6 контейнерів зі статусом "healthy".
```

**✓ Verify після завершення:**

```bash
# З сервера — всі контейнери healthy?
ssh deploy@<server_ip> 'docker ps --format "table {{.Names}}\t{{.Status}}"'
# Очікувано (6 рядків):
#   flatcraft-postgres-1     Up X minutes (healthy)
#   flatcraft-redis-1        Up X minutes (healthy)
#   flatcraft-cad-worker-1   Up X minutes (healthy)
#   flatcraft-api-1          Up X minutes (healthy)
#   flatcraft-web-1          Up X minutes (healthy)
#   flatcraft-caddy-1        Up X minutes (healthy)

# Public endpoints живі?
curl -sI https://staging.hart.crimea.ua/ | head -1
# Очікувано: HTTP/2 200

curl -s https://api-staging.hart.crimea.ua/health
# Очікувано: {"status":"ok","uptime":...,"version":"0.0.0"}

# Cron'и зареєстровані?
ssh deploy@<server_ip> 'crontab -l'
# Очікувано: 3 рядки — backup 03:00, monitor */5, prune weekly.

# UFW правила?
ssh deploy@<server_ip> 'sudo ufw status numbered | head -20'
# Очікувано: ALLOW 22 from <ssh_allowed_ips>, ALLOW 80/443 from кожного CF range.

# Swap працює?
ssh deploy@<server_ip> 'free -h && cat /proc/swaps'
# Очікувано: Swap 2.0Gi, /swapfile 2097148 0.
```

---

### 2.3. Налаштувати GH secrets для CI deploy

Після того, як перший ansible run пройшов вручну, CI може робити re-deploy через `deploy-staging.yml`. Для цього треба 3 GH secrets:

GitHub Repo → Settings → Secrets and variables → **Actions** → New repository secret.

| Secret                   | Значення                                                                                                                                                                     |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `STAGING_HOST`           | `<server_ip з §0.1>`                                                                                                                                                         |
| `SSH_PRIVATE_KEY`        | приватна частина ssh-ключа, який ти додав у `deploy_authorized_keys` (`cat ~/.ssh/id_ed25519` цілком — `-----BEGIN OPENSSH PRIVATE KEY-----...END OPENSSH PRIVATE KEY-----`) |
| `ANSIBLE_VAULT_PASSWORD` | те, що зберегли у §0.10 (`flatcraft-staging.vault-password`)                                                                                                                 |

⚠ **`SSH_PRIVATE_KEY` — ed25519 без passphrase.** Якщо твій ключ має passphrase, створи окремий deploy-key:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/flatcraft-ci -N '' -C 'flatcraft-ci'
# Додай ~/.ssh/flatcraft-ci.pub у deploy_authorized_keys (group_vars/all.yml),
# зашифруй vault, re-deploy. Тоді private ~/.ssh/flatcraft-ci паасти у GH secret.
```

**Опційно**: GH Repo → Settings → Environments → New environment `staging` → Required reviewers: `stjurik`. Дозволить manual approval gate перед deploy.

**✓ Verify:**

```bash
gh secret list
# Очікувано (мінімум):
#   ANSIBLE_VAULT_PASSWORD  Updated ...
#   SSH_PRIVATE_KEY         Updated ...
#   STAGING_HOST            Updated ...
```

---

### 2.4. Smoke-перевірка через CI (тестова re-deploy)

```bash
# Workflow_dispatch на deploy-staging.yml — re-deploy того ж staging тегу:
gh workflow run deploy-staging.yml -f version=staging
gh run watch  # дивись live progress
```

**✓ Verify**: останній крок workflow це smoke curl https://staging/ + https://api/health. Якщо exit 0 → CI deploy працює.

---

## §3. Поточний deploy (через CI, regular flow)

```
   feature PR → main merge → manual release.yml → manual deploy-staging.yml
```

### 3.1. Build snapshot (`:staging`)

```bash
gh workflow run release.yml -f reason="after PR #N merge"
# Або у UI: Actions → Release images → Run workflow.
```

Тривалість: 3-6 хв (з GHA cache).

**✓ Verify:**

```bash
gh run list --workflow=release.yml --limit=1
# CONCLUSION=success
```

### 3.2. Deploy snapshot

```bash
# Deploy останній :staging:
gh workflow run deploy-staging.yml -f version=staging

# Або deploy конкретного SHA для pinning'у (recommended на staging):
gh workflow run deploy-staging.yml -f version=sha-$(git rev-parse HEAD)
```

`gh run watch` показує прогрес.

**✓ Verify:**

- останній крок workflow робить smoke curl
- ручна перевірка: відкрий https://staging.hart.crimea.ua/templates у браузері, обери L-bracket, потягни повзунки, спробуй Export → DXF.

---

## §4. Rollback

Якщо новий деплой зламав щось, відкочуємось до попереднього образу.

### 4.1. Знайти попередній sha

```bash
# Список останніх release.yml run'ів (включно з SHA):
gh run list --workflow=release.yml --limit=10
# Запам'ятай "Head SHA" попереднього успішного run'у.

# Або з git:
git log --oneline -10 main
# Знаєш sha коміту, з якого було зібрано той успішний образ — це і є тег.
```

### 4.2. Re-deploy старого

```bash
gh workflow run deploy-staging.yml -f version=sha-<full-40-char-sha>
gh run watch
```

Compose pull'не старий образ, перезапустить контейнери. Downtime ~30с (Caddy і web ребутаються, postgres/redis лишаються).

**✓ Verify:**

```bash
ssh deploy@<server_ip> 'docker inspect flatcraft-api-1 --format "{{.Config.Image}}"'
# Очікувано: ghcr.io/stjurik/flatcraft-api:sha-<old>
```

⚠ **Rollback БД-міграцій** — окрема історія. Drizzle migrations не мають автоматичного `down`. Якщо новий код запустив незворотні міграції, rollback коду не відкоче БД. Перед serious rollback'ом — `pg_dump` поточної БД (див. §5.5).

---

## §5. Інциденти

### 5.1. Де логи

```bash
ssh deploy@<server_ip>

# Контейнерні логи (запит — конкретний сервіс):
docker compose --env-file /srv/flatcraft/.env.prod \
  -f /srv/flatcraft/infra/compose/docker-compose.prod.yml \
  logs --tail=200 -f api    # або web, cad-worker, caddy, postgres, redis

# Усі контейнери одразу:
docker compose --env-file /srv/flatcraft/.env.prod \
  -f /srv/flatcraft/infra/compose/docker-compose.prod.yml logs --tail=100

# Bash шорткат — додай у ~/.bashrc на сервері:
alias fclogs='docker compose --env-file /srv/flatcraft/.env.prod -f /srv/flatcraft/infra/compose/docker-compose.prod.yml logs'

# Системні логи:
journalctl -u docker -n 100               # docker daemon
journalctl -u ssh -n 50                   # SSH (auth events)
journalctl -u fail2ban -n 50 --no-pager   # ban-актіви

# Cron-вихід (наш):
tail -n 100 /var/log/flatcraft/backup.log
tail -n 100 /var/log/flatcraft/monitor.log
tail -n 100 /var/log/flatcraft/prune.log

# UFW dropped packets:
sudo tail -n 50 /var/log/ufw.log
```

### 5.2. Перезапустити один сервіс

```bash
# Якщо api/web/cad-worker завис чи має memory leak:
ssh deploy@<server_ip>
cd /srv/flatcraft
docker compose --env-file .env.prod -f infra/compose/docker-compose.prod.yml restart api
# або: down + up (важче — викидає volumes? — НІ, named volumes persist):
docker compose --env-file .env.prod -f infra/compose/docker-compose.prod.yml up -d --force-recreate api
```

**✓ Verify:**

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep api
# Має знову бути "Up X seconds (healthy)" через ~15с (start_period).
```

### 5.3. Стек повністю лежить (всі контейнери down)

```bash
ssh deploy@<server_ip>
cd /srv/flatcraft
docker compose --env-file .env.prod -f infra/compose/docker-compose.prod.yml up -d
# Якщо image зламаний — pull нового staging:
docker compose --env-file .env.prod -f infra/compose/docker-compose.prod.yml pull
docker compose --env-file .env.prod -f infra/compose/docker-compose.prod.yml up -d
```

Якщо НЕ піднімається — дивись `docker compose logs` → причина зазвичай у:

- `.env.prod` не валідний (вручну редагували?)
- образ зламаний (rollback на попередній sha — див. §4)
- postgres data corruption (відновлення з R2 backup — §5.5)

### 5.4. Disk usage > 80% (Discord alert)

```bash
ssh deploy@<server_ip>
df -h /
du -sh /var/lib/docker /srv/flatcraft /var/lib/flatcraft/backups
# Найвірогідніше: docker images накопичились → ручне prune:
docker image prune -af --filter "until=72h"
docker volume prune -f
docker builder prune -af
# Якщо лишилось > 80% — backup'и зайняли диск (cron не chuck'ає):
ls -lh /var/lib/flatcraft/backups/
# Тримаємо лише 3 дні — якщо більше, видали руками:
find /var/lib/flatcraft/backups -name '*.dump.age' -mtime +3 -delete
```

### 5.5. Відновити БД з R2 backup

⚠ **Це руйнівна операція** — переписує поточну БД. Спочатку зроби backup поточної (якщо ще функціональна).

```bash
# З робочої машини (НЕ з сервера — приватний age-key тут):
cd /tmp

# 1. Список backup'ів у R2:
rclone --config ~/.config/rclone/rclone-flatcraft.conf lsl r2:flatcraft-backups/
# (rclone-flatcraft.conf — той самий формат, що Ansible пише на сервер;
#  локально можеш зробити окремо для recovery).

# 2. Pull потрібного:
rclone --config ~/.config/rclone/rclone-flatcraft.conf copy \
  r2:flatcraft-backups/flatcraft-db-20260520T030000Z.dump.age ./

# 3. Decrypt:
age -d -i <шлях до age private key з password manager> \
  -o flatcraft-db-20260520T030000Z.dump \
  flatcraft-db-20260520T030000Z.dump.age

# 4. Перенести на сервер:
scp flatcraft-db-20260520T030000Z.dump deploy@<server_ip>:/tmp/

# 5. На сервері — restore:
ssh deploy@<server_ip>
cd /srv/flatcraft
docker compose --env-file .env.prod -f infra/compose/docker-compose.prod.yml exec -T postgres \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists' \
  < /tmp/flatcraft-db-20260520T030000Z.dump

# 6. Verify — кількість записів повернулась:
docker compose --env-file .env.prod -f infra/compose/docker-compose.prod.yml exec -T postgres \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "select count(*) from templates;"'

# 7. Видалити tmp dump (важливо!):
shred -u /tmp/flatcraft-db-20260520T030000Z.dump.age
shred -u /tmp/flatcraft-db-20260520T030000Z.dump
ssh deploy@<server_ip> 'shred -u /tmp/flatcraft-db-20260520T030000Z.dump'
```

### 5.6. CAD-worker OOM-killed (memory pressure)

Якщо в логах api з'являється `cad-worker connection refused`, а в `docker ps` cad-worker крутиться у restart loop:

```bash
ssh deploy@<server_ip>
docker stats --no-stream
# Очікувано: cad-worker біля 1.5g cap'у на mem_limit.

dmesg | tail -50 | grep -i "killed process"
# Якщо OOM-killer — підвищити swap або зменшити Concurrency (вже 1).

# Тимчасово: рестарт worker'а:
cd /srv/flatcraft
docker compose --env-file .env.prod -f infra/compose/docker-compose.prod.yml restart cad-worker
```

Якщо OOM повторюється — upgrade Mirohost тариф (більше RAM).

### 5.7. QR-permalink у PDF (issue #70) — без нового секрету

cad-worker бере `BASE_URL` зі свого `environment:` у `infra/compose/docker-compose.prod.yml`
(`BASE_URL: ${APP_BASE_URL}`) — те саме значення, що вже використовує `api` як
`APP_BASE_URL`, окрема змінна лише тому, що worker — інший контейнер/процес.
**Нового prod-секрету не треба** — якщо `APP_BASE_URL` вже стоїть у `.env.prod`
(а він стоїть, це foundational var), QR у щойно згенерованих PDF одразу веде на
`{APP_BASE_URL}/f/{export_id}` після наступного деплою/рестарту cad-worker.
Без `BASE_URL` (або якщо `export_id` не передано з `api`) — воркер тихо
повертається до старого fallback `flatcraft://<slug>/<article>` (не працює на
телефонах, лише зворотна сумісність зі старими job'ами).

---

## §6. Ротація secrets

Періодичність:

- `ANSIBLE_VAULT_PASSWORD` — раз/рік
- R2 keys, GHCR token — раз/рік або при підозрі
- AUTH_SECRET — раз/рік (вибрасить активні JWT — приймаємо)
- CF Origin Cert — раз/15 років (CF default)
- SSH deploy key — при компрометації

### 6.1. AUTH_SECRET

```bash
# 1. Згенерувати новий:
NEW_SECRET=$(openssl rand -hex 32)
echo "$NEW_SECRET"  # зберегти у password manager

# 2. Edit vault:
cd ~/flatcraft/infra/ansible
ansible-vault edit group_vars/all.vault.yml
# замінити vault_auth_secret → новий

# 3. Commit (vault зашифрований):
git add group_vars/all.vault.yml
git commit -m "chore(infra): rotate AUTH_SECRET"
git push

# 4. Re-deploy (apply нової .env.prod):
gh workflow run deploy-staging.yml
```

Усі активні сесії інвалідовані — користувачі мають перелогінитись.

### 6.2. R2 keys

```bash
# 1. CF dashboard → R2 → Manage R2 API Tokens → Create новий → permissions=Object R+W, scope=2 bucket'и.
# 2. Скопіюй нові Access Key + Secret у password manager.
# 3. Edit vault (vault_s3_access_key_id, vault_s3_secret_access_key).
# 4. Commit + push + re-deploy (§3).
# 5. Перевір що cad-worker і backup script бачать R2:
ssh deploy@<server_ip>
docker compose ... exec cad-worker sh -c 'env | grep S3'
# Очікувано: нові ключі.

# 6. Видалити старий token у CF dashboard (revoke).
```

### 6.3. CF Origin Certificate

⚠ CF cert живе 15 років (дефолт). Ротація потрібна лише якщо: cert leak, або CF змінює CA.

```bash
# 1. CF dashboard → SSL/TLS → Origin Server → Create Certificate (новий).
# 2. Скопіюй cert + key у password manager.
# 3. Edit vault (vault_cf_origin_cert, vault_cf_origin_key).
# 4. Commit + push + re-deploy.
# Caddy перечитає certs на restart (handler у flatcraft role).

# 5. У CF dashboard — revoke старий Origin Certificate.
```

### 6.4. GHCR token

```bash
# 1. GitHub → Settings → Developer settings → PAT → Revoke старий.
# 2. Generate новий (read:packages, 90д).
# 3. Vault → vault_ghcr_token = новий.
# 4. Re-deploy (роль docker зробить `docker login ghcr.io` з новим).
```

### 6.5. SSH deploy key

При компрометації приватного ключа:

```bash
# 1. На робочій машині — згенерувати новий:
ssh-keygen -t ed25519 -f ~/.ssh/flatcraft-deploy-v2 -N '' -C 'flatcraft-deploy'

# 2. Edit group_vars/all.yml — у deploy_authorized_keys додати новий ключ (поки лишається старий).
# 3. Re-deploy → новий ключ заавторизовано на сервері.
# 4. Update GH secret SSH_PRIVATE_KEY на новий приватний.
# 5. Update lokal ~/.ssh/config якщо треба.
# 6. Verify CI deploy ще працює.
# 7. Edit group_vars/all.yml — прибрати старий ключ зі списку.
# 8. Re-deploy → старий ключ видалено з ~deploy/.ssh/authorized_keys.
```

### 6.6. ANSIBLE_VAULT_PASSWORD

⚠ Найскладніша ротація — треба перешифрувати vault.

```bash
cd ~/flatcraft/infra/ansible

# 1. Згенерувати новий пароль:
NEW_VAULT_PASS=$(openssl rand -hex 32)
echo "$NEW_VAULT_PASS" > ~/.flatcraft-vault-pass-new
chmod 600 ~/.flatcraft-vault-pass-new

# 2. Re-encrypt vault з новим паролем:
ansible-vault rekey \
  --new-vault-password-file ~/.flatcraft-vault-pass-new \
  group_vars/all.vault.yml

# 3. Замінити основний vault password file:
mv ~/.flatcraft-vault-pass-new ~/.flatcraft-vault-pass

# 4. Update GH secret ANSIBLE_VAULT_PASSWORD на новий.

# 5. Commit re-encrypted vault:
git add group_vars/all.vault.yml
git commit -m "chore(infra): rotate vault password"
git push

# 6. Verify CI deploy працює.
```

---

## §7. Телеметрія (Phase 3.3-B activation)

Код Phase 3.3 (ADR-032) — в main. Активація в проді потребує 7 мануальних кроків нижче; після них Sentry / Umami / weekly digest оживуть від самих env-значень без правок коду.

### 7.1. Cloudflare DNS для Umami

У CF dashboard додати A/CNAME запис:

- **Name:** `analytics`
- **Target:** такий самий, як `staging` (той самий origin IP; CF proxied — HTTPS обслуговує CF Origin Cert)
- **Proxy:** Proxied (помаранчева хмарка)
- **TTL:** Auto

### 7.2. Sentry — 2 проєкти

`sentry.io/organizations/<org>/projects/new/`:

1. **flatcraft-web** — платформа Browser JS (Next.js client bundle).
2. **flatcraft-server** — платформа Node.js; спільний для `api` (Fastify) і `cad-worker` (Python).

> Один DSN для api+worker, бо `beforeSend`-фільтр PII і рівень таг'ювання (`sentry.environment`, `release`) однакові. Різні runtime'и потрапляють у Sentry з окремим тегом `runtime.name` — фільтрувати легко.

Скопіювати DSN кожного. У vault:

```yaml
# infra/ansible/group_vars/all.vault.yml
vault_sentry_dsn: "https://<key>@<org>.ingest.sentry.io/<flatcraft-server-id>" # для api + worker
vault_next_public_sentry_dsn: "https://<key>@<org>.ingest.sentry.io/<flatcraft-web-id>" # для web-клієнта
```

> Web-клієнт має **окремий** публічний DSN (інлайниться у bundle під час build).

### 7.3. Discord webhook для digest

Discord Server → канал `#digest-flatcraft` → Edit Channel → Integrations → Webhooks → New Webhook → Copy URL → у vault:

```yaml
vault_digest_webhook_url: "https://discord.com/api/webhooks/<id>/<token>"
```

> Це **окремий** webhook від monitoring (`vault_discord_webhook_url` уже існує для алертів backup/disk).

### 7.4. UMAMI_APP_SECRET

```bash
openssl rand -base64 32
# → у vault: vault_umami_app_secret: "..."
```

### 7.5. Deploy (перший — БД + Umami-контейнер стартують)

```bash
ansible-playbook -i inventory.staging.ini site.yml --tags deploy
```

Що відбувається:

1. Compose тягне `ghcr.io/umami-software/umami:postgresql-v2.19.0` (~150 MB, ~30-60 с).
2. Umami-контейнер стартує → крашиться (БД `umami` ще не існує) → restart.
3. Ansible-task «Ensure umami database» → створює БД → `docker restart umami`.
4. Umami піднімається, виконує свою schema-migration, стає healthy.
5. Дефолт-адмін: `admin` / `umami`. **Одразу змінити** через UI.

Ансибль-run падає лише якщо щось справді зламано — БД-таск ідемпотентний.

### 7.6. Umami UI: створити website, отримати `website_id`

`https://analytics.hart.crimea.ua/` → login → Settings → Websites → Add:

- **Name:** hart.crimea.ua (staging)
- **Domain:** staging.hart.crimea.ua

Скопіювати UUID (`Website ID`). У vault:

```yaml
vault_umami_website_id: "<uuid>"
```

### 7.7. Повторний deploy — інлайн `website_id` у web-bundle

```bash
# Пересобрати web-image, бо NEXT_PUBLIC_* інлайняться під час build.
gh workflow run release.yml --ref main
# і дочекатися:
gh run watch
# → auto-trigger deploy-staging.yml
```

Або локально: `docker compose build web && docker compose up -d web`.

### 7.8. Acceptance-перевірка (недільний ритуал після 1-го тижня)

- **Umami dashboard** (`analytics.hart.crimea.ua`) — воронка `catalog → studio_opened → param_changed → validation_error_shown → export_clicked → export_done` показує реальні цифри.
- **Sentry** — тестова помилка з `throw new Error('smoke')` у dev-guard route → з'являється у `flatcraft-web` (для web) і `flatcraft-server` (для api/worker, розрізняються тегом `runtime.name`), з `beforeSend` PII-фільтром (email/IP порожні).
- **Discord `#digest-flatcraft`** — щонеділі 18:00 Europe/Kyiv падає markdown-digest з top-5 validation_error, failed exports, p95 export_duration.

Якщо будь-що з цих трьох не працює через тиждень → GitHub issue з тегом `observability-broken`.

---

## §8. Go-live checklist (soft-launch)

Перемикання бойового домену `hart.crimea.ua` з placeholder-стану (порожній 200) на робочий стек. Виконати після успішного тижня staging + повного проходу §7.

### 8.1. Мануальні кроки

1. **CF DNS — `hart.crimea.ua` root:**
   - Створити A запис `@` → той самий origin IP, що й `staging`. Proxied.
   - Створити A запис `api` → той самий origin IP. Proxied.
2. **Caddyfile — додати production vhost'и** (окремим PR через `Edit(infra/**)` gate; **НЕ у цьому PR**):
   ```
   hart.crimea.ua {
       tls /etc/caddy/cf-origin/cert.pem /etc/caddy/cf-origin/key.pem
       import security_headers
       reverse_proxy web:3000 { flush_interval -1 }
   }
   api.hart.crimea.ua {
       tls /etc/caddy/cf-origin/cert.pem /etc/caddy/cf-origin/key.pem
       import security_headers
       # ... той самий блок як для api-staging
   }
   ```
3. **`all.yml` — оновити `app_domain` / `api_domain`** з `staging.hart.crimea.ua` на `hart.crimea.ua`. Re-render env.prod, redeploy.
4. **NEXT_PUBLIC_UMAMI_SRC** лишається на `analytics.hart.crimea.ua` (той самий домен обслуговує обидва — staging і prod).
5. **DNS TTL** — після `dig +short hart.crimea.ua` (з чужого DNS-resolver'а) віддає CF-anycast, чекати 60-300s propagation.

### 8.2. Smoke-тести після перемикання

- [ ] `curl -fsS https://hart.crimea.ua/` → 200, HTML з `<title>hart · Креслення листового металу за 60 секунд</title>`.
- [ ] `curl -fsS https://hart.crimea.ua/templates` → 200, `<title>Каталог · hart</title>`, 5 карток.
- [ ] У браузері: відкрити студію (напр. `/templates/l_bracket`), змінити параметр → 3D preview оновлюється, `Export DXF+PDF` → отримати presigned URL, обидва файли завантажуються.
- [ ] Umami dashboard: у `Realtime` з'являються hit'и на `hart.crimea.ua` (не тільки `staging`).
- [ ] `curl -fsS https://api.hart.crimea.ua/health` → `{"status":"ok"}`.

### 8.3. KPI перший тиждень (Roadmap §KPI MVP)

Джерело:

- **users з експортом ≥ 10** — Umami dashboard, unique visitor'и з `event=export_done`. Мета — `≥ 10` за 7 днів.
- **p95 export_duration < 5c** — Discord digest пункт `p95 export_duration_ms` для `event_type=export_completed`.
- **error rate < 1%** — Sentry issues / total requests × 100. Порожньо або 0 issues — OK.

Якщо після 7 днів:

- users < 10 → продукт незнайомий; писати про запуск у пости/канали (окрема задача).
- p95 > 5c → shortcut CPU/RAM peak; переглянути ADR-011 tier'у.
- error rate > 1% → issue кожного топа-помилки, окрема гілка bugfix.

### 8.4. Rollback

Якщо після go-live виявлено критичну проблему:

1. **CF DNS — швидкий rollback:** видалити A/CNAME записи `hart.crimea.ua` і `api.hart.crimea.ua` → домен повертається до попереднього стану (порожній 200 з CF-default або через WAF-rule «Under construction»). Час: <60s (CF cache).
2. **Ansible rollback** до попереднього sha:
   ```bash
   gh workflow run deploy-staging.yml -f version=sha-<pre-go-live>
   ```
   (Runbook §4.)

Post-mortem у `docs/13_PROGRESS_LOG.md` як окремий hotfix-запис (за конвенцією `Feature X.Y.hotfix-Z`).

---

## §9. Перший день у проді — health checklist

Через ~24 год після першого deploy:

- [ ] `df -h /` < 50% (логи + docker не з'їли диск)
- [ ] `free -h` — swap використовується мало (<10%)
- [ ] `crontab -l` у deploy — backup ран o 03:00 (`tail -100 /var/log/flatcraft/backup.log`)
- [ ] R2 `flatcraft-backups` має хоч один файл `*.dump.age` (через rclone або CF dashboard)
- [ ] Discord webhook — жодних 🚨 за добу
- [ ] Sentry — порожнє (Phase 5.1 ще не активне, тому й немає DSN)
- [ ] `sudo fail2ban-client status sshd` — N banned IPs (зазвичай 5-50 на добу, нормально)
- [ ] `sudo ufw status` — правила лежать як планувалося

---

## Що НЕ покрито цим runbook'ом

- Auth/Donations (Phase 3-4) — окремо, бо потребує OAuth setup + Monobank link.
- Production deploy — окрема процедура; має включати backup verification і IP allowlist'и звужені.
- Multi-region failover — не закладено; staging single-server. Якщо ДЦ Mirohost у Києві впаде — recovery з R2 backup на іншому хостингу за ~1 год.
- Sentry/Plausible — Phase 5.1/5.2.
