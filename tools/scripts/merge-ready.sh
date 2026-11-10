#!/usr/bin/env bash
# merge-ready.sh — merge одного PR лише за чинною згодою yurii, прив'язаною до
# голови PR (ADR-044 п.7, рішення yurii «3а», задача A8 055).
#
# ЧОМУ. Згода на merge — рядок «merge: N» у відповіді yurii на зведення доби в
# hart-inbox (розбирає parse-decisions.sh, задача 052). Сама згода не каже,
# яку голову PR вона дозволяє, — лише зведення, на яке вона відповідає,
# називає «зелений на <sha>». Тому ми прив'язуємо голову з аргумента до
# merge-команди через --match-head-commit: якщо голова PR на момент виклику
# gh pr merge інша, GitHub сам відмовляє — атомарно, без вікна гонки між
# нашою перевіркою і фактичним merge.
#
# ЩО ЦЕ ДОВОДИТЬ: що голова PR станом на виклик gh pr merge — саме та, яку
# перевірено (--match-head-commit — межа атомарності самого GitHub, не
# нашого коду); що згода — останній коментар власника після останнього
# зведення з позначкою бота, без редагування після публікації.
#
# ЧОГО НЕ ДОВОДИТЬ. Що коментар написав саме yurii, а не хтось інший з того
# самого облікового запису stjurik — оркестратор, Архітектор і yurii пишуть
# з одного логіна, і ми розрізняємо їх лише за відсутністю позначок бота чи
# Архітектора. Це захист від ПОМИЛКИ агента, не від навмисної підробки
# (ADR-044 п.7 «а», прийнято свідомо yurii). Права самого виклику цього
# скрипта (хто може його запустити) — справа профілю дозволів, не цього
# файла.
#
# Використання:
#   merge-ready.sh [--dry-run] <PR> <sha> <id-коментаря-згоди> <id-коментаря-зведення>
#
# Коди виходу: 0 — злито (або --dry-run пройшов); 1 — збій gh/git чи
# відповідь не JSON; 2 — аргументи або тека; 3 — згода чи зведення не чинні;
# 4 — у згоді цього PR немає, або parse-decisions дав питання; 5 — стан PR,
# голова чи CI не дозволяють merge.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
GH="${GH:-gh}"
PARSE_DECISIONS_SH="${PARSE_DECISIONS_SH:-$HERE/parse-decisions.sh}"

FLATCRAFT="stjurik/flatcraft"
HART_INBOX="stjurik/hart-inbox"
OWNER="stjurik"
ISSUE="${MERGE_READY_INBOX_ISSUE:-8}"
MARK='<!-- inbox-bot -->'

die() {
  echo "merge-ready: $1" >&2
  exit "$2"
}

# ─── аргументи ────────────────────────────────────────────────────────────
DRY_RUN=0
args=("$@")
if ((${#args[@]} > 0)) && [[ "${args[0]}" == --* ]]; then
  if [[ "${args[0]}" == "--dry-run" ]]; then
    DRY_RUN=1
    args=("${args[@]:1}")
  else
    die "невідомий прапорець «${args[0]}»" 2
  fi
fi
((${#args[@]} == 4)) || die "використання: merge-ready.sh [--dry-run] <PR> <sha> <id-згоди> <id-зведення>" 2
PR="${args[0]}"
SHA="${args[1]}"
CONSENT_ID="${args[2]}"
DIGEST_ID="${args[3]}"
[[ "$PR" =~ ^[1-9][0-9]*$ ]] || die "PR «$PR» — не номер" 2
[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || die "sha «$SHA» — не 40 hex-символів" 2
[[ "$CONSENT_ID" =~ ^[1-9][0-9]*$ ]] || die "id згоди «$CONSENT_ID» — не номер" 2
[[ "$DIGEST_ID" =~ ^[1-9][0-9]*$ ]] || die "id зведення «$DIGEST_ID» — не номер" 2

# ─── тека ─────────────────────────────────────────────────────────────────
top="$(git rev-parse --show-toplevel 2>/dev/null)" || die "не в git-дереві — запускайте з кореня клону flatcraft" 2
[[ "$top" == "$PWD" ]] || die "запускайте з кореня клону («$top» ≠ «$PWD»)" 2
git remote get-url origin >/dev/null 2>&1 || die "немає remote origin" 2

# ─── утиліти ──────────────────────────────────────────────────────────────
unquoted() { # unquoted <текст> — рядки без ведучого (після пробілів) «>»
  grep -vE '^[[:space:]]*>' <<<"$1" 2>/dev/null || true
}
epoch() { # epoch <ISO8601Z> — unix-час або порожньо
  jq -rn --arg t "$1" '$t | fromdateiso8601' 2>/dev/null
}
# gh_api_json/gh_api_list НЕ викликають die: die всередині функції, покликаної через
# підстановку команди `x="$(fn)"`, завершує лише підшкаралупу підстановки, а не весь
# скрипт — тож помилку повертаємо кодом і текстом у GH_ERR, die кличе викликач.
gh_api_json() { # gh_api_json <шлях> — одне валідне значення JSON; $? != 0 → GH_ERR
  local out rc
  out="$("$GH" api "$1" 2>&1)"
  rc=$?
  if ((rc != 0)); then
    GH_ERR="gh api $1: $out"
    return 1
  fi
  if ! jq -e . >/dev/null 2>&1 <<<"$out"; then
    GH_ERR="gh api $1: відповідь не JSON: $out"
    return 1
  fi
  printf '%s' "$out"
}
gh_api_list() { # gh_api_list <шлях> — сторінки --paginate, зведені в один масив
  local raw rc merged
  raw="$("$GH" api "$1" --paginate 2>&1)"
  rc=$?
  if ((rc != 0)); then
    GH_ERR="gh api $1 --paginate: $raw"
    return 1
  fi
  merged="$(jq -cs 'add // []' <<<"$raw" 2>&1)"
  if (($? != 0)); then
    GH_ERR="gh api $1 --paginate: відповідь не JSON: $merged"
    return 1
  fi
  printf '%s' "$merged"
}

# ─── 1. коментар згоди ────────────────────────────────────────────────────
consent_json="$(gh_api_json "repos/$HART_INBOX/issues/comments/$CONSENT_ID")" || die "$GH_ERR" 1
c_login="$(jq -r '.user.login' <<<"$consent_json")"
c_issue_url="$(jq -r '.issue_url' <<<"$consent_json")"
c_created="$(jq -r '.created_at' <<<"$consent_json")"
c_updated="$(jq -r '.updated_at' <<<"$consent_json")"
c_body="$(jq -r '.body' <<<"$consent_json")"
c_html_url="$(jq -r '.html_url' <<<"$consent_json")"

[[ "$c_login" == "$OWNER" ]] || die "коментар згоди #$CONSENT_ID не від $OWNER" 3
[[ "$c_issue_url" == */issues/"$ISSUE" ]] || die "коментар згоди #$CONSENT_ID не в issue $ISSUE" 3
[[ "$c_created" == "$c_updated" ]] || die "коментар згоди #$CONSENT_ID відредаговано — не рахується" 3
c_unquoted="$(unquoted "$c_body")"
if grep -qF -- "$MARK" <<<"$c_unquoted" || grep -qE 'Архітектор (→|->)' <<<"$c_unquoted"; then
  die "коментар згоди #$CONSENT_ID має позначку бота чи Архітектора — не від yurii" 3
fi

# ─── 2. коментар зведення ─────────────────────────────────────────────────
digest_json="$(gh_api_json "repos/$HART_INBOX/issues/comments/$DIGEST_ID")" || die "$GH_ERR" 1
d_login="$(jq -r '.user.login' <<<"$digest_json")"
d_issue_url="$(jq -r '.issue_url' <<<"$digest_json")"
d_created="$(jq -r '.created_at' <<<"$digest_json")"
d_body="$(jq -r '.body' <<<"$digest_json")"

[[ "$d_login" == "$OWNER" ]] || die "зведення #$DIGEST_ID не від $OWNER" 3
[[ "$d_issue_url" == */issues/"$ISSUE" ]] || die "зведення #$DIGEST_ID не в issue $ISSUE" 3
d_unquoted="$(unquoted "$d_body")"
grep -qF -- "$MARK" <<<"$d_unquoted" || die "зведення #$DIGEST_ID без позначки бота" 3

c_epoch="$(epoch "$c_created")"
d_epoch="$(epoch "$d_created")"
[[ -n "$c_epoch" && -n "$d_epoch" ]] || die "дата згоди чи зведення не ISO8601" 1
((d_epoch < c_epoch)) || die "зведення #$DIGEST_ID не раніше згоди #$CONSENT_ID" 3

comments_json="$(gh_api_list "repos/$HART_INBOX/issues/$ISSUE/comments")" || die "$GH_ERR" 1
newer="$(jq -r --arg owner "$OWNER" --arg mark "$MARK" --argjson did "$DIGEST_ID" --argjson depoch "$d_epoch" '
  [ .[]
    | select(.id != $did)
    | select(.user.login == $owner)
    | select(((.body // "") | split("\n") | map(select(test("^\\s*>") | not)) | join("\n")) | contains($mark))
    | select((.created_at | fromdateiso8601) > $depoch)
  ] | length' <<<"$comments_json")"
[[ "$newer" == "0" ]] || die "є новіше зведення з позначкою бота — стара згода анульована" 3

# ─── 3. зведення називає голову ───────────────────────────────────────────
pattern="#${PR}([^0-9]|\$)"
matching_lines="$(grep -E "$pattern" <<<"$d_unquoted" || true)"
mapfile -t raw_matches < <(grep -oE 'зелений на [0-9a-f]+' <<<"$matching_lines" || true)
tokens=()
for m in "${raw_matches[@]}"; do
  tokens+=("${m#"зелений на "}")
done
((${#tokens[@]} > 0)) || die "зведення не називає голову PR #$PR" 3
for t in "${tokens[@]}"; do
  len=${#t}
  ((len >= 7 && len <= 40)) || die "зведення #$DIGEST_ID: токен голови «$t» поза довжиною 7..40" 3
  [[ "${SHA:0:$len}" == "$t" ]] || die "зведення #$DIGEST_ID: токен голови «$t» не префікс sha $SHA" 3
done

# ─── 4. parse-decisions ───────────────────────────────────────────────────
reply_tmp="$(mktemp)"
digest_tmp="$(mktemp)"
printf '%s\n' "$c_unquoted" >"$reply_tmp"
printf '%s\n' "$d_unquoted" >"$digest_tmp"
pd_out="$("$PARSE_DECISIONS_SH" "$reply_tmp" "$digest_tmp" 2>"$reply_tmp.err")"
pd_rc=$?
pd_err="$(cat "$reply_tmp.err" 2>/dev/null)"
rm -f "$reply_tmp" "$digest_tmp" "$reply_tmp.err"

case "$pd_rc" in
  0)
    in_merge="$(jq -r --argjson pr "$PR" '(.merge // []) | any(. == $pr)' <<<"$pd_out" 2>/dev/null)"
    [[ "$in_merge" == "true" ]] || die "у згоді #$CONSENT_ID немає «merge: $PR»" 4
    ;;
  4)
    while IFS= read -r q; do
      [[ -n "$q" ]] && echo "$q" >&2
    done < <(jq -r '.questions[]?' <<<"$pd_out" 2>/dev/null)
    die "parse-decisions: є питання до відповіді #$CONSENT_ID" 4
    ;;
  *)
    die "parse-decisions: несподіваний код $pd_rc; $pd_err" 1
    ;;
esac

# ─── 5. стан PR ───────────────────────────────────────────────────────────
pr_out="$("$GH" pr view "$PR" -R "$FLATCRAFT" --json state,isDraft,baseRefName,headRefOid,mergeStateStatus,statusCheckRollup 2>&1)"
pr_rc=$?
((pr_rc == 0)) || die "gh pr view $PR: $pr_out" 1
jq -e . >/dev/null 2>&1 <<<"$pr_out" || die "gh pr view $PR: відповідь не JSON: $pr_out" 1

state="$(jq -r '.state' <<<"$pr_out")"
base="$(jq -r '.baseRefName' <<<"$pr_out")"
is_draft="$(jq -r '.isDraft' <<<"$pr_out")"
head="$(jq -r '.headRefOid' <<<"$pr_out")"
mss="$(jq -r '.mergeStateStatus' <<<"$pr_out")"
rollup="$(jq -c '.statusCheckRollup' <<<"$pr_out")"

[[ "$state" == "OPEN" ]] || die "PR #$PR state=$state (очікую OPEN)" 5
[[ "$base" == "main" ]] || die "PR #$PR base=$base (очікую main)" 5

# ─── 6. голова ────────────────────────────────────────────────────────────
if [[ "$head" == "$SHA" ]]; then
  effective_head="$SHA"
else
  fetch_out="$(git fetch --quiet origin "$head" main 2>&1)"
  fetch_rc=$?
  ((fetch_rc == 0)) || die "git fetch origin $head main: $fetch_out" 1

  parents_out="$(git rev-list --parents -n1 "$head" 2>&1)"
  parents_rc=$?
  ((parents_rc == 0)) || die "git rev-list --parents $head: $parents_out" 1
  read -r _ p1 p2 extra <<<"$parents_out"
  if [[ -z "$p1" || -z "$p2" || -n "$extra" || "$p1" != "$SHA" ]]; then
    die "потрібна нова згода на $head" 5
  fi
  git merge-base --is-ancestor "$p2" origin/main 2>/dev/null || die "потрібна нова згода на $head" 5

  mt_out="$(git merge-tree --write-tree "$SHA" "$p2" 2>&1)"
  mt_rc=$?
  ((mt_rc == 0)) || die "потрібна нова згода на $head" 5
  mt_tree="$(head -n1 <<<"$mt_out")"
  head_tree="$(git rev-parse "$head^{tree}" 2>&1)" || die "git rev-parse $head^{tree}: $head_tree" 1
  [[ "$mt_tree" == "$head_tree" ]] || die "потрібна нова згода на $head" 5

  effective_head="$head"
fi

# ─── 7. CI ────────────────────────────────────────────────────────────────
ci_ok="$(jq -n --argjson arr "$rollup" '
  ($arr | length) > 0
  and ($arr | all(. as $x | (($x.conclusion // $x.state) as $v | $v == "SUCCESS" or $v == "NEUTRAL" or $v == "SKIPPED")))
  and ($arr | any(. as $x | (($x.conclusion // $x.state) == "SUCCESS")))
')"
[[ "$ci_ok" == "true" ]] || die "CI PR #$PR не зелений (чи тестів не було)" 5
[[ "$mss" == "CLEAN" ]] || die "PR #$PR mergeStateStatus=$mss (очікую CLEAN)" 5

# ─── 8. мутації ───────────────────────────────────────────────────────────
if ((DRY_RUN)); then
  echo "ГОТОВО: #$PR голова $effective_head згода $CONSENT_ID"
  exit 0
fi

if [[ "$is_draft" == "true" ]]; then
  ready_out="$("$GH" pr ready "$PR" -R "$FLATCRAFT" 2>&1)"
  ready_rc=$?
  ((ready_rc == 0)) || die "gh pr ready $PR: $ready_out" 1
fi

merge_out="$("$GH" pr merge "$PR" -R "$FLATCRAFT" --squash --match-head-commit "$effective_head" 2>&1)"
merge_rc=$?
((merge_rc == 0)) || die "gh pr merge $PR: $merge_out" 1

echo "ЗЛИТО: #$PR голова $effective_head згода $c_html_url"
exit 0
