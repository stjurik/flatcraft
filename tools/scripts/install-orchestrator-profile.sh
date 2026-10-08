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
#      не змінюється; правило з `*` — лише дослівно з переліку WILDCARD_OK;
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
# десятки, і межа стає нечитабельною (CLAUDE.md §6.2). --replace скидає до профілю
# те, що ДАЄ права (allow, additionalDirectories, hooks), а те, що ОБМЕЖУЄ (deny,
# ask), лишає й доповнює профілем; решту ключів локального файла не чіпає, перед
# записом робить резервну копію поза репо.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
PROFILE="$ROOT/.claude/settings.orchestrator.json"
LOCAL="$ROOT/.claude/settings.local.json"
BACKUP_DIR="${FLATCRAFT_BACKUP_DIR:-$HOME/.flatcraft-backups}"

# Хуки профілю: лічильник натискань (log-permission-request.sh, подія
# PermissionRequest) і охорона руйнівних команд (guard-destructive.sh, подія
# PreToolUse, #216). Хук виконується БЕЗ
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
#   - --check звіряє кожну копію з тим самим файлом побайтово;
#   - для кожної події дозволена рівно одна команда хука — hook_cmd її файла,
#     дослівно; охорона guard-destructive в профілі обов'язкова.
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
HOOKS_DIR="${FLATCRAFT_HOOKS_DIR:-$HOME/.flatcraft/hooks}"
# Подія → файл хука в tools/scripts/ (той самий індекс).
HOOK_EVENTS=(PermissionRequest PreToolUse)
HOOK_FILES=(log-permission-request.sh guard-destructive.sh)
hook_cmd() { # hook_cmd <файл> — єдина дозволена команда хука для цього файла
  # shellcheck disable=SC2016 # $HOME має розгорнути shell хука, а не цей скрипт
  printf 'bash "$HOME/.flatcraft/hooks/%s"' "$1"
}

# Дозвіл, що пропускає ДОВІЛЬНУ дію: будь-яку команду, будь-яку віддалену
# команду на A8 (префікс ssh обмежує те, що ДО команди, а не ПІСЛЯ — див.
# a8-ro-shell.sh), запис через gh api, merge, креденшали, root, живий Discord.
#
# Будь-який `ssh` — теж: `ssh a8-ro -o ProxyCommand=…` виконує команду ЛОКАЛЬНО
# («executed using the user's shell», man ssh_config), тож обмеження на боці A8
# тут не рятує (рецензія PR #141, Gemini 3.8 Flash, 2026-09-27).
#
# Шаблон із `*` одразу по імені програми, що сама виконує чи пише довільне:
#   git *            — `git -c alias.x='!…' x`, `-c core.pager=…` (документація
#                      Claude Code: `-c` «makes git run a program you name»);
#   tools/scripts/*  — оркестратор пише новий скрипт без кліку і запускає його
#                      (`*.test.sh` лишається: тести — і є виконання його коду, #134);
#   uv run … *       — будь-яка програма, крім трьох перевірок воркера;
#   pnpm run|exec|dlx, pnpm --filter *, npx — будь-який скрипт чи пакет;
#   sort/jq/cut/… *  — читають будь-який файл, `sort -o` перезаписує;
#   інтерпретатори   — python, node, perl, bash -c тощо.
# У режимі Auto allow-правило ще й ВИМИКАЄ перевірку класифікатором для
# збіжних команд, тож широкий allow знімає захист, а не кліки.
DANGER_RE='^Bash\(\*|^Bash\(\)|^Bash\(ssh |^Bash\(git (\*|-c|-C)|^Bash\((bash |sh )?(\./)?tools/scripts/\*\)|^Bash\((bash|sh) (-c|\*)|^Bash\(uv run (?!--directory workers/cad (pytest|ruff|mypy) \*\)$)|^Bash\(pnpm (--filter \S+ )?(run|exec|dlx) |^Bash\(pnpm --filter \*|^Bash\(npx (?!prettier --check \*\)$)|^Bash\((pnpx|uvx|bunx|deno|bun) |^Bash\((npm|yarn) (exec|run|x|dlx) |^Bash\(pnpm (\S+ )*(run|exec|dlx|x) |^Bash\((sort|jq|cut|uniq|tr|date|printf|comm|column|awk|sed|tee|xargs|find|env|python3?|node|perl|ruby) |^Bash\(gh api|--force|^Bash\(git push -f|gh pr merge|^Bash\(gh auth|^Bash\(gh secret|^Bash\(gh repo (edit|delete)|^Bash\(sudo|^Bash\(docker|discord|^Bash\(rm |^Bash\(ansible-playbook (?!a8\.yml -i inventory\.a8\.ini --tags verify\)$)|^Read\(//|^Read\(~'

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
  'Bash(agy *--dangerously-skip-permissions*)'
  # Push у main найчастішою формою: `git push -u origin main` збігається з allow
  # `git push -u origin *`, а захист гілки на GitHub адмінський токен обходить
  # (enforce_admins вимкнено, замір №7). Рецензія #141, 2026-09-28.
  'Bash(git push * main)'
  'Bash(git push * main *)'
  # Живий Discord (ADR-023): і через кореневий скрипт, і через пакет напряму.
  'Bash(pnpm *discord:apply*)'
  'Bash(pnpm * apply*)'
)

# Правила з `*` — лише ПЕРЕВІРЕНІ форми. Шаблон ловить відомі небезпечні форми,
# але перелік обходів нескінченний: після DANGER_RE рецензія #141 знайшла ще
# `pnpx *`, `uvx *`, `npm exec|run *`, `bash tools/scripts/*.sh`, `pnpm -F * exec *`.
# Тому навпаки: будь-яке правило з `*`, якого тут немає дослівно, — відмова.
# Нова широка форма потребує PR саме в цей перелік — окремий, помітний крок, а не
# рядок серед десятків у профілі. Правила без `*` перевіряє лише DANGER_RE.
WILDCARD_OK=(
  'Bash(git status *)'
  'Bash(git log *)'
  'Bash(git diff *)'
  'Bash(git show *)'
  'Bash(git fetch *)'
  'Bash(git rev-parse *)'
  'Bash(git ls-remote *)'
  'Bash(git branch --list *)'
  'Bash(git worktree list *)'
  'Bash(git worktree add *)'
  'Bash(git switch *)'
  'Bash(git add *)'
  'Bash(git commit *)'
  'Bash(git push -u origin *)'
  'Bash(gh pr view *)'
  'Bash(gh pr list *)'
  'Bash(gh pr checks *)'
  'Bash(gh pr diff *)'
  'Bash(gh pr create --draft *)'
  'Bash(gh run list *)'
  'Bash(gh run view *)'
  'Bash(gh issue view *)'
  'Bash(gh issue list *)'
  'Bash(pnpm test *)'
  'Bash(pnpm vitest *)'
  'Bash(pnpm lint *)'
  'Bash(pnpm typecheck *)'
  'Bash(npx prettier --check *)'
  'Bash(uv run --directory workers/cad pytest *)'
  'Bash(uv run --directory workers/cad ruff *)'
  'Bash(uv run --directory workers/cad mypy *)'
  'Bash(bash tools/scripts/*.test.sh)'
  'Bash(bash tools/scripts/a8-report.sh -o *)'
  'Bash(agy -p *)'
  'Bash(bash tools/scripts/check-agy-scope.sh *)'
  'Bash(tools/scripts/check-agy-scope.sh *)'
  'Bash(bash ~/.flatcraft/hooks/log-permission-request.sh --count *)'
)

# Порівняння в самому bash, без `printf … | grep -q`: grep -q виходить на першому
# збігу, printf отримує SIGPIPE, і з pipefail «знайдено» перетворювалось на «не
# знайдено» — перевірене правило зрідка ставало небезпечним. Знайшли мутаційні
# прогони сценарію 28 під паралельним навантаженням: 8 хибних відмов на 320 викликів.
wildcard_ok() { # wildcard_ok <правило> — 0, якщо правило є в переліку дослівно
  local w
  for w in "${WILDCARD_OK[@]}"; do [[ "$w" == "$1" ]] && return 0; done
  return 1
}

danger_in() { # danger_in <файл> — друкує небезпечні дозволи (порожньо = чисто)
  jq -r '.permissions.allow // [] | .[]' "$1" | while IFS= read -r rule; do
    if grep -qP "$DANGER_RE" <<<"$rule"; then
      echo "$rule"
    elif [[ "$rule" == *'*'* ]] && ! wildcard_ok "$rule"; then
      echo "$rule"
    fi
  done
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

# Кінцеве `:*` Claude Code читає як стару форму «префікс і будь-які аргументи», а не
# як «двокрапка, далі що завгодно». Тож `Bash(git push * :*)` не забороняв
# `git push origin :гілка` — перевірено справжнім Claude Code 2.1.283 2026-09-28
# (`Bash(echo * :*)` пропустив `echo a :b`, а `Bash(echo * :**)` — ні). Стара форма
# має сенс лише після простого префікса; `*` чи пробіл перед кінцевим `:*` — пастка.
trap_rules="$(jq -r '.permissions | (.allow // []) + (.ask // []) + (.deny // []) | .[]
  | select(test("^Bash\\(.*(\\*|\\s):\\*\\)$"))' "$PROFILE")"
if [[ -n "$trap_rules" ]]; then
  echo "відмова: кінцеве :* після * чи пробілу Claude Code читає як стару форму префікса, а не як двокрапку — правило не діє, як написано (пишіть :** ):" >&2
  printf '  ✗ %s\n' "$trap_rules" >&2
  exit 1
fi

# Будь-який обробник хука, крім команди свого файла для своєї події дослівно, —
# відмова: інший тип (http, prompt, agent), інша команда, невідома подія чи
# команда із дописаним «; щось» однаково виконуються без кліку.
allowed_hooks="$(for i in "${!HOOK_EVENTS[@]}"; do
  jq -n --arg e "${HOOK_EVENTS[$i]}" --arg c "$(hook_cmd "${HOOK_FILES[$i]}")" '{($e): $c}'
done | jq -s 'add')"
foreign="$(jq -r --argjson ok "$allowed_hooks" '
  [(.hooks // {}) | to_entries[] | .key as $e | .value[]? | .hooks[]?
   | select(.type != "command" or .command != $ok[$e] or has("args"))
   | (.command // .url // .prompt // (.type + "?"))] | .[]' "$PROFILE")"
if [[ -n "$foreign" ]]; then
  echo "відмова: у профілі чужий хук — локальний файл не змінено:" >&2
  printf '  ✗ %s\n' "$foreign" >&2
  exit 1
fi
# Охорона руйнівних команд (#216) — обов'язкова, як заборони REQUIRED_DENY: профіль
# без неї тихо повернув би стан, коли заборону обходить інша форма команди.
if ! jq -e --arg c "$(hook_cmd guard-destructive.sh)" '
    [.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]? | select(.command == $c)]
    | length > 0' "$PROFILE" >/dev/null; then
  echo "відмова: у профілі немає хука PreToolUse (matcher Bash) guard-destructive.sh — локальний файл не змінено" >&2
  exit 1
fi
# Файл хука з коміту, на який зараз указує main на origin. SHA — з ls-remote
# (відповідь самого origin); об'єкти git адресуються вмістом, тож підмінити
# файл за справжнім SHA локально не можна.
HOOK_WANT_DIR="$(mktemp -d)"
trap 'rm -rf "$HOOK_WANT_DIR"' EXIT
authentic_hook() { # authentic_hook <шлях у репо> <куди> — файл з origin/main; код 1 — не вдалося
  local sha
  sha="$(git -C "$ROOT" ls-remote origin refs/heads/main 2>/dev/null | cut -f1)"
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || return 1
  git -C "$ROOT" cat-file -e "$sha^{commit}" 2>/dev/null ||
    git -C "$ROOT" fetch -q origin main 2>/dev/null || return 1
  git -C "$ROOT" show "$sha:$1" >"$2" 2>/dev/null
}

current='{}'
[[ -f "$LOCAL" ]] && current="$(cat "$LOCAL")"
MODE="${1:-}"
# Лише один аргумент і лише відомий: `--replace --check` мовчки виконав би
# --replace (рецензія PR #141).
if (($# > 1)) || [[ -n "$MODE" && "$MODE" != --check && "$MODE" != --replace ]]; then
  echo "використання: $(basename "$0") [--check | --replace]" >&2
  exit 2
fi
# Злиття — об'єднання множин у кожному списку. --replace скидає до профілю все,
# що ДАЄ права (allow, additionalDirectories, hooks: саме туди кліки «більше не
# питати» дописують одноразові записи), а все, що ОБМЕЖУЄ (deny, ask), лишає й
# доповнює профілем: власні заборони yurii не зникають мовчки.
# `~/` у additionalDirectories розгортається тут, у локальному файлі: чи розгортає
# його Claude Code сам, документація не каже, а в git абсолютного шляху з іменем
# користувача бути не повинно.
merged="$(jq -s --arg mode "$MODE" --arg home "$HOME" '
  .[0] as $l | .[1] as $p
  | def grants: ["allow", "additionalDirectories"];
  def lists: ["allow", "ask", "deny", "additionalDirectories"];
  def expand: map(if startswith("~/") then $home + .[1:] else . end);
  ($p | .permissions.additionalDirectories |= (if . == null then null else expand end)) as $p
  | $l | .permissions = (($l.permissions // {})
      + (reduce lists[] as $k ({};
          (if $mode == "--replace" and (grants | index($k)) != null
           then ($p.permissions[$k] // [])
           else (($l.permissions[$k] // []) + ($p.permissions[$k] // [])) end | unique) as $v
          | if $v == [] then . else .[$k] = $v end)))
  | if $mode == "--replace" then .permissions |= with_entries(select(.key as $k | (grants | index($k)) == null or ($p.permissions[$k] // null) != null)) else . end
  | if ($p.hooks // {}) == {} then .
    elif $mode == "--replace" then .hooks = $p.hooks
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
# Стан хуків рахується ОДИН раз і до будь-якого запису: без origin нема з чим
# звірити копію, і тоді не змінюємо нічого — ні налаштувань, ні копій.
# hs: none (у профілі хуків немає) | noorigin | ok | bad (є missing чи drift).
hs=none hooks_missing=() hooks_drift=()
for i in "${!HOOK_EVENTS[@]}"; do
  jq -e --arg e "${HOOK_EVENTS[$i]}" '(.hooks // {}) | has($e)' "$PROFILE" >/dev/null || continue
  f="${HOOK_FILES[$i]}"
  if ! authentic_hook "tools/scripts/$f" "$HOOK_WANT_DIR/$f"; then
    hs=noorigin
    break
  fi
  hs=ok
  if [[ ! -f "$HOOKS_DIR/$f" ]]; then
    hooks_missing+=("$f")
  elif ! cmp -s "$HOOK_WANT_DIR/$f" "$HOOKS_DIR/$f"; then
    hooks_drift+=("$f")
  fi
done
[[ "$hs" == ok ]] && ((${#hooks_missing[@]} + ${#hooks_drift[@]})) && hs=bad

# Найстаріша версія Claude Code, на якій профіль діє, як написано. До 2.1.282 правило
# з `*` одразу після двокрапки не діє жодною формою, тож `Bash(git push * :**)` не
# забороняє видалення гілки через `:гілка`. Виміряно 2026-09-28 на `echo` з контролем:
# 2.1.280 і 2.1.281 — ні, 2.1.282 (оркестратор на T470) і 2.1.283 — так. Перевіряємо
# CLI з PATH: headless-прогони йдуть через нього. Сесію у VS Code міряє
# `CLAUDE_BIN=… probe-profile-rules.sh`.
MIN_CLAUDE="2.1.282"
old_claude() { # друкує попередження, якщо claude з PATH старіший за MIN_CLAUDE
  local v
  v="$(claude --version 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')" || return 0
  [[ -n "$v" && "$(printf '%s\n%s\n' "$MIN_CLAUDE" "$v" | sort -V | head -1)" != "$MIN_CLAUDE" ]] || return 0
  echo "  ⚠ Claude Code у терміналі — $v, а профіль діє, як написано, з $MIN_CLAUDE: заборона видалення гілки через «:гілка» тут не діє — оновіть: claude update"
}

if [[ "$MODE" == --check ]]; then
  # Небезпечні дозволи в локальному файлі — сказати, а не мовчати, і за будь-якого
  # результату перевірки: перша редакція називала їх лише тоді, коли профіль уже
  # встановлено повністю (рецензія #141).
  risky=""
  [[ -f "$LOCAL" ]] && risky="$(danger_in "$LOCAL")"
  warn_risky() {
    [[ -n "$risky" ]] || return 0
    echo "  ⚠ у локальному файлі дозволи, що пропускають довільні дії — прибирає --replace:"
    sed 's/^/    • /' <<<"$risky"
  }
  if same_as_sets "$merged" "$current" && [[ "$hs" == ok || "$hs" == none ]]; then
    echo "OK: профіль оркестратора вже в $LOCAL"
    # Інформація, не помилка: скільки дозволів накопичилось понад профіль.
    extra="$(jq -n --argjson l "$current" --slurpfile p "$PROFILE" \
      '(($l.permissions.allow // []) - ($p[0].permissions.allow // [])) | length')"
    ((extra > 0)) && echo "  понад профіль у локальному файлі дозволів: $extra — прибирає --replace"
    warn_risky
    old_claude
    exit 0
  fi
  same_as_sets "$merged" "$current" ||
    echo "НЕ ВСТАНОВЛЕНО: у $LOCAL бракує частини профілю — запустіть без --check" >&2
  [[ "$hs" == noorigin ]] && echo "НЕ ПЕРЕВІРЕНО: немає зв'язку з origin — копію хука нема з чим звірити" >&2
  for f in ${hooks_missing[@]+"${hooks_missing[@]}"}; do
    echo "НЕ ВСТАНОВЛЕНО: немає копії хука $HOOKS_DIR/$f" >&2
  done
  for f in ${hooks_drift[@]+"${hooks_drift[@]}"}; do
    echo "НЕ ВСТАНОВЛЕНО: копія хука $HOOKS_DIR/$f розійшлась із main на origin — запустіть без --check" >&2
  done
  warn_risky >&2
  old_claude >&2
  exit 1
fi

if [[ "$hs" == noorigin ]]; then
  echo "відмова: не вдалося взяти хуки з main на origin — нічого не змінено" >&2
  exit 2
fi
for f in ${hooks_missing[@]+"${hooks_missing[@]}"} ${hooks_drift[@]+"${hooks_drift[@]}"}; do
  mkdir -p "$HOOKS_DIR"
  chmod 700 "$HOOKS_DIR"
  dst="$HOOKS_DIR/$f"
  if [[ -f "$dst" ]]; then
    chmod u+w "$dst"
    echo "Хук відновлено з git (копія розійшлась): $dst"
  else
    echo "Хук встановлено: $dst"
  fi
  cp "$HOOK_WANT_DIR/$f" "$dst"
  chmod 555 "$dst"
done

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
