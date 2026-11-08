#!/usr/bin/env bash
# fail-classes.test.sh — власний тест лічильника класів помилок: рядки реєстру,
# правило трьох (CLAUDE.md §0 п.6), збій публікації не губить випадок.
#
# Що СПРАВЖНЄ: tools/scripts/fail-classes.sh. Що ПІДМІНЕНО: SAFE_PUBLISH —
# заглушка тут, що лише записує свій виклик у файл і друкує URL нового issue;
# реального gh і мережі тест не торкається. Усі змінні середовища тест
# експортує сам, бо оракул запускає його з чистим середовищем.
#
# Скрипт кличеться через $FAIL_CLASSES_SH — оракул підставляє сюди мутанти
# (issue не створюється; завжди rc=0; count бреше): кожен мусить почервонити
# цей тест.
#
# Запуск: tools/scripts/fail-classes.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${FAIL_CLASSES_SH:-$HERE/fail-classes.sh}"
fail=0
ok() { echo "✓ $1"; }
bad() {
  echo "✗ $1" >&2
  fail=1
  # Під мутантом зупиняємось на першій розбіжності — оракул чекає нуль-rc.
  [[ -z "${FAIL_CLASSES_SH:-}" ]] || exit 1
}

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/fc" "$T/bin"

# Заглушка safe-publish: записує аргументи й тіло в $STUB_DIR, друкує URL нового
# issue (create) чи коментаря (comment) — як справжній gh.
cat >"$T/bin/sp" <<'EOS'
#!/usr/bin/env bash
k=$(ls "$STUB_DIR" 2>/dev/null | grep -c '^pub-.*\.args$' || true)
k=$((k + 1))
printf '%s\n' "$@" >"$STUB_DIR/pub-$k.args"
cp "$2" "$STUB_DIR/pub-$k.body"
case "$*" in
  *"issue create"*) echo "https://github.com/x/y/issues/$((40 + k))" ;;
  *"issue comment"*) echo "https://github.com/x/y/issues/777#issuecomment-$k" ;;
esac
EOS
chmod +x "$T/bin/sp"

export STUB_DIR="$T" SAFE_PUBLISH="$T/bin/sp" FAIL_CLASSES_DIR="$T/fc"
printf 'demo-class\tдемо-клас\t-\n' >"$T/fc/classes.tsv"
: >"$T/fc/cases.tsv"

run() { bash "$SCRIPT" "$@"; }
pubs() { ls "$T" 2>/dev/null | grep -c '^pub-.*\.args$' || true; }
is_create() { tr '\n' ' ' <"$1" | grep -q 'issue create'; }

# ── add: невалідні аргументи — нічого не записано й не опубліковано ─────────
run add >/dev/null 2>&1
rc=$?
[[ $rc == 2 ]] && ok "add без аргументів → rc=2" || bad "add без аргументів дав rc=$rc"

run add unknown-class x https://e.org >/dev/null 2>&1
rc=$?
[[ $rc == 2 ]] && ok "невідомий клас → rc=2" || bad "невідомий клас дав rc=$rc"

run add demo-class "" https://e.org >/dev/null 2>&1
rc=$?
[[ $rc == 2 ]] && ok "порожній опис → rc=2" || bad "порожній опис дав rc=$rc"

run add demo-class x не-посилання >/dev/null 2>&1
rc=$?
[[ $rc == 2 ]] && ok "посилання без http(s) → rc=2" || bad "погане посилання дав rc=$rc"

run add demo-class "$(printf 'a\tb')" https://e.org >/dev/null 2>&1
rc=$?
[[ $rc == 2 ]] && ok "TAB в описі → rc=2" || bad "TAB в описі дав rc=$rc"

[[ "$(wc -l <"$T/fc/cases.tsv" | tr -d ' ')" == 0 ]] && ok "невдалі add нічого не дописали" || bad "невдалий add дописав рядок у cases.tsv"
[[ "$(pubs)" == 0 ]] || bad "невдалий add щось опублікував"

# ── перші два випадки класу — рядок у cases.tsv, без публікації ─────────────
out1="$(run add demo-class "перший" https://e.org/1)"
rc=$?
[[ $rc == 0 && "$out1" == "клас demo-class: випадків 1" ]] || bad "перший випадок: rc=$rc out='$out1'"
out2="$(run add demo-class "другий" https://e.org/2)"
rc=$?
[[ $rc == 0 && "$out2" == "клас demo-class: випадків 2" ]] || bad "другий випадок: rc=$rc out='$out2'"
[[ "$(pubs)" == 0 ]] && ok "1–2 випадок класу — без публікації" || bad "1–2 випадок класу вже щось опублікував"
[[ "$(run count demo-class)" == 2 ]] && ok "count demo-class = 2" || bad "count demo-class ≠ 2"

# ── третій випадок: issue create, номер — у реєстр ──────────────────────────
out3="$(run add demo-class "третій" https://e.org/3)"
rc=$?
[[ $rc == 0 ]] || bad "третій випадок: rc=$rc"
[[ "$(sed -n 1p <<<"$out3")" == "клас demo-class: випадків 3" ]] || bad "третій випадок: перший рядок stdout — '$out3'"
new_issue="$(sed -n 2p <<<"$out3" | grep -oE '[0-9]+$')"
[[ -n "$new_issue" ]] && ok "третій випадок друкує номер нового issue" || bad "третій випадок без номера issue: '$out3'"
[[ "$(pubs)" == 1 ]] && ok "третій випадок: рівно одна публікація" || bad "третій випадок: публікацій $(pubs), не 1"
is_create "$T/pub-1.args" && ok "третій випадок публікує issue create" || bad "третій випадок — не issue create"
grep -q "https://e.org/1" "$T/pub-1.body" && grep -q "https://e.org/3" "$T/pub-1.body" || bad "тіло нового issue без усіх випадків класу"
grep -q "Оракул" "$T/pub-1.body" || bad "тіло нового issue без розділу «Оракул»"
awk -F'\t' -v n="$new_issue" '$1 == "demo-class" && $3 == n { f = 1 } END { exit !f }' "$T/fc/classes.tsv" ||
  bad "номер нового issue не записано в classes.tsv"

# ── четвертий випадок: коментар у те саме issue, не нове ───────────────────
run add demo-class "четвертий" https://e.org/4 >/dev/null
[[ "$(pubs)" == 2 ]] || bad "четвертий випадок не опублікував рівно одну публікацію"
tr '\n' ' ' <"$T/pub-2.args" | grep -q "issue comment $new_issue" || bad "четвертий випадок — не коментар у #$new_issue"
grep -q "четвертий" "$T/pub-2.body" && grep -q "https://e.org/4" "$T/pub-2.body" || bad "коментар без опису й посилання нового випадку"
! is_create "$T/pub-2.args" && ok "четвертий випадок не створює нового issue" || bad "четвертий випадок створив нове issue"

# ── register ──────────────────────────────────────────────────────────────
run register new-cls "новий клас" >/dev/null
rc=$?
[[ $rc == 0 ]] && ok "register нового класу — rc=0" || bad "register дав rc=$rc"
awk -F'\t' '$1 == "new-cls" && $2 == "новий клас" && $3 == "-" { f = 1 } END { exit !f }' "$T/fc/classes.tsv" ||
  bad "register не дописав рядок класу"
run register new-cls x >/dev/null 2>&1
rc=$?
[[ $rc == 2 ]] && ok "повторний register того самого класу → rc=2" || bad "повторний register дав rc=$rc"
run register Bad_Slug x >/dev/null 2>&1
rc=$?
[[ $rc == 2 ]] && ok "невалідний слаг класу → rc=2" || bad "невалідний слаг дав rc=$rc"
run register only-one-arg >/dev/null 2>&1
rc=$?
[[ $rc == 2 ]] && ok "register з одним аргументом → rc=2" || bad "register з одним аргументом дав rc=$rc"

# ── count без аргументу — за всім реєстром, у порядку реєстру ──────────────
all="$(run count)"
[[ "$all" == "$(printf 'demo-class\t4\nnew-cls\t0')" ]] && ok "count без аргументу — повний список у порядку реєстру" ||
  bad "count без аргументу: '$all'"
run count unknown-class >/dev/null 2>&1
rc=$?
[[ $rc == 2 ]] && ok "count невідомого класу → rc=2" || bad "count невідомого класу дав rc=$rc"

# ── публікація падає: випадок лишається, rc=3, реєстр без змін ─────────────
printf 'flaky\tнестабільний клас\t-\n' >>"$T/fc/classes.tsv"
run add flaky a https://e.org/a >/dev/null
run add flaky b https://e.org/b >/dev/null
cat >"$T/bin/fail-sp" <<'EOS'
#!/usr/bin/env bash
echo "fail-sp: публікація впала" >&2
exit 1
EOS
chmod +x "$T/bin/fail-sp"
export SAFE_PUBLISH="$T/bin/fail-sp"
run add flaky c https://e.org/c >/dev/null 2>&1
rc=$?
export SAFE_PUBLISH="$T/bin/sp"
[[ $rc == 3 ]] && ok "збій публікації на третьому випадку → rc=3" || bad "збій публікації дав rc=$rc"
awk -F'\t' '$2 == "flaky" && $3 == "c" && $4 == "https://e.org/c" { f = 1 } END { exit !f }' "$T/fc/cases.tsv" ||
  bad "після збою публікації рядок випадку зник з cases.tsv"
awk -F'\t' '$1 == "flaky" && $3 == "-" { f = 1 } END { exit !f }' "$T/fc/classes.tsv" ||
  bad "після збою публікації реєстр класу змінено"

p0="$(pubs)"
run add flaky d https://e.org/d >/dev/null
[[ "$(pubs)" == $((p0 + 1)) ]] && ok "наступний add того самого класу пробує опублікувати знову" ||
  bad "наступний add не спробував опублікувати знову (публікацій $(pubs), було $p0)"
is_create "$T/pub-$((p0 + 1)).args" || bad "повторна спроба — не issue create"
[[ "$(run count flaky)" == 4 ]] && ok "count flaky = 4 (рядок після збою не загублено)" || bad "count flaky ≠ 4"
awk -F'\t' '$1 == "flaky" && $3 ~ /^[0-9]+$/ { f = 1 } END { exit !f }' "$T/fc/classes.tsv" ||
  bad "після успішного повтору номер issue не записано в реєстр"

if ((fail == 0)); then
  echo "Усі тести пройдено"
  exit 0
else
  exit 1
fi
