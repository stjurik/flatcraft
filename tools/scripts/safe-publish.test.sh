#!/usr/bin/env bash
# safe-publish.test.sh — обгортка публікує лише після check-leak з кодом 0; код виходу
# check-leak не маскується; у коміті й push перевіряються лише додані рядки.
# gh — заглушка в PATH: справжнього мережевого виклику немає. git — справжній, у
# тимчасовому репозиторії з «віддаленим» bare-репозиторієм поруч. Справжній
# ~/.flatcraft тест не читає: файл відомої адреси — тимчасовий.
# Запуск: tools/scripts/safe-publish.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${SAFE_PUBLISH_UNDER_TEST:-$HERE/safe-publish.sh}"
fail=0
ok() { echo "✓ $1"; }
bad() {
  echo "✗ $1"
  fail=1
  [[ -z "${SAFE_PUBLISH_UNDER_TEST:-}" ]] || exit 1
}

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
KNOWN="$T/origin-host"
# Лише документаційні адреси (RFC 5737): блок у тесті дає те, що вони у файлі відомої
# адреси. Справжній check-leak на доданих рядках цього файла дає лише попередження, тож
# сам тест можна закомітити через обгортку.
printf '%s\n' 'secret-origin.invalid' '203.0.113.77' '198.51.100.9' >"$KNOWN"
export LEAK_ORIGIN_FILE="$KNOWN"

# Ізоляція git від конфігурації машини (хуки, підпис, шаблони).
export HOME="$T/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
mkdir -p "$HOME" "$T/stub"

# Заглушка gh: записує аргументи й текст, який отримала б через --body-file.
cat >"$T/stub/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$GH_LOG"
prev=""
for a in "$@"; do
  [[ "$prev" == "--body-file" ]] && cat "$a" >"$GH_LOG.body"
  prev="$a"
done
exit "${GH_EXIT:-0}"
SH
chmod +x "$T/stub/gh"
export PATH="$T/stub:$PATH" GH_LOG="$T/gh.log"

# run <аргументи обгортки>... — вивід у $out, код у $rc; журнал gh перед цим чиститься.
run() {
  rm -f "$GH_LOG" "$GH_LOG.body"
  out="$(bash "$SCRIPT" "$@" 2>&1)"
  rc=$?
}
gh_called() { [[ -f "$GH_LOG" ]]; }

# ─── 1. gh: публікація лише при check-leak = 0 ────────────────────────────────
printf 'Опис PR без адрес.\n' >"$T/clean.md"
printf 'Сервер 203.0.113.77 відповідає.\n' >"$T/leak.md"
printf 'Origin — secret-origin.invalid.\n' >"$T/known.md"

run gh "$T/clean.md" pr create --draft --title "feat: чисто"
if [[ $rc == 0 ]] && gh_called && grep -qx -- '--body-file' "$GH_LOG" &&
  grep -qx 'feat: чисто' "$GH_LOG" && grep -q 'Опис PR без адрес' "$GH_LOG.body"; then
  ok "чистий текст — gh викликано з --body-file і заголовком"
else bad "чистий текст — rc=$rc: $out"; fi

run gh "$T/leak.md" pr comment 12
if [[ $rc == 1 ]] && ! gh_called; then ok "адреса в тексті — exit 1, gh не викликано"; else bad "адреса в тексті — rc=$rc, gh=$(gh_called && echo так || echo ні): $out"; fi

run gh "$T/known.md" issue create --title "x"
if [[ $rc == 1 ]] && ! gh_called; then ok "рядок відомої адреси — exit 1, gh не викликано"; else bad "відома адреса — rc=$rc: $out"; fi

run gh "$T/clean.md" pr create --title "сервер 203.0.113.77"
if [[ $rc == 1 ]] && ! gh_called; then ok "адреса в заголовку — exit 1, gh не викликано"; else bad "адреса в заголовку — rc=$rc: $out"; fi

out="$(LEAK_ORIGIN_FILE="$T/немає" bash "$SCRIPT" gh "$T/clean.md" issue comment 5 2>&1)"
rc=$?
if [[ $rc == 3 ]] && ! gh_called; then ok "без файла відомої адреси — exit 3, gh не викликано"; else bad "без файла відомої адреси — rc=$rc: $out"; fi

run gh "$T/немає.md" pr edit 7
if [[ $rc == 2 ]] && ! gh_called; then ok "немає файла тексту — exit 2, gh не викликано"; else bad "немає файла тексту — rc=$rc: $out"; fi

for flag in --body "--body=x" -bx --body-file -F --fill --editor --web --template; do
  run gh "$T/clean.md" pr create --title "чисто" "$flag" "текст"
  if [[ $rc == 2 ]] && ! gh_called; then ok "«$flag» повз перевірений файл — відхилено"; else bad "«$flag» — rc=$rc: $out"; fi
done

# Кожна підкоманда з переліку проходить: вилучення будь-якої з переліку тест помічає.
for sc in "pr create" "pr edit" "pr comment" "issue create" "issue comment"; do
  # shellcheck disable=SC2086 # підкоманда — два слова
  run gh "$T/clean.md" $sc 7 --title "чисто"
  if [[ $rc == 0 ]] && gh_called && grep -qx "${sc#* }" "$GH_LOG"; then ok "gh $sc — опубліковано"; else bad "gh $sc — rc=$rc: $out"; fi
done

# create без --title: gh спитав би заголовок у терміналі, повз перевірку.
for sc in "pr create" "issue create"; do
  # shellcheck disable=SC2086
  run gh "$T/clean.md" $sc --draft
  if [[ $rc == 2 ]] && ! gh_called; then ok "gh $sc без --title — відхилено"; else bad "gh $sc без --title — rc=$rc: $out"; fi
done
run gh "$T/clean.md" pr create -tчисто
if [[ $rc == 0 ]] && gh_called; then ok "gh pr create -t<заголовок> — опубліковано"; else bad "pr create -t… — rc=$rc: $out"; fi

run gh "$T/clean.md" repo delete
if [[ $rc == 2 ]] && ! gh_called; then ok "gh repo delete — не з переліку, відхилено"; else bad "gh repo delete — rc=$rc: $out"; fi

GH_EXIT=4 run gh "$T/clean.md" pr comment 12
if [[ $rc == 4 ]] && gh_called; then ok "помилка gh — її код не маскується (4)"; else bad "помилка gh — rc=$rc: $out"; fi

# ─── 2. commit: лише додані рядки індексу ─────────────────────────────────────
git init -q --bare "$T/origin.git"
git init -q -b main "$T/repo"
cd "$T/repo" || exit 1
git remote add origin "$T/origin.git"
# Стара адреса вже в історії й на віддаленому — як рядок журналу 2026-10-01.
printf 'старий рядок: 198.51.100.9\nдругий рядок\n' >journal.md
git add journal.md && git commit -q -m "init" && git push -q origin main

printf 'feat: новий рядок\n' >"$T/msg-clean"
printf 'fix: сервер 203.0.113.77\n' >"$T/msg-leak"
head0="$(git rev-parse HEAD)"

git checkout -q -b c1 main
printf 'новий чистий рядок\n' >>journal.md && git add journal.md
run commit "$T/msg-clean"
if [[ $rc == 0 && "$(git rev-parse HEAD)" != "$head0" ]]; then
  ok "чистий доданий рядок у файлі зі старою адресою — коміт є"
else bad "чистий доданий рядок — rc=$rc: $out"; fi

git checkout -q -b c2 main
printf 'новий рядок 203.0.113.77\n' >>journal.md && git add journal.md
run commit "$T/msg-clean"
if [[ $rc == 1 && "$(git rev-parse HEAD)" == "$head0" ]]; then ok "адреса в доданому рядку — exit 1, коміту немає"; else bad "адреса в доданому рядку — rc=$rc: $out"; fi
git reset -q --hard main

git checkout -q -b c3 main
printf 'ще рядок\n' >>journal.md && git add journal.md
run commit "$T/msg-leak"
if [[ $rc == 1 && "$(git rev-parse HEAD)" == "$head0" ]]; then ok "адреса в повідомленні коміту — exit 1, коміту немає"; else bad "адреса в повідомленні — rc=$rc: $out"; fi
git reset -q --hard main

git checkout -q -b c4 main
printf 'другий рядок\n' >journal.md && git add journal.md
run commit "$T/msg-clean"
if [[ $rc == 0 && "$(git rev-parse HEAD)" != "$head0" ]]; then ok "видалення рядка з адресою — не блок"; else bad "видалення рядка з адресою — rc=$rc: $out"; fi

git checkout -q -b c5 main
printf 'новий файл\n' >a.md
printf 'другий файл: 203.0.113.77\n' >b.md
git add a.md b.md
run commit "$T/msg-clean"
if [[ $rc == 1 && "$(git rev-parse HEAD)" == "$head0" ]]; then ok "адреса в другому з двох нових файлів — exit 1"; else bad "адреса в другому файлі — rc=$rc: $out"; fi
git reset -q --hard main

# ─── 3. push: усе, чого ще немає на віддалених гілках ─────────────────────────
remote_has() { git --git-dir="$T/origin.git" rev-parse -q --verify "refs/heads/$1" >/dev/null; }

git checkout -q -b p1 main
printf 'адреса 203.0.113.77\n' >>journal.md && git commit -qam "перший"
printf 'чисто\n' >>journal.md && git commit -qam "другий"
run push
if [[ $rc == 1 ]] && ! remote_has p1; then ok "адреса в ранішому з двох неопублікованих комітів — exit 1, push немає"; else bad "push з адресою в першому коміті — rc=$rc: $out"; fi

git checkout -q -b p2 main
printf 'чисто\n' >>journal.md && git commit -q -am "сервер 203.0.113.77"
printf 'чисто 2\n' >>journal.md && git commit -qam "другий"
run push
if [[ $rc == 1 ]] && ! remote_has p2; then ok "адреса в повідомленні неопублікованого коміту — exit 1, push немає"; else bad "push з адресою в повідомленні — rc=$rc: $out"; fi

git checkout -q -b p3 main
printf 'чисто\n' >>journal.md && git commit -qam "чистий"
run push
if [[ $rc == 0 ]] && remote_has p3 && [[ "$(git --git-dir="$T/origin.git" rev-parse p3)" == "$(git rev-parse HEAD)" ]]; then
  ok "чисті коміти поверх опублікованої адреси — push є"
else bad "чистий push — rc=$rc: $out"; fi

# Другий remote: коміт, що вже лежить на backup, на origin ще не публічний.
git init -q --bare "$T/backup.git"
git remote add backup "$T/backup.git"
backup_has() { git --git-dir="$T/backup.git" rev-parse -q --verify "refs/heads/$1" >/dev/null; }
git checkout -q -b p4 main
printf 'адреса 203.0.113.77\n' >>journal.md && git commit -qam "на backup"
git push -q backup p4
run push origin
if [[ $rc == 1 ]] && ! remote_has p4; then ok "коміт з адресою, що є лише на іншому remote — exit 1, push в origin немає"; else bad "коміт лише на backup — rc=$rc: $out"; fi

git checkout -q -b p5 main
printf 'чисто p5\n' >>journal.md && git commit -qam "p5"
run push backup
if [[ $rc == 0 ]] && backup_has p5 && ! remote_has p5; then ok "push backup — іде в названий remote, не в origin"; else bad "push backup — rc=$rc: $out"; fi

run push немає
if [[ $rc == 2 ]]; then ok "push у неіснуючий remote — exit 2"; else bad "push немає — rc=$rc: $out"; fi
cd "$HERE" || exit 1

# ─── 4. Мутації: кожне правило тримається тестом ──────────────────────────────
if [[ -z "${SAFE_PUBLISH_UNDER_TEST:-}" && $fail == 0 ]]; then
  src="$(<"$SCRIPT")"
  # mutate <назва> <було> <стало> [<було2> <стало2>] — кожне «було» стоїть у скрипті рівно раз
  mutate() {
    local name="$1" d="$T/mut/$((++n))" m s="$src" from to rest
    shift
    while [[ $# -ge 2 ]]; do
      from="$1" to="$2"
      shift 2
      rest="${s#*"$from"}"
      if [[ "$rest" == "$s" || "$rest" == *"$from"* ]]; then
        bad "мутант «$name»: текст не знайдено рівно один раз — мутація застаріла"
        return
      fi
      s="${s/"$from"/"$to"}"
    done
    mkdir -p "$d" && m="$d/safe-publish.sh"
    printf '%s\n' "$s" >"$m"
    cp "$HERE/check-leak.sh" "$d/"
    if ! bash -n "$m" 2>/dev/null; then
      bad "мутант «$name» нежиттєздатний (синтаксис)"
      return
    fi
    if SAFE_PUBLISH_UNDER_TEST="$m" bash "$HERE/$(basename "$0")" >"$d/out" 2>&1; then
      bad "мутант ВИЖИВ: $name"
    else
      ok "мутанта вбито: $name"
    fi
  }
  n=0
  mutate "код виходу замасковано: | tail -1 без pipefail (вада 2026-10-01)" \
    'set -uo pipefail' 'set -u' \
    '  bash "$CHECK" "$@"
  local rc=$?' '  bash "$CHECK" "$@" | tail -1
  local rc=$?'
  mutate "код виходу замасковано: || true" \
    '  bash "$CHECK" "$@"
  local rc=$?' '  bash "$CHECK" "$@" || true
  local rc=$?'
  mutate "публікація при ненульовому check-leak" '    exit "$rc"' '    :'
  mutate "блокує лише exit 1, а «не перевірено» (3) публікується" 'if [[ $rc != 0 ]]; then' 'if [[ $rc == 1 ]]; then'
  mutate "коміт: перевіряється весь файл, а не додані рядки" \
    'staged_added >"$T/added"' 'git diff --cached --name-only -z | xargs -0 cat >"$T/added"'
  mutate "коміт: перевіряються й видалені рядки" "h && /^\\+/{print" "h && /^[-+]/{print"
  mutate "коміт: лише перший файл diff" "/^diff --git /{h=0; next}" "/^diff --git /{if (seen++) exit; h=0; next}"
  mutate "коміт: повідомлення не перевіряється" 'check "$msg" "$T/added"' 'check "$T/added"'
  mutate "gh: заголовок і аргументи не перевіряються" 'check "$body" "$T/args"' 'check "$body"'
  mutate "gh: --body повз перевірений файл" '-b | -b?* | --body | --body=* | ' ''
  mutate "gh: будь-яка підкоманда" \
    '"pr create" | "pr edit" | "pr comment" | "issue create" | "issue comment") ;;' '*) ;;'
  mutate "gh: код помилки gh замасковано" '    gh "$@" --body-file "$body"
    exit $?' '    gh "$@" --body-file "$body"
    exit 0'
  mutate "push: лише останній коміт" 'revs="$(git rev-list HEAD --not --remotes="$remote")"' 'revs="$(git rev-list -1 HEAD)"'
  mutate "push: уся історія, а не лише неопубліковане" 'revs="$(git rev-list HEAD --not --remotes="$remote")"' 'revs="$(git rev-list HEAD)"'
  mutate "push: виключено коміти будь-якого remote, а не цільового" \
    'revs="$(git rev-list HEAD --not --remotes="$remote")"' 'revs="$(git rev-list HEAD --not --remotes)"' \
    'git rev-list HEAD --not --remotes="$remote" --format=%B' 'git rev-list HEAD --not --remotes --format=%B'
  mutate "push: завжди origin" 'remote="${1:-origin}"' 'remote="origin"'
  mutate "gh: create без заголовка" '[[ -n "$has_title" ]] ||' 'true ||'
  mutate "push: повідомлення не перевіряються" 'check "$T/messages" "$T/added"' 'check "$T/added"'
fi

if [[ $fail == 1 ]]; then
  echo "FAIL"
  exit 1
fi
echo "Усі тести пройдено."
