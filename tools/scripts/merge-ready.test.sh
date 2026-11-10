#!/usr/bin/env bash
# merge-ready.test.sh — власний тест merge-ready.sh на синтетичному git-репозиторії
# та заглушках gh/parse-decisions.sh.
#
# Скрипт під тестом береться через MERGE_READY_SH (дефолт — поруч): оракул
# приймання підставляє сюди обгортки-мутанти, кожна ставить СВІЙ gh першим у
# PATH і запускає СПРАВЖНІЙ merge-ready.sh крізь нього — мутант псує відповідь
# gh (чи аргументи виклику), а не код скрипта. Набір нижче мусить почервоніти
# на кожному з п'яти мутантів нижче — інакше псування пройшло б непоміченим
# в оркестраторі. PARSE_DECISIONS_SH (дефолт — поруч) — щоб тест міг
# підставити свою заглушку, не залежачи від граматики parse-decisions.sh.
#
# Мережі немає: origin — локальний голий репозиторій.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MR="${MERGE_READY_SH:-$HERE/merge-ready.sh}"
fail=0
ok() { echo "✓ $1"; }
bad() {
  echo "✗ $1"
  fail=1
}

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
MARK='<!-- inbox-bot -->'
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# ─── git: M0 → main M1 (b.txt); feat S (a.txt) = SHA; U = merge(feat, main) —
#     клон зроблено ДО M1/U, тож без git fetch їх у клоні немає (справжня
#     перевірка прив'язки до голови, не лише перевірка JSON-поля).
W="$SB/src"
git init -q -b main "$W"
echo 0 >"$W/a.txt"
git -C "$W" add -A
git -C "$W" commit -q -m M0
git -C "$W" checkout -q -b feat
echo 1 >"$W/a.txt"
git -C "$W" commit -q -am S
SHA="$(git -C "$W" rev-parse HEAD)"
git init -q --bare "$SB/origin.git"
git -C "$SB/origin.git" config uploadpack.allowAnySHA1InWant true
git -C "$W" push -q "$SB/origin.git" main feat
git clone -q "$SB/origin.git" "$SB/clone"
git -C "$W" checkout -q main
echo b >"$W/b.txt"
git -C "$W" add -A
git -C "$W" commit -q -m M1
M1="$(git -C "$W" rev-parse HEAD)"
git -C "$W" checkout -q feat
git -C "$W" merge -q --no-edit main
U="$(git -C "$W" rev-parse HEAD)"
git -C "$W" push -q -f "$SB/origin.git" main feat
CLONE="$SB/clone"

# ─── gh: заглушка з фікстур у $D, кожен виклик — окремий файл у $CALLS_DIR ──
D="$SB/d"
CALLS_DIR="$SB/calls"
mkdir -p "$D" "$CALLS_DIR" "$SB/bin"
export FIXTURE_DIR="$D" CALLS_DIR
cat >"$SB/bin/gh" <<'EOS'
#!/usr/bin/env bash
n=$(ls "$CALLS_DIR" | wc -l)
printf '%s\n' "$@" >"$CALLS_DIR/$(printf %04d "$n").args"
D="$FIXTURE_DIR"
a=("$@")
if [[ "$*" =~ repos/stjurik/hart-inbox/issues/comments/([0-9]+) ]]; then
  cat "$D/comment-${BASH_REMATCH[1]}.json"
  exit 0
fi
if [[ "$*" =~ repos/stjurik/hart-inbox/issues/([0-9]+)/comments ]]; then
  cat "$D/comments-${BASH_REMATCH[1]}.json"
  exit 0
fi
if [[ "${1:-}" == pr ]]; then
  num=""
  for ((i = 2; i < ${#a[@]}; i++)); do
    [[ "${a[i - 1]}" == -R || "${a[i - 1]}" == --repo ]] && continue
    [[ "${a[i]}" =~ ^[0-9]+$ ]] && { num="${a[i]}"; break; }
  done
  case "$2" in
    view) cat "$D/pr-$num.json"; exit 0 ;;
    ready) exit 0 ;;
    merge) exit "${MR_MERGE_RC:-0}" ;;
  esac
fi
echo "stub gh: невідомий виклик $*" >&2
exit 9
EOS
chmod +x "$SB/bin/gh"

# ─── parse-decisions — своя заглушка: грепає merge:/питання, не граматику ──
cat >"$SB/pd.sh" <<'EOS'
#!/usr/bin/env bash
[ -f "$1" ] && [ -f "$2" ] || exit 2
if grep -q 'MR_TEST_QUESTION' "$1"; then
  echo '{"decisions":[],"merge":[],"accepted":[],"text":"","questions":["тестове питання"]}'
  exit 4
fi
m="$(grep -oE 'merge:( +#?[0-9]+)+' "$1" | grep -oE '[0-9]+' | jq -sc '.')"
jq -cn --argjson m "${m:-[]}" '{decisions:[],merge:$m,accepted:[],text:"",questions:[]}'
EOS
chmod +x "$SB/pd.sh"

# ─── фікстури ─────────────────────────────────────────────────────────────
ISSUE=8
PR=42
DIGEST_ID=500
CONSENT_ID=501

write_comment() { # write_comment <id> <created> <updated> <login> <issue> <тіло>
  jq -cn --argjson id "$1" --arg c "$2" --arg u "$3" --arg l "$4" --arg i "$5" --arg b "$6" \
    '{id:$id, created_at:$c, updated_at:$u, user:{login:$l}, body:$b,
      issue_url:("https://api.github.com/repos/stjurik/hart-inbox/issues/\($i)"),
      html_url:("https://github.com/stjurik/hart-inbox/issues/\($i)#issuecomment-\($id)")}' >"$D/comment-$1.json"
}
write_list() { # write_list <id...> → comments-$ISSUE.json
  local f=()
  for id in "$@"; do f+=("$D/comment-$id.json"); done
  jq -s '.' "${f[@]}" >"$D/comments-$ISSUE.json"
}
GREEN='[{"name":"a","status":"COMPLETED","conclusion":"SUCCESS"},{"context":"b","state":"SUCCESS"}]'
RED='[{"name":"a","status":"COMPLETED","conclusion":"FAILURE"}]'
write_pr() { # write_pr <head> [draft] [state] [base] [mergeState] [rollup]
  local r="${6:-$GREEN}"
  jq -cn --arg h "$1" --argjson dr "${2:-false}" --arg s "${3:-OPEN}" --arg b "${4:-main}" --arg m "${5:-CLEAN}" --argjson r "$r" \
    '{state:$s,isDraft:$dr,baseRefName:$b,headRefOid:$h,mergeStateStatus:$m,statusCheckRollup:$r}' >"$D/pr-$PR.json"
}
digest_body() { printf -- '- **#%s** — зелений на %s.\n\n%s' "$PR" "${SHA:0:7}" "$MARK"; }
baseline() {
  write_comment "$DIGEST_ID" 2026-11-05T03:00:00Z 2026-11-05T03:00:00Z stjurik "$ISSUE" "$(digest_body)"
  write_comment "$CONSENT_ID" 2026-11-05T04:00:00Z 2026-11-05T04:00:00Z stjurik "$ISSUE" "merge: $PR"
  write_list "$DIGEST_ID" "$CONSENT_ID"
  write_pr "$SHA"
}

ERRFILE="$SB/err"
calls() { cat "$CALLS_DIR"/*.args 2>/dev/null | tr '\n' ' '; }
run_mr() {
  rm -f "$CALLS_DIR"/*
  set +e
  out="$(cd "$CLONE" && PATH="$SB/bin:$PATH" PARSE_DECISIONS_SH="$SB/pd.sh" MERGE_READY_INBOX_ISSUE="$ISSUE" "$MR" "$@" 2>"$ERRFILE")"
  rc=$?
  set -e
}
std() { run_mr "$PR" "$SHA" "$CONSENT_ID" "$DIGEST_ID"; }
merged() { calls | grep -q 'pr merge'; }
expect() { # expect <очікую-rc> <опис>
  if [[ "$rc" == "$1" ]]; then
    ok "$2 (rc=$rc)"
  else
    bad "$2: rc=$rc, чекаю $1; stderr: $(head -c 300 "$ERRFILE")"
  fi
}

# ── 1. Щасливий шлях: голова = sha. Перевіряє і --match-head-commit, і
#      відсутність заборонених прапорців — це той самий виклик, що ловить
#      мутант «merge без --match-head-commit».
baseline
std
expect 0 "голова=sha — merge"
if merged; then ok "merge викликано"; else bad "merge не викликано"; fi
c="$(calls)"
if grep -q -- "--match-head-commit $SHA" <<<"$c" && grep -q -- "--squash" <<<"$c"; then
  ok "merge з --squash --match-head-commit $SHA"
else
  bad "merge без --squash чи --match-head-commit $SHA: $c"
fi
if grep -qE -- '--auto|--admin|--rebase|--delete-branch|update-branch' <<<"$c"; then
  bad "заборонений прапорець чи update-branch у виклику: $c"
else
  ok "жодного забороненого прапорця"
fi
if grep -q -- '-R stjurik/flatcraft' <<<"$c"; then ok "merge з -R stjurik/flatcraft"; else bad "merge без -R stjurik/flatcraft: $c"; fi
if [[ "$out" == "ЗЛИТО: #$PR голова $SHA згода https://github.com/stjurik/hart-inbox/issues/$ISSUE#issuecomment-$CONSENT_ID" ]]; then
  ok "stdout успіху"
else
  bad "stdout успіху: $out"
fi

# ── 2. --dry-run: без мутацій. ──────────────────────────────────────────
baseline
run_mr --dry-run "$PR" "$SHA" "$CONSENT_ID" "$DIGEST_ID"
expect 0 "--dry-run"
if merged; then bad "--dry-run викликав merge"; else ok "--dry-run без merge"; fi
if [[ "$out" == "ГОТОВО: #$PR голова $SHA згода $CONSENT_ID" ]]; then ok "stdout --dry-run"; else bad "stdout --dry-run: $out"; fi

# ── 3. Голова — merge-коміт update-branch (U) поверх sha без інших змін:
#      клон застарілий, потрібен git fetch. Перевіряє саму git-логіку. ──
baseline
write_pr "$U"
std
expect 0 "голова — update-branch (U)"
if calls | grep -q -- "--match-head-commit $U"; then ok "merge з --match-head-commit $U"; else bad "merge без --match-head-commit $U: $(calls)"; fi

# ── 4. Відредагована згода (updated_at ≠ created_at) → код 3, merge не
#      викликано. Ловить мутант «відредагована згода приймається». ──
baseline
write_comment "$CONSENT_ID" 2026-11-05T04:00:00Z 2026-11-05T04:05:00Z stjurik "$ISSUE" "merge: $PR"
write_list "$DIGEST_ID" "$CONSENT_ID"
std
expect 3 "відредагована згода"
if merged; then bad "відредагована згода — merge не мав викликатись: $(calls)"; else ok "відредагована згода — merge не викликано"; fi

# ── 5. Позначка Архітектора в нецитованому рядку згоди → код 3. Ловить
#      мутант «згода з позначкою Архітектора приймається». ──
baseline
write_comment "$CONSENT_ID" 2026-11-05T04:00:00Z 2026-11-05T04:00:00Z stjurik "$ISSUE" $'Архітектор → оркестратор\nmerge: '"$PR"
write_list "$DIGEST_ID" "$CONSENT_ID"
std
expect 3 "позначка Архітектора в згоді"

# ── 5б. Позначка бота в нецитованому рядку згоди → код 3. ──────────────
baseline
write_comment "$CONSENT_ID" 2026-11-05T04:00:00Z 2026-11-05T04:00:00Z stjurik "$ISSUE" "merge: $PR"$'\n'"$MARK"
write_list "$DIGEST_ID" "$CONSENT_ID"
std
expect 3 "позначка бота в згоді"

# ── 6. Зведення без позначки бота → код 3. ──────────────────────────────
baseline
write_comment "$DIGEST_ID" 2026-11-05T03:00:00Z 2026-11-05T03:00:00Z stjurik "$ISSUE" "- **#$PR** — зелений на ${SHA:0:7}."
write_list "$DIGEST_ID" "$CONSENT_ID"
std
expect 3 "зведення без позначки бота"

# ── 7. Голова змінилась на щось, що не є update-branch-мерджем над sha
#      (M1 — один батько) → код 5, stderr з «потрібна нова згода». Ловить
#      мутант «голова не перевіряється». ──
baseline
write_pr "$M1"
std
expect 5 "голова змінилась (M1 — не merge update-branch)"
if grep -q "потрібна нова згода на $M1" "$ERRFILE"; then
  ok "stderr називає нову голову $M1"
else
  bad "stderr без «потрібна нова згода на $M1»: $(cat "$ERRFILE")"
fi
if merged; then bad "голова змінилась — merge не мав викликатись"; else ok "голова змінилась — merge не викликано"; fi

# ── 8. Червона перевірка CI → код 5. Ловить мутант «червона перевірка CI
#      пропускається». ──
baseline
write_pr "$SHA" false OPEN main CLEAN "$RED"
std
expect 5 "червона перевірка CI"
if merged; then bad "червоний CI — merge не мав викликатись"; else ok "червоний CI — merge не викликано"; fi

# ── 9. У згоді немає merge: <PR> → код 4. ───────────────────────────────
baseline
write_comment "$CONSENT_ID" 2026-11-05T04:00:00Z 2026-11-05T04:00:00Z stjurik "$ISSUE" "merge: 999"
write_list "$DIGEST_ID" "$CONSENT_ID"
std
expect 4 "у згоді інший PR"

# ── 10. parse-decisions дав питання → код 4, питання у stderr. ──────────
baseline
write_comment "$CONSENT_ID" 2026-11-05T04:00:00Z 2026-11-05T04:00:00Z stjurik "$ISSUE" "MR_TEST_QUESTION merge: $PR"
write_list "$DIGEST_ID" "$CONSENT_ID"
std
expect 4 "parse-decisions дав питання"
if grep -q "тестове питання" "$ERRFILE"; then ok "питання потрапило у stderr"; else bad "питання не в stderr: $(cat "$ERRFILE")"; fi

# ── 11. PR закрито → код 5. ─────────────────────────────────────────────
baseline
write_pr "$SHA" false CLOSED
std
expect 5 "PR закрито"

# ── 12. Збій gh pr merge → код 1. ───────────────────────────────────────
baseline
export MR_MERGE_RC=1
std
unset MR_MERGE_RC
expect 1 "gh pr merge падає"

# ── 13. Аргументи: невалідне значення → код 2. ──────────────────────────
baseline
run_mr abc "$SHA" "$CONSENT_ID" "$DIGEST_ID"
expect 2 "PR не номер"
run_mr "$PR" "${SHA:0:39}" "$CONSENT_ID" "$DIGEST_ID"
expect 2 "sha не 40 символів"
run_mr --foo "$PR" "$SHA" "$CONSENT_ID" "$DIGEST_ID"
expect 2 "невідомий прапорець"

# ── 14. Поза клоном flatcraft → код 2. ──────────────────────────────────
rm -f "$CALLS_DIR"/*
set +e
out="$(cd "$SB" && PATH="$SB/bin:$PATH" PARSE_DECISIONS_SH="$SB/pd.sh" "$MR" "$PR" "$SHA" "$CONSENT_ID" "$DIGEST_ID" 2>"$ERRFILE")"
rc=$?
set -e
expect 2 "поза клоном flatcraft"

if [[ "$fail" -eq 0 ]]; then
  echo "Усі тести пройдено."
  exit 0
else
  echo "FAIL"
  exit 1
fi
