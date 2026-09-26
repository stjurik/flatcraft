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
#   tools/scripts/install-orchestrator-profile.sh             # злити
#   tools/scripts/install-orchestrator-profile.sh --check     # лише перевірити: 0 = усе на місці
#   tools/scripts/install-orchestrator-profile.sh --replace   # дозволи — РІВНО профіль
#
# --replace — для прибирання. Кожне «Так, більше не питати» дописує в локальний
# файл одноразовий дозвіл на одну конкретну команду; за місяць їх набираються
# десятки, і межа стає нечитабельною (CLAUDE.md §6.2). --replace замінює розділ
# permissions профілем цілком (allow, ask, deny, additionalDirectories), решту
# ключів локального файла лишає, перед записом робить резервну копію поза репо.
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
#   - джерело копії — НЕ робоче дерево, а файл у коміті, на який ЗАРАЗ указує
#     main на origin (SHA з `git ls-remote`, тобто від самого GitHub). Робоче
#     дерево й локальний `origin/main` оркестратор змінює без кліку (Edit,
#     `git fetch .`); main на GitHub — лише через merge yurii. Знайдено
#     рецензією Claude Opus 4.6 через agy 2026-09-23;
#   - --check звіряє копію з тим самим файлом побайтово;
#   - єдина дозволена в профілі команда хука — HOOK_CMD, дослівно.
#
# ЧОГО ЦЕ НЕ ТРИМАЄ — чесно. Профіль дозволяє запускати тести й `pnpm install`,
# а це виконання коду, який оркестратор сам пише. Такий код може переписати
# копію хука (заборона Edit/Write, за документацією, не діє на довільні
# програми; 555 не захищає від того самого користувача). Отже, копія захищена
# від випадкового дрейфу і від розгортання нерецензованого коду, але не від
# рішучого агента. Механічна межа для цього — пісочниця Claude Code
# (sandboxing), рішення yurii.
#
# FLATCRAFT_HOOKS_DIR — лише для тестів; команда хука завжди вказує на $HOME.
HOOK_PATH="tools/scripts/log-permission-request.sh"
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
  'Bash(agy *--dangerously-skip-permissions*)'
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
# Файл хука з коміту, на який зараз указує main на origin. SHA — з ls-remote
# (відповідь самого origin); об'єкти git адресуються вмістом, тож підмінити
# файл за справжнім SHA локально не можна.
HOOK_WANT="$(mktemp)"
trap 'rm -f "$HOOK_WANT"' EXIT
authentic_hook() { # пише хук з origin/main у HOOK_WANT; код 1 — не вдалося
  local sha
  sha="$(git -C "$ROOT" ls-remote origin refs/heads/main 2>/dev/null | cut -f1)"
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || return 1
  git -C "$ROOT" cat-file -e "$sha^{commit}" 2>/dev/null ||
    git -C "$ROOT" fetch -q origin main 2>/dev/null || return 1
  git -C "$ROOT" show "$sha:$HOOK_PATH" >"$HOOK_WANT" 2>/dev/null
}

current='{}'
[[ -f "$LOCAL" ]] && current="$(cat "$LOCAL")"
MODE="${1:-}"
# Злиття — об'єднання множин у кожному списку profile.permissions; з --replace —
# список профілю замість локального.
merged="$(jq -s --arg mode "$MODE" '
  .[0] as $l | .[1] as $p
  | def lists: ["allow", "ask", "deny", "additionalDirectories"];
  $l | .permissions = (($l.permissions // {})
      + (reduce lists[] as $k ({};
          if $mode == "--replace" then
            (if ($p.permissions[$k] // null) == null then . else .[$k] = ($p.permissions[$k] | unique) end)
          else
            (((($l.permissions[$k] // []) + ($p.permissions[$k] // [])) | unique) as $v
             | if $v == [] then . else .[$k] = $v end)
          end)))
  | if $mode == "--replace" then .permissions |= with_entries(select(.key as $k | (lists | index($k)) == null or ($p.permissions[$k] // null) != null)) else . end
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
hook_state() { # друкує: none | noorigin | missing | ok | drift
  if jq -e '(.hooks // {}) == {}' "$PROFILE" >/dev/null; then
    echo none
  elif ! authentic_hook; then
    echo noorigin
  elif [[ ! -f "$HOOK_DST" ]]; then
    echo missing
  elif cmp -s "$HOOK_WANT" "$HOOK_DST"; then
    echo ok
  else
    echo drift
  fi
}

# Стан хука рахується ОДИН раз і до будь-якого запису: без origin нема з чим
# звірити копію, і тоді не змінюємо нічого — ні налаштувань, ні копії.
hs="$(hook_state)"

if [[ "$MODE" == --check ]]; then
  if same_as_sets "$merged" "$current" && [[ "$hs" == ok || "$hs" == none ]]; then
    echo "OK: профіль оркестратора вже в $LOCAL"
    # Інформація, не помилка: скільки дозволів накопичилось понад профіль.
    extra="$(jq -n --argjson l "$current" --slurpfile p "$PROFILE" \
      '(($l.permissions.allow // []) - ($p[0].permissions.allow // [])) | length')"
    ((extra > 0)) && echo "  понад профіль у локальному файлі дозволів: $extra — прибирає --replace"
    exit 0
  fi
  same_as_sets "$merged" "$current" ||
    echo "НЕ ВСТАНОВЛЕНО: у $LOCAL бракує частини профілю — запустіть без --check" >&2
  [[ "$hs" == noorigin ]] && echo "НЕ ПЕРЕВІРЕНО: немає зв'язку з origin — копію хука нема з чим звірити" >&2
  [[ "$hs" == missing ]] && echo "НЕ ВСТАНОВЛЕНО: немає копії хука $HOOK_DST" >&2
  [[ "$hs" == drift ]] && echo "НЕ ВСТАНОВЛЕНО: копія хука $HOOK_DST розійшлась із main на origin — запустіть без --check" >&2
  exit 1
fi

if [[ "$hs" == noorigin ]]; then
  echo "відмова: не вдалося взяти $HOOK_PATH з main на origin — нічого не змінено" >&2
  exit 2
fi
if [[ "$hs" == missing || "$hs" == drift ]]; then
  mkdir -p "$HOOKS_DIR"
  chmod 700 "$HOOKS_DIR"
  [[ -f "$HOOK_DST" ]] && chmod u+w "$HOOK_DST"
  cp "$HOOK_WANT" "$HOOK_DST"
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
  if [[ "$MODE" == --replace ]]; then
    echo "Замінено: дозволи — рівно профіль ($(jq '.permissions.allow | length' <<<"$merged") allow, $(jq '.permissions.deny | length' <<<"$merged") deny) → $LOCAL"
  else
    echo "Додано: дозволів $added_a, заборон $added_d → $LOCAL"
  fi
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
