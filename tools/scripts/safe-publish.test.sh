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

for flag in --body "--body=x" -bx --body-file -F --fill --editor --web --template \
  --editor=true --web=true --fill=true -de -dw -df; do
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

# «-» — це stdin для gh --body-file і git commit -F, тобто текст повз перевірку.
# Чистий файл з іменем «-» поруч: check-leak перевірив би його, а gh читав би stdin.
mkdir -p "$T/dash" && printf 'чисто\n' >"$T/dash/-"
cd "$T/dash" || exit 1
run gh - pr comment 12 </dev/null
cd "$HERE" || exit 1
if [[ $rc == 2 ]] && ! gh_called; then ok "файл тексту «-» (stdin) — відхилено"; else bad "файл «-» — rc=$rc: $out"; fi

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

# Старий рядок без кінцевого \n: дописування показує його в diff як «-» і «+».
git checkout -q -b c6 main
printf 'без кінця: 198.51.100.9' >tail.md && git add tail.md && git commit -qm "tail" && git push -q origin c6
printf '\nновий рядок\n' >>tail.md && git add tail.md
h6="$(git rev-parse HEAD)"
run commit "$T/msg-clean"
if [[ $rc == 0 && "$(git rev-parse HEAD)" != "$h6" ]]; then ok "дописано після старого рядка без \\n — коміт є"; else bad "рядок без \\n — rc=$rc: $out"; fi
git checkout -q main

git checkout -q -b c7 main
printf 'чисто\n' >./- && printf 'c7\n' >>journal.md && git add journal.md
run commit - </dev/null
if [[ $rc == 2 && "$(git rev-parse HEAD)" == "$head0" ]]; then ok "commit «-» (stdin) — відхилено"; else bad "commit «-» — rc=$rc: $out"; fi
rm -f ./- && git reset -q --hard main

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

git checkout -q -b "p6-203.0.113.77" main
printf 'чисто p6\n' >>journal.md && git commit -qam "p6"
run push
if [[ $rc == 1 ]] && ! remote_has "p6-203.0.113.77"; then ok "адреса в назві гілки — exit 1, push немає"; else bad "адреса в назві гілки — rc=$rc: $out"; fi

# Merge origin/main у гілку: рядки main уже публічні — не блок; «злий» merge з новою
# адресою — блок.
git checkout -q main
printf 'стара в main: 198.51.100.9\n' >main2.md && git add main2.md && git commit -qm "main2"
git push -q origin main
git checkout -q -b p7 main~1
printf 'чисто p7\n' >p7.md && git add p7.md && git commit -qm "p7"
git merge -q --no-edit main
run push
if [[ $rc == 0 ]] && remote_has p7; then ok "merge origin/main зі старою адресою — push є"; else bad "merge origin/main — rc=$rc: $out"; fi
git checkout -q -b p8 p7~1
git merge -q --no-commit main >/dev/null 2>&1
printf 'злий merge 203.0.113.77\n' >>p7.md && git add p7.md && git commit -qm "merge"
run push
if [[ $rc == 1 ]] && ! remote_has p8; then ok "нова адреса в самому merge-коміті — exit 1"; else bad "злий merge — rc=$rc: $out"; fi

# Злиття, що лише перевирівнює рядок з адресою, який уже є в main (зупинка #178, #222):
# commit і push — 0. Злиття, що додає НОВИЙ рядок з адресою, — блок.
git checkout -q main
printf '|a|198.51.100.9|\n|x|y|\n' >table.md && git add table.md && git commit -qm "table" && git push -q origin main
git checkout -q -b m1 main
printf '|b|чисто|\n' >>table.md && git commit -qam "m1 рядок"
git checkout -q main
printf '| a | 198.51.100.9 |\n| x | y      |\n' >table.md && git commit -qam "prettier" && git push -q origin main
git checkout -q m1
git merge -q --no-commit --no-ff main >/dev/null 2>&1
printf '| a | 198.51.100.9 |\n| x | y      |\n| b | чисто  |\n' >table.md && git add table.md
hm="$(git rev-parse HEAD)"
run commit "$T/msg-clean"
if [[ $rc == 0 && "$(git rev-parse HEAD~1)" == "$hm" && "$(git rev-parse HEAD^2)" == "$(git rev-parse main)" ]]; then
  ok "злиття: рядок з адресою з main лише перевирівняно — коміт злиття є"
else bad "злиття з перевирівняним рядком main — rc=$rc: $out"; fi
run push
if [[ $rc == 0 ]] && remote_has m1; then ok "злиття: рядок з адресою з main лише перевирівняно — push є"; else bad "push злиття з перевирівняним рядком — rc=$rc: $out"; fi
git checkout -q -b m2 m1~1
git merge -q --no-commit --no-ff main >/dev/null 2>&1
printf '| a | 198.51.100.9 |\n| x | y      |\n| b | чисто  |\n| c | 203.0.113.77 |\n' >table.md && git add table.md
hm="$(git rev-parse HEAD)"
run commit "$T/msg-clean"
if [[ $rc == 1 && "$(git rev-parse HEAD)" == "$hm" ]]; then ok "злиття, що додає новий рядок з адресою, — exit 1, коміту немає"; else bad "злиття з новою адресою — rc=$rc: $out"; fi
git merge --abort

# Злиття, де рядок з адресою — останній без \n в обох батьках, а в результаті з \n:
# combined diff дає `--` і `++`, рядок не новий — 0 (контрприклад Sonnet 5.5, #225).
git checkout -q main
printf 'a\nстара 198.51.100.9' >nl.md && git add nl.md && git commit -qm "nl" && git push -q origin main
git checkout -q -b n1 main
printf 'a1\nстара 198.51.100.9' >nl.md && git commit -qam "n1"
git checkout -q -b n2 main
printf 'a2\nстара 198.51.100.9' >nl.md && git commit -qam "n2"
git checkout -q n1
git merge -q --no-commit --no-ff n2 >/dev/null 2>&1
printf 'a3\nстара 198.51.100.9\nнове\n' >nl.md && git add nl.md
hn="$(git rev-parse HEAD)"
run commit "$T/msg-clean"
if [[ $rc == 0 && "$(git rev-parse HEAD~1)" == "$hn" ]]; then ok "злиття: рядок без \\n з обох батьків, у результаті з \\n — коміт є"; else bad "злиття, рядок без \\n — rc=$rc: $out"; fi

# Злиття, що додає новий файл з адресою (Flash, #225) — блок; новий чистий файл — 0.
git checkout -q -b f1 n1~1
git merge -q --no-commit --no-ff n2 >/dev/null 2>&1
printf 'a3\nстара 198.51.100.9\n' >nl.md && printf 'новий файл 203.0.113.77\n' >fresh.md && git add nl.md fresh.md
hf="$(git rev-parse HEAD)"
run commit "$T/msg-clean"
if [[ $rc == 1 && "$(git rev-parse HEAD)" == "$hf" ]]; then ok "злиття, що додає новий файл з адресою, — exit 1, коміту немає"; else bad "злиття з новим файлом з адресою — rc=$rc: $out"; fi
printf 'новий чистий файл\n' >fresh.md && git add fresh.md
run commit "$T/msg-clean"
if [[ $rc == 0 && "$(git rev-parse HEAD~1)" == "$hf" ]]; then ok "злиття, що додає новий чистий файл, — коміт є"; else bad "злиття з новим чистим файлом — rc=$rc: $out"; fi

# Нерозв'язаний конфлікт злиття: write-tree відмовляє — exit 2, коміту немає (Flash, #225).
git checkout -q -b k1 main
printf 'k1\n' >conflict.md && git add conflict.md && git commit -qm "k1"
git checkout -q -b k2 main
printf 'k2\n' >conflict.md && git add conflict.md && git commit -qm "k2"
git merge -q --no-edit k1 >/dev/null 2>&1
hk="$(git rev-parse HEAD)"
if [[ -n "$(git ls-files -u)" ]]; then
  run commit "$T/msg-clean"
  if [[ $rc == 2 && "$(git rev-parse HEAD)" == "$hk" && "$out" == *"write-tree"* ]]; then
    ok "злиття з нерозв'язаним конфліктом — exit 2, коміту немає"
  else bad "нерозв'язаний конфлікт — rc=$rc: $out"; fi
else bad "нерозв'язаний конфлікт — сценарій не дав конфлікту"; fi
git merge --abort

# push --to (#222): явна цільова гілка для detached HEAD і локальної гілки з іншим ім'ям.
addr_known="$(printf '%s.%s.%s.%s' 203 0 113 77)"
git checkout -q main
git checkout -q --detach
printf 'чисто t1\n' >t1.md && git add t1.md && git commit -qm "t1"
run push --to x
if [[ $rc == 0 ]] && remote_has x && [[ "$(git --git-dir="$T/origin.git" rev-parse x)" == "$(git rev-parse HEAD)" ]] &&
  ! git rev-parse -q --verify refs/heads/x >/dev/null; then
  ok "detached + push --to x — push у x, локальної гілки x немає"
else bad "detached --to x — rc=$rc: $out"; fi
printf 'чисто t1b\n' >>t1.md && git commit -qam "t1b"
run push
if [[ $rc == 2 && "$out" == *"--to"* ]]; then ok "detached без --to — відмова з підказкою"; else bad "detached без --to — rc=$rc: $out"; fi
git checkout -q -b y
run push --to z
if [[ $rc == 0 ]] && remote_has z && ! remote_has y && [[ -z "$(git config branch.y.remote)" ]]; then
  ok "гілка y + push --to z — push у z, не в y, без -u"
else bad "гілка y --to z — rc=$rc: $out"; fi
printf 'чисто t2\n' >>t1.md && git commit -qam "t2"
# backup ще не має історії main (у ній старі адреси) — кладемо її туди повз обгортку,
# як уже публічну.
git push -q backup main
run push --to w backup
if [[ $rc == 0 ]] && backup_has w && ! remote_has w; then ok "push --to w backup — у названий remote"; else bad "--to w backup — rc=$rc: $out"; fi
mbefore="$(git --git-dir="$T/origin.git" rev-parse main)"
run push --to main
if [[ $rc == 2 && "$(git --git-dir="$T/origin.git" rev-parse main)" == "$mbefore" ]]; then ok "push --to main — відмова, main на remote не змінено"; else bad "--to main — rc=$rc: $out"; fi
for name in "" "-f" "refs/heads/main" "a..b" "x:y" "a b" "@" "HEAD" "x.lock" "x@{1}"; do
  run push --to "$name"
  if [[ $rc == 2 ]]; then ok "push --to «$name» — відмова"; else bad "--to «$name» — rc=$rc: $out"; fi
done
run push --to
if [[ $rc == 2 ]]; then ok "push --to без імені — відмова"; else bad "--to без імені — rc=$rc: $out"; fi
run push --to "v-$addr_known"
if [[ $rc == 1 ]] && ! remote_has "v-$addr_known"; then ok "адреса в імені цільової гілки — exit 1, push немає"; else bad "адреса в --to — rc=$rc: $out"; fi
git checkout -q --detach
printf 'адреса %s\n' "$addr_known" >>t1.md && git commit -qam "t3"
run push --to x3
if [[ $rc == 1 ]] && ! remote_has x3; then ok "detached + --to, адреса в неопублікованому коміті — exit 1, push немає"; else bad "--to з адресою в коміті — rc=$rc: $out"; fi
git checkout -q main

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
  mutate "коміт: перевіряються й видалені рядки" 'pre ~ /-/ {gone[txt]++; next}' 'pre ~ /-/ {print txt; next}'
  mutate "злиття: рядок без \\n з батьків — новий (контрприклад #225)" 'pre ~ /-/ {gone[txt]++; next}' 'pre ~ /-/ {if (np==1) gone[txt]++; next}'
  mutate "коміт: дослівно перенесений рядок вважається новим" 'if (gone[txt] > 0) {gone[txt]--; next} ' ''
  mutate "merge: перший батько замість combined diff" '--format= --cc "$c" | added_lines || return 1' '--format= --diff-merges=first-parent "$c" | added_lines || return 1'
  mutate "merge: combined diff не читається" 'pre ~ /^\++$/ {' 'np == 1 && pre ~ /^\++$/ {'
  mutate "merge: рядок, що є в іншому батьку, — новий" 'pre ~ /^\++$/ {' 'pre ~ /\+/ {'
  mutate "commit злиття: diff проти першого батька (вада #178)" 'if [[ -f "$mh" ]]; then' 'if false; then'
  mutate "commit злиття: не перевіряється" '--cc "$c" | added_lines
    return' '--cc "$c" >/dev/null
    return'
  mutate "commit злиття: батьки з MERGE_HEAD не беруться" '[[ -n "$c" ]] && parents+=(-p "$c")' 'true'
  mutate "push: назва гілки не перевіряється" 'printf '"'"'%s\n'"'"' "${to:-$cur}" >>"$T/messages"' 'true'
  mutate "gh: кластер коротких прапорців" '        -[!-]?*)' '        -[!-]?*-NEVER)'
  mutate "gh: --editor=… повз перелік" '-e | --editor* |' '-e | --editor |'
  mutate "stdin замість файла" '[[ "$body" != -* ]] ||' 'true ||' '[[ "$msg" != -* ]] ||' 'true ||'
  mutate "коміт: лише перший файл diff" '/^diff (--git|--cc|--combined) /{h=0; next}' '/^diff (--git|--cc|--combined) /{if (seen++) exit; h=0; next}'
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
  mutate "push: --to ігнорується" 'git push "$remote" "HEAD:refs/heads/$to"' 'git push -u "$remote" HEAD'
  mutate "push: --to main дозволено" '[[ "$to" != main ]] ||' 'true ||'
  mutate "push: --to з -u" 'git push "$remote" "HEAD:refs/heads/$to"' 'git push -u "$remote" "HEAD:refs/heads/$to"'
  mutate "push: ім'я --to без check-ref-format" 'git check-ref-format "refs/heads/$to" ||' 'true ||'
  mutate "push: назва цільової гілки не перевіряється" 'printf '"'"'%s\n'"'"' "${to:-$cur}" >>"$T/messages"' 'printf '"'"'%s\n'"'"' "$cur" >>"$T/messages"'
  mutate "push: detached без --to не відхиляється" '[[ -n "$to" || "$cur" != HEAD ]] ||' 'true ||'
  mutate "gh: create без заголовка" '[[ -n "$has_title" ]] ||' 'true ||'
  mutate "push: повідомлення не перевіряються" 'check "$T/messages" "$T/added"' 'check "$T/added"'
fi

if [[ $fail == 1 ]]; then
  echo "FAIL"
  exit 1
fi
echo "Усі тести пройдено."
