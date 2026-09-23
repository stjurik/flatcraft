#!/usr/bin/env bash
# install-orchestrator-profile.sh — дозволи оркестратора на T470: з git у локальний файл.
#
# ЧОМУ ЦЕ ІСНУЄ. Оркестратор на T470 працює в режимі «Edit automatically»: правки
# файлів проходять самі, а КОЖНА команда в терміналі чекає натискання yurii. Так
# автономність лишається на папері. Зняти підтвердження зовсім не можна
# (`--dangerously-skip-permissions` на T470 заборонений, CLAUDE.md §6.2), тож
# потрібен вузький, ПЕРЕВІРЕНИЙ список того, що безпечно виконувати без кліку.
#
# ЧОМУ ПРОФІЛЬ У GIT, А ЗАСТОСУВАННЯ — У ЛОКАЛЬНИЙ ФАЙЛ. Розширення VS Code читає
# `.claude/settings.local.json` сам, без прапорців запуску. Але конфігурація,
# якої немає в git, не існує (§0 п.5): тому джерело — `.claude/settings.orchestrator.json`
# у репозиторії, а цей скрипт лише зливає його в локальний файл.
#
# ЩО ГАРАНТУЄ (перевіряє .test.sh, а CI — на кожному PR):
#   1. у профілі немає небезпечних дозволів — інакше відмова, локальний файл
#      не змінюється;
#   2. у профілі є всі обов'язкові заборони — інакше відмова;
#   3. злиття лише ДОДАЄ: чужі записи yurii лишаються, повторний запуск нічого
#      не змінює;
#   4. перед записом — резервна копія ПОЗА репозиторієм (у git ігнорується лише
#      сам settings.local.json, а не копії поруч із ним);
#   5. небезпечні дозволи, які ВЖЕ є в локальному файлі, друкуються як
#      попередження — але не видаляються: це рішення yurii.
#
# Використання:
#   tools/scripts/install-orchestrator-profile.sh           # злити
#   tools/scripts/install-orchestrator-profile.sh --check   # лише перевірити: 0 = усе на місці
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
PROFILE="$ROOT/.claude/settings.orchestrator.json"
LOCAL="$ROOT/.claude/settings.local.json"
BACKUP_DIR="${FLATCRAFT_BACKUP_DIR:-$HOME/.flatcraft-backups}"

# Дозвіл, що пропускає ДОВІЛЬНУ дію: будь-яку команду, будь-яку віддалену
# команду на A8 (префікс ssh обмежує те, що ДО команди, а не ПІСЛЯ — див.
# a8-ro-shell.sh), запис через gh api, merge, креденшали, root, живий Discord.
# Єдиний дозволений ssh — `ssh a8-ro`: там межу тримає сам A8 (a8-ro-shell).
DANGER_RE='^Bash\(\*|^Bash\(\)|^Bash\(ssh (?!a8-ro )|^Bash\(gh api|--force|^Bash\(git push -f|gh pr merge|^Bash\(gh auth|^Bash\(gh secret|^Bash\(gh repo (edit|delete)|^Bash\(sudo|^Bash\(docker|discord|^Bash\(rm |^Bash\(ansible-playbook (?!a8\.yml -i inventory\.a8\.ini --tags verify\)$)|^Read\(//|^Read\(~'

REQUIRED_DENY=(
  'Bash(git push --force:*)'
  'Bash(gh pr merge:*)'
  'Bash(gh auth:*)'
  'Bash(gh secret:*)'
  'Bash(sudo:*)'
  'Edit(CLAUDE.md)'
  'Edit(.github/**)'
  'Edit(packages/db/src/migrations/**)'
  'Edit(workers/cad/tests/snapshots/**)'
  'Edit(packages/cad-engine/data/bend-machine-esi.yaml)'
)

danger_in() { # danger_in <файл> — друкує небезпечні дозволи (порожньо = чисто)
  jq -r '.permissions.allow // [] | .[]' "$1" | grep -P "$DANGER_RE" || true
}

[[ -f "$PROFILE" ]] || { echo "відмова: немає $PROFILE" >&2; exit 2; }
jq -e 'type == "object"' "$PROFILE" >/dev/null || { echo "відмова: профіль не є JSON-об'єктом" >&2; exit 2; }

bad="$(danger_in "$PROFILE")"
if [[ -n "$bad" ]]; then
  echo "відмова: у профілі небезпечні дозволи — локальний файл не змінено:" >&2
  printf '  ✗ %s\n' "$bad" >&2
  exit 1
fi
missing=()
for d in "${REQUIRED_DENY[@]}"; do
  jq -e --arg d "$d" '(.permissions.deny // []) | index($d) != null' "$PROFILE" >/dev/null || missing+=("$d")
done
if ((${#missing[@]})); then
  echo "відмова: у профілі бракує обов'язкових заборон — локальний файл не змінено:" >&2
  printf '  ✗ %s\n' "${missing[@]}" >&2
  exit 1
fi

current='{}'
[[ -f "$LOCAL" ]] && current="$(cat "$LOCAL")"
merged="$(jq -s '
  .[0] as $l | .[1] as $p
  | $l | .permissions = (($l.permissions // {})
      + { allow: ((($l.permissions.allow // []) + ($p.permissions.allow // [])) | unique),
          deny:  ((($l.permissions.deny  // []) + ($p.permissions.deny  // [])) | unique) })
' <(printf '%s' "$current") "$PROFILE")"

if [[ "${1:-}" == --check ]]; then
  if [[ "$(jq -S . <<<"$merged")" == "$(jq -S . <<<"$current")" ]]; then
    echo "OK: профіль оркестратора вже в $LOCAL"
    exit 0
  fi
  echo "НЕ ВСТАНОВЛЕНО: у $LOCAL бракує частини профілю — запустіть без --check" >&2
  exit 1
fi

if [[ "$(jq -S . <<<"$merged")" == "$(jq -S . <<<"$current")" ]]; then
  echo "Змін немає: профіль уже в $LOCAL"
else
  if [[ -f "$LOCAL" ]]; then
    mkdir -p "$BACKUP_DIR"
    backup="$BACKUP_DIR/settings.local.$(date -u +%Y%m%dT%H%M%SZ).json"
    cp "$LOCAL" "$backup"
    echo "Резервна копія: $backup"
  fi
  printf '%s\n' "$merged" >"$LOCAL.tmp" && mv "$LOCAL.tmp" "$LOCAL"
  added_a=$(($(jq '.permissions.allow | length' <<<"$merged") - $(jq '.permissions.allow // [] | length' <<<"$current")))
  added_d=$(($(jq '.permissions.deny | length' <<<"$merged") - $(jq '.permissions.deny // [] | length' <<<"$current")))
  echo "Додано: дозволів $added_a, заборон $added_d → $LOCAL"
fi

# Попередження, а не видалення: те, що yurii колись погодив, — його рішення.
old="$(danger_in "$LOCAL")"
if [[ -n "$old" ]]; then
  echo
  echo "⚠ У локальному файлі вже є дозволи, що пропускають довільні дії (CLAUDE.md §6.2)."
  echo "  Заборони профілю мають пріоритет над ними лише там, де збігаються. Варто переглянути:"
  printf '  • %s\n' "$old"
fi
