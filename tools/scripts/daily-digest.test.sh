#!/usr/bin/env bash
# daily-digest.test.sh — доказ, що daily-digest.sh справді рахує факти (PR, черга A8,
# квоти agy, hart-inbox), а не друкує гарний шаблон. Усі джерела — заглушки; час —
# DIGEST_NOW, фіксований на сценарій. Скрипт під тестом береться через
# DAILY_DIGEST_SH, бо оракул приймання підставляє замість нього мутанти-обгортки
# (CLAUDE.md §0 п.6: фікс без регресійного тесту не зараховується).
#
# Запуск: tools/scripts/daily-digest.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${DAILY_DIGEST_SH:-$HERE/daily-digest.sh}"
fail=0
ok() { echo "✓ $1"; }
bad() {
  echo "✗ $1"
  fail=1
  # Під мутантом досить однієї червоної перевірки — далі тест лише гаяв би час
  # (мутант обгортає СПРАВЖНІЙ скрипт, інші сценарії того самого прогону йому не цікаві).
  [[ -z "${DAILY_DIGEST_SH:-}" ]] || exit 1
}

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
BIN="$ROOT/bin"
mkdir -p "$BIN"

cat >"$BIN/gh" <<'EOS'
#!/usr/bin/env bash
[ "${STUB_GH:-ok}" = fail ] && { echo "gh: мережі немає" >&2; exit 1; }
case "$*" in
  *"pr list"*) cat <<'J'
[{"number":401,"title":"feat: готовий","isDraft":false,"mergeable":"MERGEABLE","mergeStateStatus":"CLEAN",
  "statusCheckRollup":[{"conclusion":"SUCCESS"},{"conclusion":"SKIPPED"}]},
 {"number":402,"title":"wip: чернетка","isDraft":true,"mergeable":"MERGEABLE","mergeStateStatus":"DRAFT",
  "statusCheckRollup":[{"conclusion":"SUCCESS"}]},
 {"number":403,"title":"fix: конфлікт","isDraft":false,"mergeable":"CONFLICTING","mergeStateStatus":"DIRTY",
  "statusCheckRollup":[{"conclusion":"SUCCESS"}]},
 {"number":404,"title":"fix: червоний CI","isDraft":false,"mergeable":"MERGEABLE","mergeStateStatus":"CLEAN",
  "statusCheckRollup":[{"conclusion":"FAILURE"}]},
 {"number":405,"title":"docs: шаблон ЗАПОВНИТИ у формі","isDraft":false,"mergeable":"MERGEABLE","mergeStateStatus":"CLEAN",
  "statusCheckRollup":[{"conclusion":"SUCCESS"}]},
 {"number":406,"title":"feat: CI ще не стартував","isDraft":false,"mergeable":"MERGEABLE","mergeStateStatus":"CLEAN",
  "statusCheckRollup":[]}]
J
  ;;
  *"issue list"*) cat <<'J'
[{"number":20,"title":"нове зауваження","createdAt":"2026-10-31T04:00:00Z","labels":[{"name":"нове"}]},
 {"number":15,"title":"чекає відповіді","createdAt":"2026-10-27T04:00:00Z","labels":[{"name":"оброблено"},{"name":"потрібна відповідь"}]},
 {"number":7,"title":"давно оброблено","createdAt":"2026-09-01T06:00:00Z","labels":[{"name":"оброблено"},{"name":"в беклозі"}]}]
J
  ;;
  *) echo "stub gh: невідомий виклик $*" >&2; exit 2 ;;
esac
EOS

cat >"$BIN/agy" <<'EOS'
#!/usr/bin/env bash
[ "${STUB_AGY:-ok}" = fail ] && { echo "agy: квота недоступна" >&2; exit 1; }
printf 'Economy Pool\tWeekly Limit Remaining\t30%%\t2026-11-07T04:00:00Z\n'
printf 'Gemini Models\tWeekly Limit Remaining\t10%%\t2026-11-07T04:00:00Z\n'
printf 'Gemini Models\tFive Hour Limit Remaining\t100%%\t2026-11-02T08:00:00Z\n'
printf 'Claude and GPT models\tWeekly Limit Remaining\t40%%\t2026-11-07T04:00:00Z\n'
printf 'Claude and GPT models\tFive Hour Limit Remaining\t10%%\t2026-11-02T08:00:00Z\n'
EOS

cat >"$BIN/a8status" <<'EOS'
#!/usr/bin/env bash
[ "$1" = status ] || { echo "a8status: потрібне дієслово status" >&2; exit 2; }
[ "${STUB_A8:-ok}" = fail ] && { echo "ssh: з'єднання обірвано" >&2; exit 255; }
echo "== A8: стан черги"
if [ "${STUB_A8:-ok}" = stop ]; then
  echo "STOP: Є — kill switch на місці"
else
  echo "STOP: немає"
fi
echo "запобіжники: активні"
echo "плановий потік: працює"
echo "черга: urgent=1 planned=3 running=1 failed=0 done=10 rejected=0"
EOS

cat >"$BIN/safe-publish" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$PUBLISH_CALL_FILE"
EOS
chmod +x "$BIN/"*

cat >"$ROOT/notes.md" <<'EOS'
## Критичний шлях
#401 чекає на merge yurii.
## Чекає на вас
1. глянути #401.
## Що йде
051 у роботі.
## Архітектору
питань немає.
EOS

sec() { awk -v h="## $1" '$0 == h { f = 1; next } /^## / { f = 0 } f' "$2"; }

run() { # run <назва теки-виводу> [аргументи скрипта]...
  local out="$1"
  shift
  GH="$BIN/gh" AGY="$BIN/agy" A8_STATUS_CMD="$BIN/a8status status" \
    SAFE_PUBLISH="$BIN/safe-publish" DIGEST_OUT="$ROOT/$out" \
    HEARTBEAT_FILE="${HEARTBEAT_FILE_OVERRIDE:-$ROOT/$out/heartbeat}" \
    DIGEST_NOW="2026-11-02T04:00:00Z" PUBLISH_CALL_FILE="$ROOT/$out/published" \
    bash "$SCRIPT" "$@"
}

# ─── 1. Повний набір розділів у заданому порядку ──────────────────────────
mkdir -p "$ROOT/case1"
date -u -d '2026-11-02T01:00:00Z' +%s >"$ROOT/case1/heartbeat"
run case1 >"$ROOT/case1.out" 2>&1
rc=$?
D1="$ROOT/case1/digest-2026-11-02.md"
if [[ $rc -eq 0 && -s "$D1" ]]; then
  ok "без аргументів — rc=0, файл написано"
else
  bad "без аргументів — rc=$rc, файл=$([ -s "$D1" ] && echo є || echo немає)"
fi
order="$(grep -E '^## ' "$D1" 2>/dev/null | sed 's/^## //' | tr '\n' '|')"
if [[ "$order" == "Стан|Критичний шлях|Готово до merge|Чекає на вас|Що йде|Квоти|Ризики / STOP|Архітектору|" ]]; then
  ok "вісім розділів у заданому порядку"
else
  bad "порядок розділів: $order"
fi
grep -qF "$D1" "$ROOT/case1.out" && ok "stdout називає шлях до файла" ||
  bad "stdout без шляху: $(cat "$ROOT/case1.out")"
[[ "$(tail -n 1 "$D1")" == '<!-- inbox-bot -->' ]] && ok "останній рядок — позначка inbox-bot" ||
  bad "останній рядок не позначка: $(tail -n 1 "$D1")"

# ─── 2. Судження без --notes — ЗАПОВНИТИ ──────────────────────────────────
sec "Критичний шлях" "$D1" | grep -q 'ЗАПОВНИТИ' && ok "без --notes судження — ЗАПОВНИТИ" ||
  bad "без --notes «Критичний шлях» не ЗАПОВНИТИ"

# ─── 3. Готово до merge: лише зелений mergeable+CLEAN і зелений draft+DRAFT ─
rm_sec="$(sec 'Готово до merge' "$D1")"
if grep -qF -- '- #401 feat: готовий' <<<"$rm_sec" && grep -qF -- '- #402 wip: чернетка — draft' <<<"$rm_sec" &&
  ! grep -q '#403' <<<"$rm_sec" && ! grep -q '#404' <<<"$rm_sec"; then
  ok "«Готово до merge» бере лише зелені PR, draft позначено окремо"
else
  bad "«Готово до merge»: $rm_sec"
fi
# Рецензія #308: PR без жодної перевірки (порожній statusCheckRollup) — не «зелений».
! grep -q '#406' <<<"$rm_sec" && ok "PR без перевірок CI не потрапляє в «Готово до merge»" ||
  bad "PR #406 без перевірок у «Готово до merge»: $rm_sec"
st_sec="$(sec 'Стан' "$D1")"
grep -q '#403' <<<"$st_sec" && grep -q '#404' <<<"$st_sec" && ok "не готові PR названо в «Стан»" ||
  bad "«Стан» не згадує неготові PR: $st_sec"

# ─── 4. hart-inbox: нерозібраний і такий, що чекає відповіді — нарізно ─────
grep -q 'нерозібраний запис hart-inbox: #20 — 2 доб' <<<"$st_sec" &&
  ok "найстаріший нерозібраний (мітка «нове») — #20" ||
  bad "немає нерозібраного #20: $st_sec"
grep -q 'чекає відповіді yurii: #15 — 6 доб' <<<"$st_sec" &&
  ok "чекає відповіді («потрібна відповідь») — #15" ||
  bad "немає «чекає відповіді» #15: $st_sec"
grep -q '#7' <<<"$st_sec" && bad "давно оброблений #7 потрапив у «Стан»" ||
  ok "оброблений #7 не названо"

# ─── 5. Серцебиття — години від DIGEST_NOW ────────────────────────────────
grep -qE 'серцебиття.*3 год' <<<"$st_sec" && ok "серцебиття — 3 години тому" ||
  bad "серцебиття не 3 год: $st_sec"

# ─── 6. Квоти — усі чотири зони з того самого правила ─────────────────────
q_sec="$(sec 'Квоти' "$D1")"
if grep 'Economy Pool' <<<"$q_sec" | grep -q -- '— Економія' &&
  grep 'Gemini Models' <<<"$q_sec" | grep -q -- '— Резерв' &&
  grep 'Claude and GPT' <<<"$q_sec" | grep -q "П'ять годин"; then
  ok "зони квот: Економія / Резерв / П'ять годин рахуються за правилом"
else
  bad "зони квот не збігаються: $q_sec"
fi
grep 'Economy Pool' <<<"$q_sec" | grep -q '30%, до оновлення 120 год (частка тижня 71%)' &&
  ok "Economy Pool — точні цифри (30%, 120 год, 71%)" ||
  bad "Economy Pool — цифри розходяться: $(grep 'Economy Pool' <<<"$q_sec")"

# ─── 7. Ризики / STOP: STOP першим рядком, запобіжники й потік — поруч ────
r_sec="$(sec 'Ризики / STOP' "$D1")"
[[ "$(grep -v '^$' <<<"$r_sec" | head -1)" == 'STOP: немає' ]] && ok "STOP: немає — перший рядок Ризиків" ||
  bad "перший рядок Ризиків не STOP: $r_sec"
grep -q 'запобіжники: активні' <<<"$r_sec" && grep -q 'плановий потік: працює' <<<"$r_sec" &&
  ok "запобіжники й плановий потік — у Ризиках" || bad "немає запобіжників/потоку: $r_sec"

# ─── 8. STOP: Є — лишається першим рядком Ризиків (ключова перевірка проти мутанта) ─
mkdir -p "$ROOT/case2"
STUB_A8=stop run case2 >/dev/null 2>&1
D2="$ROOT/case2/digest-2026-11-02.md"
r2="$(sec 'Ризики / STOP' "$D2")"
[[ "$(grep -v '^$' <<<"$r2" | head -1)" == 'STOP: Є — kill switch на місці' ]] &&
  ok "STOP: Є — потрапляє в Ризики першим рядком" ||
  bad "STOP: Є загубився: $r2"

# ─── 9. Нотатки підставляються; публікація — рівно через SAFE_PUBLISH ─────
mkdir -p "$ROOT/case3"
run case3 --notes "$ROOT/notes.md" --publish 42 >/dev/null 2>&1
rc=$?
D3="$ROOT/case3/digest-2026-11-02.md"
sec 'Критичний шлях' "$D3" | grep -q '#401 чекає на merge yurii' && ok "--notes підставляє судження" ||
  bad "нотатки не підставлено: $(sec 'Критичний шлях' "$D3")"
if [[ $rc -eq 0 && -f "$ROOT/case3/published" &&
  "$(tr '\n' ' ' <"$ROOT/case3/published")" == "gh $D3 issue comment 42 --repo stjurik/hart-inbox " ]]; then
  ok "SAFE_PUBLISH викликано з точними аргументами"
else
  bad "публікація: rc=$rc, аргументи=$(tr '\n' ' ' <"$ROOT/case3/published" 2>/dev/null || echo немає)"
fi

# ─── 10. Публікація з ЗАПОВНИТИ — відмова rc=3, без публікації (ключова проти мутанта) ─
mkdir -p "$ROOT/case4"
run case4 --publish 43 >/dev/null 2>&1
rc=$?
if [[ $rc -eq 3 && ! -f "$ROOT/case4/published" ]]; then
  ok "публікація незавершеного зведення (ЗАПОВНИТИ) — rc=3, SAFE_PUBLISH не викликано"
else
  bad "мало бути rc=3 без публікації: rc=$rc, published=$([ -f "$ROOT/case4/published" ] && echo так || echo ні)"
fi

# ─── 11. Готовий (без ЗАПОВНИТИ) файл дня не перезаписується ──────────────
mkdir -p "$ROOT/case5"
run case5 --notes "$ROOT/notes.md" >/dev/null 2>&1
D5="$ROOT/case5/digest-2026-11-02.md"
h1="$(sha256sum <"$D5")"
run case5 >/dev/null 2>&1
rc1=$?
run case5 --notes "$ROOT/notes.md" >/dev/null 2>&1
rc2=$?
if [[ $rc1 -eq 2 && $rc2 -eq 2 && "$(sha256sum <"$D5")" == "$h1" ]]; then
  ok "завершене зведення (без ЗАПОВНИТИ) не перезаписується — rc=2"
else
  bad "завершене зведення перезаписано або rc≠2: rc1=$rc1 rc2=$rc2"
fi

# ─── 12. Чорновик (із ЗАПОВНИТИ) — можна регенерувати повторним запуском ──
mkdir -p "$ROOT/case6"
run case6 >/dev/null 2>&1
rc1=$?
run case6 --notes "$ROOT/notes.md" >/dev/null 2>&1
rc2=$?
D6="$ROOT/case6/digest-2026-11-02.md"
if [[ $rc1 -eq 0 && $rc2 -eq 0 ]] && sec 'Критичний шлях' "$D6" | grep -q '#401 чекає на merge yurii'; then
  ok "чорновик (ЗАПОВНИТИ) можна регенерувати з --notes"
else
  bad "чорновик не регенерувався: rc1=$rc1 rc2=$rc2"
fi

# ─── 13. Збій джерела — НЕ ПЕРЕВІРЕНО з причиною, а не падіння (rc=0) ─────
mkdir -p "$ROOT/case7"
STUB_A8=fail run case7 >/dev/null 2>&1
rc=$?
D7="$ROOT/case7/digest-2026-11-02.md"
if [[ $rc -eq 0 ]] && sec 'Стан' "$D7" | grep -qE "НЕ ПЕРЕВІРЕНО.*(обірвано|255)" &&
  sec 'Ризики / STOP' "$D7" | grep -qE "НЕ ПЕРЕВІРЕНО.*(обірвано|255)"; then
  ok "збій a8-ctl status — НЕ ПЕРЕВІРЕНО у Стан і Ризиках, rc=0"
else
  bad "збій a8-ctl не оброблено: rc=$rc"
fi

mkdir -p "$ROOT/case8"
STUB_GH=fail run case8 >/dev/null 2>&1
rc=$?
D8="$ROOT/case8/digest-2026-11-02.md"
if [[ $rc -eq 0 ]] && sec 'Стан' "$D8" | grep -q "НЕ ПЕРЕВІРЕНО.*мережі немає" &&
  sec 'Готово до merge' "$D8" | grep -q "НЕ ПЕРЕВІРЕНО.*мережі немає"; then
  ok "збій gh — НЕ ПЕРЕВІРЕНО у Стан і «Готово до merge», rc=0"
else
  bad "збій gh не оброблено: rc=$rc"
fi

mkdir -p "$ROOT/case9"
STUB_AGY=fail run case9 >/dev/null 2>&1
rc=$?
D9="$ROOT/case9/digest-2026-11-02.md"
if [[ $rc -eq 0 ]] && sec 'Квоти' "$D9" | grep -q "НЕ ПЕРЕВІРЕНО.*квота недоступна"; then
  ok "збій agy /usage — НЕ ПЕРЕВІРЕНО у Квотах, rc=0"
else
  bad "збій agy не оброблено: rc=$rc"
fi

# ─── 14. Серцебиття без файла — «немає», не падіння ───────────────────────
mkdir -p "$ROOT/case10"
HEARTBEAT_FILE_OVERRIDE="$ROOT/case10/nema" run case10 >/dev/null 2>&1
D10="$ROOT/case10/digest-2026-11-02.md"
sec 'Стан' "$D10" | grep -qE 'серцебиття.*(немає|НЕ ПЕРЕВІРЕНО)' && ok "без файла серцебиття — «немає»" ||
  bad "серцебиття без файла: $(sec 'Стан' "$D10")"
unset HEARTBEAT_FILE_OVERRIDE

if [[ "$fail" -eq 1 ]]; then
  echo "FAIL"
  exit 1
fi
echo "Усі тести пройдено."
