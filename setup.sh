#!/usr/bin/env bash
# =============================================================================
# setup.sh — одноразова ініціалізація dev-середовища flatcraft (Phase 0.1)
# =============================================================================
# Що робить:
#   1. перевіряє передумови (Node >= 20, git)
#   2. прибирає сміття від копіювання з Windows-папки
#   3. вмикає pnpm через corepack
#   4. git init + перший коміт
#   5. pnpm install (встановлює всі залежності монорепо)
#   6. smoke test: pnpm typecheck по всіх workspace
#
# Запускати З КОРЕНЯ проєкту у WSL / Linux:  bash setup.sh
# Розраховано на native-файлову систему (WSL ext4), НЕ на /mnt/c.
# =============================================================================
set -euo pipefail

# Перейти в каталог скрипта (щоб працювало незалежно від місця запуску)
cd "$(dirname "$0")"

# --- кольоровий вивід --------------------------------------------------------
c_ok()   { printf '\033[0;32m✓ %s\033[0m\n' "$1"; }
c_info() { printf '\033[0;36m→ %s\033[0m\n' "$1"; }
c_warn() { printf '\033[0;33m! %s\033[0m\n' "$1"; }
c_err()  { printf '\033[0;31m✗ %s\033[0m\n' "$1" >&2; }
step()   { printf '\n\033[1;37m=== %s ===\033[0m\n' "$1"; }

# =============================================================================
step "1/6  Перевірка передумов"
# =============================================================================
if ! command -v node >/dev/null 2>&1; then
  c_err "Node.js не знайдено. Встанови Node 20+ (рекомендовано через nvm):"
  echo "    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash"
  echo "    nvm install 20.11.0 && nvm use 20.11.0"
  exit 1
fi
NODE_MAJOR="$(node -v | sed 's/^v\([0-9]*\).*/\1/')"
if [ "$NODE_MAJOR" -lt 20 ]; then
  c_err "Потрібен Node >= 20, а зараз $(node -v). Онови (nvm install 20.11.0)."
  exit 1
fi
c_ok "Node $(node -v)"

if ! command -v git >/dev/null 2>&1; then
  c_err "git не знайдено. Встанови: sudo apt install git"
  exit 1
fi
c_ok "git $(git --version | awk '{print $3}')"

if ! command -v corepack >/dev/null 2>&1; then
  c_err "corepack не знайдено (має йти разом з Node 20+). Спробуй: npm i -g corepack"
  exit 1
fi
c_ok "corepack присутній"

# Попередження, якщо запускаємо на /mnt/c (повільно + можливі баги symlink-ів pnpm)
case "$(pwd -P)" in
  /mnt/[a-z]/*)
    c_warn "Проєкт лежить на $(pwd -P) — це Windows-диск через WSL (DrvFs)."
    c_warn "pnpm/git працюватимуть, але повільніше. Краще перенести у ~/hart (native ext4)."
    ;;
esac

# =============================================================================
step "2/6  Прибирання сміття від попередніх спроб"
# =============================================================================
# Якщо файли копіювалися з Windows-папки, там могли лишитись артефакти
# невдалого git init на FUSE-монтуванні. Прибираємо.
rm -rf .git __wtest__ __mv1__ __mv2__ node_modules .turbo
# Прибрати можливі CRLF у самому скрипті та конфігах (Windows → WSL)
if command -v dos2unix >/dev/null 2>&1; then
  find . -type f \( -name '*.sh' -o -name '*.json' -o -name '*.yaml' -o -name '*.yml' \) \
    -not -path './node_modules/*' -exec dos2unix -q {} + 2>/dev/null || true
fi
c_ok "робочий каталог очищено"

# =============================================================================
step "3/6  Активація pnpm через corepack"
# =============================================================================
corepack enable
corepack prepare pnpm@9.12.0 --activate
c_ok "pnpm $(pnpm --version)"

# =============================================================================
step "4/6  git init + перший коміт"
# =============================================================================
git init -b main
if [ -z "$(git config user.name)" ]; then
  git config user.name "yurii"
  git config user.email "jstovbun@gmail.com"
fi
git config core.autocrlf false   # на Linux лишаємо LF як є
git add -A
git commit -m "chore: ініціалізація монорепо flatcraft (Phase 0.1)" \
           -m "Скелет: apps/{web,api}, workers/cad, packages/{cad-engine,db,types,ui}, docs/, infra/." \
  >/dev/null
c_ok "git-репозиторій ініціалізовано, перший коміт зроблено ($(git rev-parse --short HEAD))"

# =============================================================================
step "5/6  pnpm install"
# =============================================================================
c_info "Встановлення залежностей усіх workspace (це може зайняти 1-3 хв)..."
pnpm install
c_ok "залежності встановлено"
# Закоммітити згенерований lockfile
if [ -f pnpm-lock.yaml ]; then
  git add pnpm-lock.yaml
  git commit -m "chore: додати pnpm-lock.yaml" >/dev/null 2>&1 || true
  c_ok "pnpm-lock.yaml закоммічено"
fi

# =============================================================================
step "6/6  Smoke test — typecheck по всіх workspace"
# =============================================================================
c_info "Запуск pnpm typecheck (turbo прожене tsc по кожному пакету)..."
if pnpm exec turbo run typecheck --ui=stream; then
  c_ok "typecheck пройшов — скелет монорепо коректний"
else
  c_err "typecheck впав. Скопіюй вивід вище і надішли — розберемось."
  exit 1
fi

# =============================================================================
printf '\n\033[1;32m'
echo "============================================================"
echo " Phase 0.1 завершено. Скелет монорепо робочий."
echo "============================================================"
printf '\033[0m'
cat <<'NEXT'

Наступні кроки (Phase 0.2 — див. docs/02_ROADMAP.md):
  • docker compose up -d        # підняти Postgres + Redis + MinIO + Mailpit
  • потім — Drizzle init, Fastify hello-world, Next.js hello-world

Корисне:
  • pnpm dev         — запуск усього стека (коли з'явиться код у apps/)
  • pnpm typecheck   — перевірка типів
  • pnpm test        — тести (TDD з першого дня)

NEXT
