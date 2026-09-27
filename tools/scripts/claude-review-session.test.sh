#!/usr/bin/env bash
# claude-review-session.test.sh — обгортка сесії-рецензента: з якими прапорцями
# запускається claude, коли відмовляє, що передає далі. Справжній claude підмінено
# стабом у PATH, який записує аргументи; поведінку самих прапорців перевірено
# запуском 2026-09-27 (шапка скрипта), а не тут.
# Запуск: tools/scripts/claude-review-session.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${REVIEW_SESSION_UNDER_TEST:-$HERE/claude-review-session.sh}"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail=0
ok() { echo "✓ $1"; }
bad() {
  echo "✗ $1"
  fail=1
  [[ -z "${REVIEW_SESSION_UNDER_TEST:-}" ]] || exit 1
}

# Стаб: на --help друкує STUB_HELP; інакше пише аргументи (по рядку) і теку запуску.
mkdir -p "$T/bin"
cat >"$T/bin/claude" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == --help ]]; then
  printf '%s\n' "${STUB_HELP:---restricted --tools --permission-mode --no-session-persistence --settings}"
  exit 0
fi
printf '%s\n' "$@" >"$STUB_ARGS"
pwd >"$STUB_ARGS.cwd"
readlink "/proc/$$/fd/0" >"$STUB_ARGS.stdin"
echo "stub-review"
exit "${STUB_RC:-0}"
STUB
chmod +x "$T/bin/claude"

R="$T/repo"
git init -q "$R"
mkdir -p "$R/docs/promts/inputs" "$R/sub"
CTX="$R/docs/promts/inputs/_claude-review-x.md"
echo "контекст" >"$CTX"
echo "поза" >"$T/outside.md"
ARGS="$T/args"

run() { # run [аргументи скрипта] — з кореня тимчасового репо, зі стабом у PATH
  rm -f "$ARGS" "$ARGS.cwd"
  # stdin — не /dev/null навмисно: інакше тест «сесія не читає stdin» пройшов би й
  # без </dev/null у скрипті (у CI і під агентом stdin часто вже /dev/null).
  (cd "$R" && PATH="$T/bin:$PATH" STUB_ARGS="$ARGS" bash "$SCRIPT" "$@" 2>&1 <<<"чужий вивід")
}
has_arg() { grep -qxF -- "$1" "$ARGS"; }
after() { grep -A1 -xF -- "$1" "$ARGS" | tail -1; } # значення прапорця

# ─── 1. Звичайний запуск: рівно обмежена сесія ─────────────────────────────
out="$(run "$CTX")"
rc=$?
if [[ $rc == 0 && "$out" == "stub-review" ]] && has_arg -p && has_arg --restricted &&
  has_arg --no-session-persistence && [[ "$(after --tools)" == "Read,Grep,Glob" &&
  "$(after --permission-mode)" == dontAsk && "$(after --model)" == opus &&
  "$(after --settings)" == *'"deny":["Read(**/.env*)"]'* && "$(after --output-format)" == text ]]; then
  ok "запуск: -p, лише Read/Grep/Glob, dontAsk, --restricted, без збереження сесії, deny .env, opus"
else
  bad "запуск не з тими прапорцями (rc=$rc, out=$out): $(tr '\n' ' ' <"$ARGS" 2>/dev/null)"
fi
if ! grep -qiE 'dangerously|bypassPermissions|Bash|Edit|Write|acceptEdits' <(grep -vxF -- "$(after -p)" "$ARGS"); then
  ok "жодного прапорця, що знімає обмеження, і жодного інструмента запису чи команд"
else
  bad "у прапорцях є те, що знімає обмеження: $(tr '\n' ' ' <"$ARGS")"
fi
[[ "$(after -p)" == *"$CTX"* && "$(after -p)" == *"лише контрприклади"* ]] &&
  ok "промпт називає файл контексту і роль «лише контрприклади»" || bad "промпт без файла чи ролі: $(after -p)"
out="$(cd "$R/sub" && PATH="$T/bin:$PATH" STUB_ARGS="$ARGS" bash "$SCRIPT" "$CTX" 2>&1 <<<"чужий вивід")"
[[ "$(cat "$ARGS.cwd")" == "$R" ]] && ok "запуск із підтеки — сесія стартує в корені робочого дерева" ||
  bad "сесія стартувала не в корені: $(cat "$ARGS.cwd")"

[[ "$(cat "$ARGS.stdin")" == /dev/null ]] && ok "stdin сесії — /dev/null: не чекає і не читає чужий вивід" ||
  bad "stdin сесії не /dev/null: $(cat "$ARGS.stdin")"

# ─── 2. Інша модель — лише назва моделі ────────────────────────────────────
run "$CTX" sonnet >/dev/null
[[ "$(after --model)" == sonnet ]] && ok "друга позиція — модель (sonnet)" || bad "модель не передано"
out="$(run "$CTX" 'opus --dangerously-skip-permissions')"
[[ $? == 2 && ! -f "$ARGS" ]] && ok "модель із пробілами й прапорцем — відмова, claude не запущено" ||
  bad "модель із прапорцем пройшла: $out"

# ─── 3. Відмови до запуску ─────────────────────────────────────────────────
check_refuse() { # check_refuse <назва> <підрядок> <аргументи>...
  local name="$1" needle="$2" out rc
  shift 2
  out="$(run "$@")"
  rc=$?
  [[ $rc == 2 && "$out" == *"$needle"* && ! -f "$ARGS" ]] && ok "$name — відмова, claude не запущено" ||
    bad "$name — rc=$rc, запущено=$([[ -f "$ARGS" ]] && echo так || echo ні): $out"
}
check_refuse "відносний шлях" "абсолютним" docs/promts/inputs/_claude-review-x.md
check_refuse "немає файла" "немає файла" "$R/docs/promts/inputs/немає.md"
check_refuse "файл поза робочим деревом" "поза робочим деревом" "$T/outside.md"
check_refuse "без аргументів" "використання"
check_refuse "три аргументи" "використання" "$CTX" opus зайвий
out="$(cd "$T" && PATH="$T/bin:$PATH" STUB_ARGS="$ARGS" bash "$SCRIPT" "$T/outside.md" 2>&1)"
[[ $? == 2 && "$out" == *"worktree"* ]] && ok "запуск поза git — відмова" || bad "поза git: $out"

# ─── 4. Стара версія Claude Code без потрібного прапорця — відмова ─────────
for missing in --restricted --tools --permission-mode; do
  help="--restricted --tools --permission-mode --no-session-persistence --settings"
  out="$(STUB_HELP="${help/$missing /}" run "$CTX")"
  [[ $? == 2 && "$out" == *"не знає $missing"* && ! -f "$ARGS" ]] &&
    ok "CLI без $missing — відмова, а не сесія без обмежень" || bad "CLI без $missing — запущено: $out"
done

# ─── 5. Код виходу claude передається ──────────────────────────────────────
out="$(STUB_RC=1 run "$CTX")"
[[ $? == 1 ]] && ok "claude впав (1) — скрипт повертає 1, а не 0" || bad "код виходу claude загублено"

# ─── 6. Мутації ─────────────────────────────────────────────────────────────
if [[ -z "${REVIEW_SESSION_UNDER_TEST:-}" && $fail == 0 ]]; then
  src="$(<"$SCRIPT")"
  n=0
  mutate() { # mutate <назва> <було> <стало> — «було» мусить стояти в скрипті рівно раз
    local name="$1" from="$2" to="$3" rest m="$T/mut$((++n)).sh"
    rest="${src#*"$from"}"
    if [[ "$rest" == "$src" || "$rest" == *"$from"* ]]; then
      bad "мутант «$name»: текст не знайдено рівно один раз — мутація застаріла"
      return
    fi
    printf '%s\n' "${src/"$from"/"$to"}" >"$m"
    if REVIEW_SESSION_UNDER_TEST="$m" bash "$HERE/$(basename "$0")" >"$m.out" 2>&1; then
      bad "мутант ВИЖИВ: $name"
    else
      ok "мутанта вбито: $name"
    fi
  }
  # shellcheck disable=SC2016 # дослівний текст скрипта
  {
    mutate "без --restricted" '  --restricted \' ''
    mutate "режим acceptEdits" '  --permission-mode dontAsk \' '  --permission-mode acceptEdits \'
    mutate "з Bash" '  --tools Read,Grep,Glob \' '  --tools Read,Grep,Glob,Bash \'
    mutate "без перевірки версії" 'for flag in --restricted --tools' 'for flag in --tools'
    mutate "без перевірки «поза деревом»" '[[ "$CTX" == "$ROOT"/* ]] ||' 'true ||'
    mutate "модель без перевірки" '[[ "$MODEL" =~ ^[a-z0-9.-]+$ ]] ||' 'true ||'
    mutate "без deny .env" '"deny":["Read(**/.env*)"]' '"deny":[]'
    mutate "stdin не закрито" '--output-format text </dev/null' '--output-format text'
  }
fi

if [[ $fail == 1 ]]; then
  echo "FAIL"
  exit 1
fi
echo "Усі тести пройдено."
