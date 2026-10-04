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
# curl: «png» в адресі — справжній PNG 1×1; інакше — HTML (тип має бути відкинуто).
cat >"$T/bin/curl" <<'STUB'
#!/usr/bin/env bash
D="$(dirname "$0")/../data"
url="${*: -1}"; out=""; args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do [[ "${args[i]}" == "-o" ]] && out="${args[i+1]}"; done
echo "$url" >>"$D/../curl.log"
if [[ "$url" == *png* ]]; then
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
  {"number": 4, "labels": [{"name": "оброблено"}, {"name": "потрібна відповідь"}]}
]
EOF
echo '[{"number": 5, "title": "Кнопка експорту зникає на телефоні"}]' >"$D/backlog.json"
# Підписані адреси — як у справжній відповіді API: `&amp;` і jwt у запиті.
IMG1='https://private-user-images.githubusercontent.com/1/a.png?jwt=SECRETJWT&amp;x=1'
IMG2='https://private-user-images.githubusercontent.com/1/b.bin?jwt=SECRETJWT'
IMG3='https://evil.example/c.png'
jq -n --arg h "<p>Ось</p><img alt=\"s\" src=\"$IMG1\"><img src=\"$IMG2\"><img src=\"$IMG3\">" '{
  number: 1, title: "Зауваження: кнопка", html_url: "https://github.com/stjurik/hart-inbox/issues/1",
  created_at: "2026-10-04T10:00:00Z", labels: [{name: "зауваження"}, {name: "нове"}],
  body: "### Сторінка\n\nhttps://staging.hart.crimea.ua/studio\n\n### Що не так / що хочу\n\nКнопка ховається",
  body_html: $h}' >"$D/issue-1.json"
echo '[]' >"$D/comments-1.json"
jq -n '{number: 3, title: "Ідея: полиця", html_url: "u", created_at: "c", labels: [], body: "Полиця для взуття", body_html: ""}' >"$D/issue-3.json"
jq -n --arg m "$MARK" '[{created_at: "t1", body: ("Яка товщина?\n\n" + $m), body_html: ""}, {created_at: "t2", body: "2 мм", body_html: ""}]' >"$D/comments-3.json"
jq -n --arg m "$MARK" '[{created_at: "t1", body: ("Яка ширина?\n\n" + $m), body_html: ""}]' >"$D/comments-4.json"
echo '{"labels": [{"name": "зауваження"}, {"name": "нове"}, {"name": "потрібна відповідь"}]}' >"$D/labels-1.json"

# make_repo <тека> [без-ignore|без-маркера] — мінімальне робоче дерево flatcraft.
make_repo() {
  local r="$1"
  mkdir -p "$r/docs/promts/inputs" "$r/tools/inbox"
  git -C "$r" init -q
  [[ "${2:-}" == без-маркера ]] || { touch "$r/docs/18_NEW_PART_SPEC.md" "$r/tools/inbox/labels.tsv"; }
  [[ "${2:-}" == без-ignore ]] || echo 'docs/promts/inputs/_inbox/' >"$r/.gitignore"
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
check "#3 (потрібна відповідь, останнім писав yurii) — забрано" "[[ -f '$IN/3/issue.md' ]]"
check "#4 (потрібна відповідь, відповіді yurii немає) — ні" "[[ ! -e '$IN/4' ]]"
check "issue.md: заголовок і текст" "grep -q 'Зауваження: кнопка' '$IN/1/issue.md' && grep -q 'Кнопка ховається' '$IN/1/issue.md'"
check "коментарі розрізнено, позначку прибрано" \
  "grep -q 't1 — оркестратор' '$IN/3/issue.md' && grep -q 't2 — yurii' '$IN/3/issue.md' && ! grep -qF '$MARK' '$IN/3/issue.md'"
check "зображення PNG збережено" "[[ \$(file --mime-type -b '$IN/1/img-1.png') == image/png ]]"
check "не-зображення відкинуто й видалено" "grep -q 'img-2: відкинуто' '$IN/1/images.txt' && [[ ! -e '$IN/1/img-2' ]]"
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
