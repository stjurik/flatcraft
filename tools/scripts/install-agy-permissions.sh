#!/usr/bin/env bash
# install-agy-permissions.sh — власні дозволи agy: лише читання і запис у
# docs/promts/inputs/ головного клону. Жодних команд.
#
# ЧОМУ. За замовчуванням agy на T470 мав 12 дозволів, серед них command(agy)
# (запуск самого себе — зокрема з --dangerously-skip-permissions), ls/cat/grep
# з довільними аргументами і write_file(*) — запис будь-куди. Правило
# оркестратора «agy — лише думка: без bash, запис лише в inputs/» трималося
# тільки на тексті промпту. Рішення yurii 2026-09-24: звузити механічно.
# Доказ — tools/scripts/agy-permissions-probe.sh, двічі: до і після.
#
# ЩО РОБИТЬ. Бере шаблон tools/agy/permissions.json, підставляє шлях ГОЛОВНОГО
# клону (не worktree: контекст для agy кладеться саме туди) і ЗАМІНЮЄ розділ
# permissions у налаштуваннях agy. Замінює, а не зливає: звуження означає
# прибрати зайве. Решту налаштувань (модель, довірені теки) не чіпає. Перед
# записом — резервна копія поза репо.
#
# Використання:
#   tools/scripts/install-agy-permissions.sh           # застосувати
#   tools/scripts/install-agy-permissions.sh --check   # 0 — дозволи вже такі
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SETTINGS="${AGY_SETTINGS:-$HOME/.gemini/antigravity-cli/settings.json}"
TEMPLATE="${AGY_PERMISSIONS_TEMPLATE:-$HERE/../agy/permissions.json}"
BACKUP_DIR="${FLATCRAFT_BACKUP_DIR:-$HOME/.flatcraft-backups}"
# Головний клон, навіть якщо скрипт запущено з worktree.
MAIN="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"
INPUTS_RULE="write_file($MAIN/docs/promts/inputs)"

[[ -f "$SETTINGS" ]] || { echo "відмова: немає налаштувань agy $SETTINGS" >&2; exit 2; }
[[ -f "$TEMPLATE" ]] || { echo "відмова: немає шаблону $TEMPLATE" >&2; exit 2; }

# deny потрібен, бо agy САМ пускає запис у /tmp без жодного правила
# (виміряно зондом 2026-09-24: WRITE_OUT у /tmp відкритий при звуженому allow,
# а в домашню теку — заблокований). У /tmp лежить базовий знімок, з яким
# check-agy-scope.sh звіряє межі після виклику, — agy міг би його підмінити.
want="$(jq --arg repo "$MAIN" '{allow: [.allow[] | gsub("@REPO@"; $repo)], deny: (.deny // [])}' "$TEMPLATE")"
jq -e '.deny | index("write_file(/tmp)") != null' <<<"$want" >/dev/null || {
  echo "відмова: у шаблоні немає deny write_file(/tmp) — agy лишився б із записом у /tmp" >&2
  exit 1
}

# Охорона шаблону: жодної команди; читання — будь-що; запис — рівно inputs/.
bad="$(jq -r --arg w "$INPUTS_RULE" '.allow[]
  | select(startswith("command(") or (startswith("write_file(") and . != $w)
           or (startswith("read_file(") | not) and (startswith("write_file(") | not))' <<<"$want")"
if [[ -n "$bad" ]]; then
  echo "відмова: у шаблоні дозвіл ширший за «читання + запис у inputs/» — налаштування не змінено:" >&2
  sed 's/^/  ✗ /' <<<"$bad" >&2
  exit 1
fi

same() { # same — поточні дозволи agy збігаються з цільовими як множини
  [[ "$(jq -S '.permissions // {} | map_values(if type == "array" then unique else . end)' "$SETTINGS")" == \
    "$(jq -S 'map_values(if type == "array" then unique else . end)' <<<"$want")" ]]
}

if [[ "${1:-}" == --check ]]; then
  if same; then
    echo "OK: дозволи agy звужено — $SETTINGS"
    exit 0
  fi
  echo "НЕ ВСТАНОВЛЕНО: дозволи agy ширші за ціль — запустіть без --check" >&2
  jq -r '.permissions.allow // [] | .[] | "  зараз: " + .' "$SETTINGS" >&2
  exit 1
fi

if same; then
  echo "Змін немає: дозволи agy вже звужено"
  exit 0
fi
mkdir -p "$BACKUP_DIR"
backup="$BACKUP_DIR/agy-settings.$(date -u +%Y%m%dT%H%M%SZ).json"
cp "$SETTINGS" "$backup"
echo "Резервна копія: $backup"
jq --argjson p "$want" '.permissions = $p' "$SETTINGS" >"$SETTINGS.tmp"
chmod --reference="$SETTINGS" "$SETTINGS.tmp"
mv "$SETTINGS.tmp" "$SETTINGS"
echo "Дозволи agy звужено: $(jq -c '.permissions.allow' "$SETTINGS")"
