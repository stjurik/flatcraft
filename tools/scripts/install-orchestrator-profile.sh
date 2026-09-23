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

# Хук-лічильник натискань (log-permission-request.sh). Хук виконується БЕЗ
# жодного кліку, тож він сильніший за будь-який дозвіл: якби він запускав файл
# із репозиторію, оркестратор, відредагувавши той файл, отримав би автоматичне
# виконання будь-чого в обхід заборон. Тому:
#   - запускається копія поза репо, у HOOKS_DIR, з правами 555;
#   - профіль забороняє її правити (REQUIRED_DENY нижче);
#   - --check звіряє копію з git побайтово;
#   - єдина дозволена в профілі команда хука — HOOK_CMD, дослівно.
# FLATCRAFT_HOOKS_DIR — лише для тестів; команда хука завжди вказує на $HOME.
HOOK_SRC="$ROOT/tools/scripts/log-permission-request.sh"
HOOKS_DIR="${FLATCRAFT_HOOKS_DIR:-$HOME/.flatcraft/hooks}"
HOOK_DST="$HOOKS_DIR/log-permission-request.sh"
# shellcheck disable=SC2016 # $HOME має розгорнути shell хука, а не цей скрипт
HOOK_CMD='bash "$HOME/.flatcraft/hooks/log-permission-request.sh"'

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
  'Edit(~/.flatcraft/**)'
  'Write(~/.flatcraft/**)'
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

# Будь-який обробник хука, крім HOOK_CMD дослівно, — відмова: інший тип (http,
# prompt, agent), інша команда чи HOOK_CMD із дописаним «; щось» однаково
# виконуються без кліку.
foreign="$(jq -r --arg c "$HOOK_CMD" '
  [(.hooks // {}) | to_entries[] | .value[]? | .hooks[]?
   | select(.type != "command" or .command != $c or has("args"))
   | (.command // .url // .prompt // (.type + "?"))] | .[]' "$PROFILE")"
if [[ -n "$foreign" ]]; then
  echo "відмова: у профілі чужий хук — локальний файл не змінено:" >&2
  printf '  ✗ %s\n' "$foreign" >&2
  exit 1
fi
if jq -e '(.hooks // {}) != {}' "$PROFILE" >/dev/null && [[ ! -f "$HOOK_SRC" ]]; then
  echo "відмова: профіль має хук, а в репо немає $HOOK_SRC" >&2
  exit 2
fi

current='{}'
[[ -f "$LOCAL" ]] && current="$(cat "$LOCAL")"
merged="$(jq -s '
  .[0] as $l | .[1] as $p
  | $l | .permissions = (($l.permissions // {})
      + { allow: ((($l.permissions.allow // []) + ($p.permissions.allow // [])) | unique),
          deny:  ((($l.permissions.deny  // []) + ($p.permissions.deny  // [])) | unique) })
  | if ($p.hooks // {}) == {} then .
    else .hooks = reduce ($p.hooks | keys[]) as $e (($l.hooks // {});
      .[$e] = (((.[$e] // []) + $p.hooks[$e]) | unique))
    end
' <(printf '%s' "$current") "$PROFILE")"

# Порівняння як МНОЖИН. Claude Code дописує новий дозвіл у кінець списку, коли
# yurii тисне «більше не питати», тож порядок у локальному файлі не наш. Перша
# редакція порівнювала з порядком і 2026-09-23 казала «НЕ ВСТАНОВЛЕНО» при
# повністю встановленому профілі.
same_as_sets() { # same_as_sets <json1> <json2>
  local norm='def n: (if .permissions then .permissions |= with_entries(.value |= (if type == "array" then unique else . end)) else . end)
    | (if .hooks then .hooks |= map_values(unique) else . end); n'
  [[ "$(jq -S "$norm" <<<"$1")" == "$(jq -S "$norm" <<<"$2")" ]]
}
hook_state() { # друкує: none | ok | missing | drift
  if jq -e '(.hooks // {}) == {}' "$PROFILE" >/dev/null; then
    echo none
  elif [[ ! -f "$HOOK_DST" ]]; then
    echo missing
  elif cmp -s "$HOOK_SRC" "$HOOK_DST"; then
    echo ok
  else
    echo drift
  fi
}

if [[ "${1:-}" == --check ]]; then
  hs="$(hook_state)"
  if same_as_sets "$merged" "$current" && [[ "$hs" == ok || "$hs" == none ]]; then
    echo "OK: профіль оркестратора вже в $LOCAL"
    exit 0
  fi
  same_as_sets "$merged" "$current" ||
    echo "НЕ ВСТАНОВЛЕНО: у $LOCAL бракує частини профілю — запустіть без --check" >&2
  [[ "$hs" == missing ]] && echo "НЕ ВСТАНОВЛЕНО: немає копії хука $HOOK_DST" >&2
  [[ "$hs" == drift ]] && echo "НЕ ВСТАНОВЛЕНО: копія хука $HOOK_DST розійшлась із git — запустіть без --check" >&2
  exit 1
fi

hs="$(hook_state)"
if [[ "$hs" == missing || "$hs" == drift ]]; then
  mkdir -p "$HOOKS_DIR"
  chmod 700 "$HOOKS_DIR"
  [[ -f "$HOOK_DST" ]] && chmod u+w "$HOOK_DST"
  cp "$HOOK_SRC" "$HOOK_DST"
  chmod 555 "$HOOK_DST"
  [[ "$hs" == drift ]] && echo "Хук-лічильник відновлено з git (копія розійшлась): $HOOK_DST" ||
    echo "Хук-лічильник встановлено: $HOOK_DST"
fi

if same_as_sets "$merged" "$current"; then
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
  # По рядку на запис: printf з одним багаторядковим аргументом ставив маркер
  # лише перед першим рядком (помічено 2026-09-23).
  sed 's/^/  • /' <<<"$old"
fi
