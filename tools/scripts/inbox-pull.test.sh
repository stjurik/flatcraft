#!/usr/bin/env bash
# inbox-pull.test.sh — вхідні yurii: забирає лише нерозібране, пише лише в ігноровану
# теку flatcraft, у hart-inbox — лише мітки й коментар. gh і curl — заглушки: справжній
# hart-inbox і мережу тест не чіпає.
# Запуск: tools/scripts/inbox-pull.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SCRIPT="$HERE/inbox-pull.sh"
fail=0
ok() { echo "✓ $1"; }
bad() {
  echo "✗ $1"
  fail=1
}
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/data"

# ─── Заглушки ────────────────────────────────────────────────────────────────
# gh: кожен виклик — рядок у gh.log; відповідь — файл з data/ за аргументами;
# `-q <фільтр>` виконується справжнім jq, як у gh.
cat >"$T/bin/gh" <<'STUB'
#!/usr/bin/env bash
D="$(dirname "$0")/../data"
echo "$*" >>"$D/../gh.log"
q=""; args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do [[ "${args[i]}" == "-q" ]] && q="${args[i+1]}"; done
emit() { if [[ -n "$q" ]]; then jq -r "$q" "$1"; else cat "$1"; fi; }
case "$*" in
  "issue list -R stjurik/hart-inbox"*) emit "$D/inbox-list.json" ;;
  "issue list -R stjurik/flatcraft"*) emit "$D/backlog.json" ;;
  "api repos/stjurik/hart-inbox -q .owner.login") echo stjurik ;;
  "api repos/stjurik/hart-inbox/issues/"*"/events"*)
    n="${2#repos/stjurik/hart-inbox/issues/}"; n="${n%/events}"; emit "$D/events-$n.json" ;;
  "api repos/stjurik/hart-inbox/issues/"*"/comments"*)
    n="${2#repos/stjurik/hart-inbox/issues/}"; n="${n%/comments}"; emit "$D/comments-$n.json" ;;
  "api repos/stjurik/hart-inbox/issues/"*)
    n="${2#repos/stjurik/hart-inbox/issues/}"; emit "$D/issue-$n.json" ;;
  "issue view "*) emit "$D/labels-$3.json" ;;
  "issue comment "*)
    for ((i = 0; i < ${#args[@]}; i++)); do [[ "${args[i]}" == "--body-file" ]] && cp "${args[i+1]}" "$D/../comment-$3.txt"; done; true ;;
  "issue edit "*) ;;
  *) echo "gh-заглушка: невідомий виклик $*" >&2; exit 9 ;;
esac
STUB
# curl: «jpg» в адресі — заголовок JPEG; «png» — справжній PNG 1×1; інакше — HTML
# (тип має бути відкинуто).
cat >"$T/bin/curl" <<'STUB'
#!/usr/bin/env bash
D="$(dirname "$0")/../data"
url="${*: -1}"; out=""; args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do [[ "${args[i]}" == "-o" ]] && out="${args[i+1]}"; done
echo "$url" >>"$D/../curl.log"
if [[ "$url" == *jpg* ]]; then
  printf '\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00' >"$out"
elif [[ "$url" == *png* ]]; then
  base64 -d >"$out" <<<'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='
else
  echo '<html>login</html>' >"$out"
fi
STUB
chmod +x "$T/bin/gh" "$T/bin/curl"

D="$T/data"
MARK='<!-- inbox-bot -->'
cat >"$D/inbox-list.json" <<'EOF'
[
  {"number": 1, "labels": [{"name": "зауваження"}, {"name": "нове"}]},
  {"number": 2, "labels": [{"name": "оброблено"}, {"name": "в беклозі"}]},
  {"number": 3, "labels": [{"name": "ідея"}, {"name": "оброблено"}, {"name": "потрібна відповідь"}]},
  {"number": 4, "labels": [{"name": "оброблено"}, {"name": "потрібна відповідь"}]},
  {"number": 5, "labels": [{"name": "оброблено"}, {"name": "потрібна відповідь"}]},
  {"number": 6, "labels": [{"name": "оброблено"}, {"name": "потрібна відповідь"}]},
  {"number": 7, "labels": [{"name": "оброблено"}, {"name": "потрібна відповідь"}]},
  {"number": 8, "labels": [{"name": "оброблено"}, {"name": "потрібна відповідь"}]},
  {"number": 9, "labels": [{"name": "оброблено"}, {"name": "потрібна відповідь"}]}
]
EOF
echo '[{"number": 5, "title": "Кнопка експорту зникає на телефоні"}]' >"$D/backlog.json"
# Підписані адреси — як у справжній відповіді API: `&amp;` і jwt у запиті.
IMG1='https://private-user-images.githubusercontent.com/1/a.png?jwt=SECRETJWT&amp;x=1'
IMG2='https://private-user-images.githubusercontent.com/1/b.bin?jwt=SECRETJWT'
IMG3='https://evil.example/c.png'
IMG4='https://private-user-images.githubusercontent.com/1/d.jpg?jwt=SECRETJWT'
# Тег, розбитий на рядки, і `data-canonical-src` з чужим хостом після справжнього src.
H="<p>Ось</p><img alt=\"s\" src=\"$IMG1\"><img src=\"$IMG2\"><img src=\"$IMG3\">"
H+='<img src="'"$IMG4"$'"\n  data-canonical-src="https://evil.example/x.png">'
jq -n --arg h "$H" '{
  number: 1, title: "Зауваження: кнопка", html_url: "https://github.com/stjurik/hart-inbox/issues/1",
  created_at: "2026-10-04T10:00:00Z", labels: [{name: "зауваження"}, {name: "нове"}],
  body: "### Сторінка\n\nhttps://staging.hart.crimea.ua/studio\n\n### Що не так / що хочу\n\nКнопка ховається",
  body_html: $h}' >"$D/issue-1.json"
jq -n --arg m "$MARK" '[{created_at: "t1", body: ("Який браузер?\n\n" + $m), body_html: ""}, {created_at: "t2", body: "Chrome", body_html: ""}]' >"$D/comments-1.json"
# «Потрібна відповідь»: мітку поставлено о 10:00 (події), далі — коментарі.
# c <автор> <тип> <час> <текст> — один коментар.
c() { jq -n --arg u "$1" --arg ty "$2" --arg t "2026-10-04T$3:00Z" --arg b "$4" '{user: {login: $u, type: $ty}, created_at: $t, body: $b, body_html: ""}'; }
for n in 3 4 5 6 7 8 9; do
  echo '[{"event": "labeled", "label": {"name": "потрібна відповідь"}, "created_at": "2026-10-04T10:00:00Z"}]' >"$D/events-$n.json"
done
echo '[{"event": "labeled", "label": {"name": "оброблено"}, "created_at": "2026-10-04T10:00:00Z"}]' >"$D/events-9.json"
jq -s . <(c stjurik User 09:59 "Яка товщина? $MARK") <(c stjurik User 10:05 "2 мм") >"$D/comments-3.json"
jq -s . <(c someone User 10:05 "я теж хочу") >"$D/comments-4.json"
jq -s . <(c stjurik User 09:30 "уточнення до мітки") >"$D/comments-5.json"
jq -s . <(c 'github-actions[bot]' Bot 10:05 "автоматичний коментар") >"$D/comments-6.json"
jq -s . <(c stjurik User 10:05 "Ще питання $MARK") >"$D/comments-7.json"
jq -s . <(c stjurik User 10:05 "2 мм") <(c stjurik User 10:10 "Розібрано, знову питання $MARK") >"$D/comments-8.json"
jq -s . <(c stjurik User 10:05 "2 мм") >"$D/comments-9.json"
jq -n '{number: 3, title: "Ідея: полиця", html_url: "u", created_at: "c", labels: [], body: "Полиця", body_html: ""}' >"$D/issue-3.json"
echo '{"labels": [{"name": "зауваження"}, {"name": "нове"}, {"name": "потрібна відповідь"}]}' >"$D/labels-1.json"

# make_repo <тека> [без-ignore|лише-md|без-маркера] — мінімальне робоче дерево flatcraft.
make_repo() {
  local r="$1"
  mkdir -p "$r/docs/promts/inputs" "$r/tools/inbox"
  git -C "$r" init -q
  [[ "${2:-}" == без-маркера ]] || { touch "$r/docs/18_NEW_PART_SPEC.md" "$r/tools/inbox/labels.tsv"; }
  case "${2:-}" in
    без-ignore) ;;
    лише-md) echo '*.md' >"$r/.gitignore" ;;
    *) echo 'docs/promts/inputs/_inbox/' >"$r/.gitignore" ;;
  esac
}
run() { (cd "$1" && shift && PATH="$T/bin:$PATH" bash "$SCRIPT" "$@") >"$T/out.txt" 2>&1; }

# ─── 1. pull: лише нерозібране ───────────────────────────────────────────────
R="$T/repo"
make_repo "$R"
run "$R"
rc=$?
IN="$R/docs/promts/inputs/_inbox"
check "pull — вихід 0" "[[ $rc == 0 ]] || { cat '$T/out.txt'; false; }"
check "#1 (нове) забрано" "[[ -f '$IN/1/issue.md' ]]"
check "#2 (оброблено) — ні" "[[ ! -e '$IN/2' ]]"
check "#3 потрібна відповідь + коментар yurii після мітки — повертається" "[[ -f '$IN/3/issue.md' ]]"
check "#4 коментар іншого автора — не повертає" "[[ ! -e '$IN/4' ]]"
check "#5 коментар yurii до мітки — не повертає" "[[ ! -e '$IN/5' ]]"
check "#6 коментар бота — не повертає" "[[ ! -e '$IN/6' ]]"
check "#7 лише коментар оркестратора (той самий обліковий запис) — не повертає" "[[ ! -e '$IN/7' ]]"
check "#8 відповідь yurii вже розібрана (оркестратор коментував пізніше) — не повертає" "[[ ! -e '$IN/8' ]]"
check "#9 події мітки «потрібна відповідь» немає — не повертає" "[[ ! -e '$IN/9' ]]"
check "issue.md: заголовок і текст" "grep -q 'Зауваження: кнопка' '$IN/1/issue.md' && grep -q 'Кнопка ховається' '$IN/1/issue.md'"
check "коментарі розрізнено, позначку прибрано" \
  "grep -q 't1 — оркестратор' '$IN/1/issue.md' && grep -q 't2 — yurii' '$IN/1/issue.md' && ! grep -qF '$MARK' '$IN/1/issue.md'"
check "зображення PNG збережено" "[[ \$(file --mime-type -b '$IN/1/img-1.png') == image/png ]]"
check "не-зображення відкинуто й видалено" "grep -q 'img-2: відкинуто' '$IN/1/images.txt' && [[ ! -e '$IN/1/img-2' ]]"
check "JPEG збережено з тега на кількох рядках, src, а не data-canonical-src" \
  "[[ \$(file --mime-type -b '$IN/1/img-3.jpg') == image/jpeg ]]"
check "чужий хост не завантажується" "grep -q 'пропущено (не хост GitHub)' '$IN/1/images.txt' && ! grep -q evil '$T/curl.log'"
check "підписаний запит (jwt) не записано" "! grep -rq SECRETJWT '$IN'"
check "&amp; розкодовано перед завантаженням" "grep -q 'jwt=SECRETJWT&x=1' '$T/curl.log'"
check "назви беклогу flatcraft поруч" "grep -q '#5 Кнопка експорту' '$IN/1/backlog-titles.txt'"
check "pull у hart-inbox нічого не пише" "! grep -qE '^issue (comment|edit|close|delete)|-X|--method' '$T/gh.log'"
check "у flatcraft — лише читання списку issues" \
  "! grep 'stjurik/flatcraft' '$T/gh.log' | grep -qv '^issue list -R stjurik/flatcraft --state open'"
check "_inbox ігнорується — git status чистий від нього" "! git -C '$R' status --porcelain | grep -q _inbox"

# ─── 2. Відмови писати деінде ────────────────────────────────────────────────
make_repo "$T/r2" без-ignore
run "$T/r2"
rc=$?
check "без рядка в .gitignore — відмова (2), нічого не створено" \
  "[[ $rc == 2 ]] && grep -q 'не в .gitignore' '$T/out.txt' && [[ ! -e '$T/r2/docs/promts/inputs/_inbox' ]]"
make_repo "$T/r5" лише-md
run "$T/r5"
rc=$?
check "правило *.md без теки _inbox — відмова (2): зображення не ігнорувались би" \
  "[[ $rc == 2 ]] && grep -q 'не в .gitignore' '$T/out.txt'"
git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -q -m init
git -C "$R" worktree add -q "$T/wt" 2>/dev/null
run "$T/wt"
rc=$?
check "git worktree — відмова (2): agy пише лише в головне дерево" \
  "[[ $rc == 2 ]] && grep -q 'worktree' '$T/out.txt' && [[ ! -e '$T/wt/docs/promts/inputs/_inbox' ]]"
make_repo "$T/r3" без-маркера
run "$T/r3"
rc=$?
check "не flatcraft — відмова (2)" "[[ $rc == 2 ]] && grep -q 'не flatcraft' '$T/out.txt'"
make_repo "$T/r4"
mkdir -p "$T/elsewhere"
ln -s "$T/elsewhere" "$T/r4/docs/promts/inputs/_inbox"
run "$T/r4"
rc=$?
check "_inbox — символьне посилання — відмова (2)" "[[ $rc == 2 ]] && grep -q 'символьне посилання' '$T/out.txt' && [[ -z \$(ls -A '$T/elsewhere') ]]"
mkdir -p "$T/plain"
run "$T/plain"
rc=$?
check "поза git — відмова (2)" "[[ $rc == 2 ]]"

# ─── 3. mark: лише мітки й коментар ──────────────────────────────────────────
: >"$T/gh.log"
echo "Задача в беклозі: #200" >"$T/c.md"
run "$R" mark 1 "в беклозі" "$T/c.md"
rc=$?
check "mark — вихід 0" "[[ $rc == 0 ]] || { cat '$T/out.txt'; false; }"
check "коментар у hart-inbox з позначкою" \
  "grep -q '^issue comment 1 -R stjurik/hart-inbox --body-file' '$T/gh.log' && grep -q 'беклозі: #200' '$T/comment-1.txt' && grep -qF '$MARK' '$T/comment-1.txt'"
check "мітки: + оброблено і підсумок, − нове і старий підсумок" \
  "grep -qx 'issue edit 1 -R stjurik/hart-inbox --add-label оброблено,в беклозі --remove-label нове,потрібна відповідь' '$T/gh.log'"
check "mark — лише comment/view/edit у hart-inbox" \
  "! grep -vE '^issue (comment|view|edit) 1 -R stjurik/hart-inbox( |$)' '$T/gh.log' | grep -q ."
: >"$T/gh.log"
run "$R" mark 1 "закрити" "$T/c.md"
rc=$?
check "невідомий підсумок — відмова (2), gh не викликано" "[[ $rc == 2 ]] && [[ ! -s '$T/gh.log' ]]"
run "$R" mark '1;x' "відхилено" "$T/c.md"
rc=$?
check "номер не число — відмова (2)" "[[ $rc == 2 ]] && [[ ! -s '$T/gh.log' ]]"
run "$R" mark 1 "відхилено" "$T/немає.md"
rc=$?
check "немає файла коментаря — відмова (2)" "[[ $rc == 2 ]] && [[ ! -s '$T/gh.log' ]]"

# ─── 4. Справжній .gitignore flatcraft ───────────────────────────────────────
check "у flatcraft _inbox ігнорується" "git -C '$ROOT' check-ignore -q docs/promts/inputs/_inbox/1/issue.md"

if ((fail)); then
  echo "inbox-pull.test: є провали"
  exit 1
fi
echo "inbox-pull.test: усе зелене"
