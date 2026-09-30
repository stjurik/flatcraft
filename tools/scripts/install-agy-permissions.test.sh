#!/usr/bin/env bash
# install-agy-permissions.test.sh — доказ, що інсталятор звужує дозволи agy і
# не чіпає решту його налаштувань.
#
# Що СПРАВЖНЄ: інсталятор і шаблон tools/agy/permissions.json.
# Що ПІДМІНЕНО: файл налаштувань agy — тимчасова копія з тими самими 12
# дозволами, що стояли на T470 2026-09-24; тека резервних копій — тимчасова.
#
# Запуск: tools/scripts/install-agy-permissions.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
SCRIPT="$HERE/install-agy-permissions.sh"
fail=0
ok() { echo "✓ $1"; }
bad() {
  echo "✗ $1"
  fail=1
}

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
S="$T/settings.json"
fresh() {
  cat >"$S" <<'JSON'
{
  "model": "Gemini 3.1 Pro (High)",
  "permissions": {
    "allow": ["command(agy)", "command(find)", "command(grep)", "command(rg)", "command(cat)",
              "command(ls)", "command(head)", "command(tail)", "command(wc)", "command(pwd)",
              "read_file(*)", "write_file(*)"]
  },
  "trustedWorkspaces": ["/home/x/hart", "/home/x/other"]
}
JSON
}
run() { (cd "$REPO" && AGY_SETTINGS="$S" FLATCRAFT_BACKUP_DIR="$T/backups" bash "$SCRIPT" "$@" 2>&1); }
MAIN="$(dirname "$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)")"

# ─── 1. Звуження: жодної команди, запис лише в inputs/ головного клону ─────
fresh
out="$(run)"
rc=$?
allow="$(jq -c '.permissions.allow' "$S")"
want="[\"read_file($MAIN)\",\"read_file($MAIN-wt)\",\"write_file($MAIN/docs/promts/inputs)\"]"
if [[ $rc == 0 && "$allow" == "$want" ]]; then
  ok "дозволи agy: читання лише клону й worktree-ів, запис лише в <клон>/docs/promts/inputs"
else
  bad "дозволи після встановлення неправильні (rc=$rc): $allow — $out"
fi
jq -e '.permissions.allow | map(select(startswith("command("))) | length == 0' "$S" >/dev/null &&
  ok "жодного command(...) — ні find, ні cat, ні сам agy" || bad "лишився command(...): $allow"
jq -e '.permissions.deny == ["write_file(/tmp)"]' "$S" >/dev/null &&
  ok "deny write_file(/tmp): agy пускає /tmp сам, без правила" || bad "немає deny для /tmp: $(jq -c .permissions "$S")"

# ─── 2. Решта налаштувань agy не зачеплена ─────────────────────────────────
if jq -e '.model == "Gemini 3.1 Pro (High)" and (.trustedWorkspaces | length == 2)' "$S" >/dev/null; then
  ok "модель за замовчуванням і довірені теки лишились як були"
else
  bad "інсталятор зачепив інші налаштування: $(jq -c . "$S")"
fi

# ─── 3. Резервна копія — з попередніми дозволами, поза репо ────────────────
b="$(find "$T/backups" -name 'agy-settings.*.json' | head -1)"
[[ -n "$b" ]] && jq -e '.permissions.allow | index("command(find)") != null' "$b" >/dev/null &&
  ok "резервна копія з попередніми 12 дозволами — поза репо" || bad "резервної копії немає або вона не та: $b"

# ─── 4. --check і повторний запуск ─────────────────────────────────────────
run --check >/dev/null && ok "--check після встановлення → 0" || bad "--check після встановлення не 0"
before="$(sha256sum "$S")"
out="$(run)"
[[ "$(sha256sum "$S")" == "$before" && "$out" == *"Змін немає"* ]] &&
  ok "повторний запуск — «Змін немає», файл той самий" || bad "повторний запуск змінив файл: $out"
fresh
run --check >/dev/null
[[ $? == 1 ]] && ok "--check на широких дозволах → 1" || bad "--check не помітив широких дозволів"

# ─── 5. Шаблон із небезпечним дозволом — відмова, файл не змінено ──────────
for danger in 'command(ls)' 'read_file(*)' 'read_file(/home)' 'write_file(*)' 'write_file(/tmp/**)' 'write_file(@REPO@/**)'; do
  fresh
  before="$(sha256sum "$S")"
  tpl="$T/tpl.json"
  jq --arg d "$danger" '.allow += [$d]' "$REPO/tools/agy/permissions.json" >"$tpl"
  out="$( (cd "$REPO" && AGY_SETTINGS="$S" AGY_PERMISSIONS_TEMPLATE="$tpl" FLATCRAFT_BACKUP_DIR="$T/backups" bash "$SCRIPT" 2>&1))"
  rc=$?
  if [[ $rc == 1 && "$(sha256sum "$S")" == "$before" ]]; then
    ok "шаблон з небезпечним дозволом відхилено: $danger"
  else
    bad "небезпечний дозвіл у шаблоні ПРОЙШОВ (rc=$rc): $danger — $out"
  fi
done

# ─── 6. Шаблон без deny для /tmp — відмова ─────────────────────────────────
fresh
before="$(sha256sum "$S")"
jq 'del(.deny)' "$REPO/tools/agy/permissions.json" >"$T/nodeny.json"
out="$( (cd "$REPO" && AGY_SETTINGS="$S" AGY_PERMISSIONS_TEMPLATE="$T/nodeny.json" FLATCRAFT_BACKUP_DIR="$T/backups" bash "$SCRIPT" 2>&1))"
[[ $? == 1 && "$(sha256sum "$S")" == "$before" && "$out" == *"/tmp"* ]] &&
  ok "шаблон без deny write_file(/tmp) — відмова, файл не змінено" || bad "шаблон без deny для /tmp пройшов: $out"

if ((fail)); then
  echo "Провалено."
  exit 1
fi
echo "Усі тести пройдено."
