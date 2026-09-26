#!/usr/bin/env bash
# a8-metrics.test.sh — числа a8-metrics.sh на синтетичному журналі з відомою відповіддю.
#
# Журнал нижче складено руками так, щоб кожне визначення мало випадок, на якому
# правильна і неправильна реалізація розходяться: подія між прогонами (серія не
# рветься), no-credential (серію рве), запис поза вікном, auth_stop перед kill
# switch (не навчальна зупинка), нерозібраний рядок, перемішаний порядок рядків.
#
# Мутації в кінці: ламаємо скрипт по одному визначенню — набір мусить почервоніти.
#
# Запуск: tools/scripts/a8-metrics.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${A8_METRICS_UNDER_TEST:-$HERE/a8-metrics.sh}"
fail=0
say() { [[ -z "${QUIET:-}" ]] && echo "$@"; return 0; }
ok() { say "✓ $1"; }
bad() {
  echo "✗ $1"
  fail=1
}
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

NOW=2026-10-01T12:00:00Z

run() { # run <ts> <task> <result> <exit_class> <detail> <oracle_rc>
  jq -nc --arg ts "$1" --arg t "$2" --arg r "$3" --arg c "$4" --arg d "$5" --arg o "$6" \
    '{ts:$ts, event:"run", task:$t, source:"human", result:$r, duration_s:1, model:"sonnet",
      note:"", exit_class:$c, detail:$d, origin:"direction", oracle:"x", oracle_rc:$o,
      branch:("ai/"+$t), worktree:"/w"}'
}
event() { jq -nc --arg ts "$1" --arg s "$2" --arg d "$3" '{ts:$ts, event:$s, detail:$d}'; }
reject() { jq -nc --arg ts "$1" --arg t "$2" --arg f "$3" '{ts:$ts, event:"reject", task:$t, result:"rejected", fields:($f|split(","))}'; }

# Відомі відповіді (вікно 14 днів до NOW = з 2026-09-17T12:00:00Z):
#   серія ok: найдовша 3 (22, 23, 24), поточна 0;
#   у вікні 12 прогонів, з них ok 5, forbidden 1, оракул виконано 10;
#   відхилено без оракула 1; навчальних зупинок 1;
#   правило трьох: failed:oracle = 3; нерозібраних рядків 1.
{
  run 2026-09-11T10:00:00Z old ok ok pushed 0 # поза вікном
  run 2026-09-20T10:00:00Z a ok ok pushed 0
  run 2026-09-21T10:00:00Z b failed failed "oracle rc=1" 1
  run 2026-09-22T10:00:00Z c ok ok pushed 0
  event 2026-09-22T11:00:00Z busy "інший тік ще працює" # серію не рве
  run 2026-09-23T10:00:00Z d ok ok pushed 0
  run 2026-09-24T10:00:00Z e ok ok pushed 0
  run 2026-09-25T08:00:00Z f failed failed deps -
  run 2026-09-25T10:00:00Z g failed failed "forbidden-paths: infra/x " -
  reject 2026-09-26T10:00:00Z h "oracle:missing"
  run 2026-09-27T10:00:00Z i no-credential ok "push пропущено: креденшала немає" 0 # серію рве
  run 2026-09-28T10:00:00Z j ok ok pushed 0
  run 2026-09-29T09:59:30Z k stopped stopped "kill switch під час оракула; гілка має коміти" 10
  event 2026-09-29T10:00:00Z kill_switch "a8-guard check → 10"
  event 2026-09-29T10:05:00Z kill_switch "a8-guard check → 10" # той самий епізод
  run 2026-09-30T08:00:00Z l failed failed "oracle rc=2" 2
  run 2026-09-30T12:00:00Z m failed failed "oracle rc=1" 1
  echo 'це не JSON'
} >"$tmp/journal"

m() { # m <jq-вираз> [прапорці…] — значення з --json на журналі $tmp/journal
  local expr="$1"
  shift
  "$SCRIPT" --json --now "$NOW" "$@" "$tmp/journal" | jq -c "$expr"
}
expect() { # expect <назва> <очікуване> <jq-вираз> [прапорці…]
  local name="$1" want="$2" expr="$3"
  shift 3
  local got
  got="$(m "$expr" "$@" 2>&1)"
  if [[ "$got" == "$want" ]]; then ok "$name = $want"; else bad "$name: очікував $want, отримав $got"; fi
}

expect "крок 5: найдовша серія ok поспіль" 3 .step5.streak_best
expect "крок 5: поточна серія" 0 .step5.streak_current
expect "крок 5: без --stop-at час зупинки не рахується" null .step5.kill_switch_s
expect "крок 5: kill switch → перша зупинка" 30 .step5.kill_switch_s --stop-at 2026-09-29T09:59:00Z
expect "крок 5: після останньої зупинки — зупинки немає" null .step5.kill_switch_s --stop-at 2026-09-30T00:00:00Z
expect "крок 6: прогонів у вікні" 12 .step6.runs
expect "крок 6: доведено до push" 5 .step6.done
expect "крок 6: спроб запису у виключений шлях" 1 .step6.forbidden
expect "крок 6: оракул виконано" 10 .step6.oracle_runs
expect "крок 6: оракул зелений" 6 .step6.oracle_green
expect "крок 5: серія з --since" 1 .step5.streak_best --since 2026-09-25T00:00:00Z
expect "крок 6: відхилено без оракула" 1 .step6.oracle_missing_rejects
expect "крок 6: навчальних зупинок" 1 .step6.kill_switch_drills
expect "правило трьох: failed:oracle" 3 '.rule_of_three["failed:oracle"]'
expect "правило трьох: спрацювання" '["failed:oracle"]' .rule_of_three_hits
expect "нерозібраних рядків" 1 .journal.invalid_lines
expect "вікно 30 днів: прогонів" 13 .step6.runs --window-days 30

# Порядок рядків не має значення: ротовані файли можуть прийти в іншому порядку.
shuf --random-source=<(yes) "$tmp/journal" >"$tmp/shuffled"
if [[ "$("$SCRIPT" --json --now "$NOW" "$tmp/shuffled" | jq -c '[.step5.streak_best, .step6.kill_switch_drills]')" == "[3,1]" ]]; then
  ok "перемішаний журнал → ті самі серія і зупинки"
else
  bad "перемішаний журнал: $("$SCRIPT" --json --now "$NOW" "$tmp/shuffled" | jq -c '[.step5, .step6.kill_switch_drills]')"
fi

# auth_stop сам пише STOP: така зупинка — не навчальна.
{
  run 2026-09-29T09:00:00Z z auth_stop auth_stop 401 -
  event 2026-09-29T09:05:00Z kill_switch "a8-guard check → 10"
} >"$tmp/auth"
got="$("$SCRIPT" --json --now "$NOW" "$tmp/auth" | jq -c .step6.kill_switch_drills)"
[[ "$got" == 0 ]] && ok "kill switch після auth_stop — не навчальна зупинка" || bad "auth_stop як навчальна зупинка: $got"

# Межа вікна не губить причину: auth_stop за 5 хв ДО вікна, його kill switch —
# уже у вікні. Це не навчальна зупинка (знайшов рецензент agy, Gemini 3.8 Flash).
{
  run 2026-09-17T11:55:00Z z auth_stop auth_stop 401 -
  event 2026-09-17T12:05:00Z kill_switch "a8-guard check → 10"
  event 2026-09-17T12:15:00Z kill_switch "a8-guard check → 10"
} >"$tmp/edge"
got="$("$SCRIPT" --json --now "$NOW" "$tmp/edge" | jq -c .step6.kill_switch_drills)"
[[ "$got" == 0 ]] && ok "auth_stop перед межею вікна — не навчальна зупинка" || bad "межа вікна: $got"

# Черга простоює після auth_stop (між записами нічого), а через години — справжня
# навчальна зупинка (a8-report --killswitch-test пише одну подію kill_switch).
{
  run 2026-09-29T09:00:00Z z auth_stop auth_stop 401 -
  event 2026-09-29T09:10:00Z kill_switch "a8-guard check → 10"
  event 2026-09-29T15:00:00Z kill_switch "a8-guard check → 10"
} >"$tmp/idle"
got="$("$SCRIPT" --json --now "$NOW" "$tmp/idle" | jq -c .step6.kill_switch_drills)"
[[ "$got" == 1 ]] && ok "навчальна зупинка через години після auth_stop — рахується" || bad "простій після auth_stop: $got"

# Правило трьох: коди виходу агента — один клас; auth_stop і відхилення — теж
# класи (рецензент agy, Gemini 3.8 Flash).
{
  run 2026-09-28T10:00:00Z a failed failed "rc=1" -
  run 2026-09-28T11:00:00Z b failed failed "rc=2" -
  run 2026-09-28T12:00:00Z c failed failed "rc=1" -
  run 2026-09-28T13:00:00Z d auth_stop auth_stop 401 -
  run 2026-09-28T14:00:00Z e auth_stop auth_stop 401 -
  run 2026-09-28T15:00:00Z f auth_stop auth_stop "401; гілка має коміти — не повертаю в чергу" -
  reject 2026-09-28T16:00:00Z g "oracle:missing"
  reject 2026-09-28T17:00:00Z h "oracle:missing,source:missing"
  reject 2026-09-28T18:00:00Z i "oracle:missing"
} >"$tmp/classes"
got="$("$SCRIPT" --json --now "$NOW" "$tmp/classes" | jq -c '.rule_of_three_hits | sort')"
[[ "$got" == '["auth_stop:401","failed:rc","reject:oracle:missing"]' ]] &&
  ok "правило трьох: rc=N — один клас, auth_stop і відхилення рахуються" || bad "класи падінь: $got"

# Порожній журнал — нулі, не падіння.
: >"$tmp/empty"
got="$("$SCRIPT" --json --now "$NOW" "$tmp/empty" 2>&1 | jq -c '[.journal.records, .step5.streak_best, .step6.runs]' 2>&1)"
[[ "$got" == "[0,0,0]" ]] && ok "порожній журнал → нулі" || bad "порожній журнал: $got"

# Текстовий звіт: позначки відповідають числам, а відсутні в журналі — названі.
text="$("$SCRIPT" --now "$NOW" "$tmp/journal")"
check_line() { # check_line <назва> <підрядок>
  if [[ "$text" == *"$2"* ]]; then ok "текст: $1"; else bad "текст: $1 — немає «$2»"; fi
}
check_line "серія 3 → ✅" "✅ Задача end-to-end поспіль без втручання: найдовша серія 3"
check_line "5 задач до push → ❌" "❌ Задач доведено до push без втручання: 5"
check_line "запис у виключений шлях → ❌" "❌ Спроб запису у виключений шлях (backstop): 1"
check_line "покриття 10/12 → ✅" "✅ Покриття оракулами (оракул виконався): 10/12 = 83%"
check_line "зелених оракулів" "зелених 6/12 = 50%"
check_line "злиття — не з журналу" "НЕ З ЖУРНАЛУ — Змерджено без доробок"
check_line "ребут — не з журналу" "НЕ З ЖУРНАЛУ — Ребут"
check_line "питання — не з журналу" "НЕ З ЖУРНАЛУ — Питання класу A"
check_line "правило трьох" "failed:oracle — 3 → повторився ≥ 3 разів"

# Невалідний аргумент — код 2, а не звіт.
rc=0
"$SCRIPT" --stop-at вчора "$tmp/journal" >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]] && ok "--stop-at не в ISO → код 2" || bad "--stop-at вчора → rc=$rc"

# КОНТРОЛЬ ПЕРЕД МУТАЦІЯМИ: на червоному базисі кожен мутант «убитий» за
# визначенням (той самий урок, що в a8-tick.test.sh).
if [[ -z "${A8_METRICS_UNDER_TEST:-}" && "$fail" -ne 0 ]]; then
  echo
  echo "✗ мутації НЕ ганялись: базовий набір червоний."
elif [[ -z "${A8_METRICS_UNDER_TEST:-}" ]]; then
  MUTDIR="$(mktemp -d)"
  n=0
  mutate() { # mutate <назва> <perl-вираз>
    n=$((n + 1))
    local mfile="$MUTDIR/$n.sh"
    perl -0pe "$2" "$HERE/a8-metrics.sh" >"$mfile"
    if cmp -s "$mfile" "$HERE/a8-metrics.sh"; then
      bad "мутація «$1» нічого не змінила — вираз застарів"
    elif QUIET=1 A8_METRICS_UNDER_TEST="$mfile" bash "$0" >/dev/null 2>&1; then
      bad "мутація «$1» ВИЖИЛА — набір зелений на зламаному скрипті"
    else
      ok "мутація «$1» убита"
    fi
  }
  mutate "серія не рветься на падінні" 's/else \.cur = 0 end/else . end/'
  mutate "no-credential рахується в серію" 's/if \$r\.result == "ok" then \.cur \+= 1/if \$r.exit_class == "ok" then .cur += 1/'
  mutate "подія рве серію" 's/reduce \(\$runs\[\] \| select/reduce (\$all[] | select/'
  mutate "вікно ігнорується" 's/\[ \$win\[\] \| select\(\.event == "run"\) \] as \$wruns/[ \$all[] | select(.event == "run") ] as \$wruns/'
  mutate "forbidden не рахуються" 's/startswith\("forbidden-paths"\)/startswith("forbidden_paths")/'
  mutate "прогін без оракула рахується покритим" 's/select\(\(\.oracle_rc \/\/ "-"\) != "-"\)/select(true)/'
  mutate "поріг правила трьох 4" 's/select\(\.value >= 3\)/select(.value >= 4)/'
  mutate "auth_stop рахується навчальною зупинкою" 's/select\(\.auth \| not\)/select(true)/'
  mutate "кожен запис kill switch — окрема зупинка" 's/\(if \(\.in \| not\) or/(if true or/'
  mutate "журнал не сортується за часом" 's/ \| sort_by\(\.ts \/\/ ""\)//'
  mutate "нерозібрані рядки не рахуються" 's/select\(type != "object"\)/select(false)/'
  mutate "зупинка шукається до --stop-at" 's/select\(\(t \/\/ -1\) >= \$s\)/select(true)/'
  mutate "епізоди рахуються лише у вікні" 's/reduce \$all\[\] as \$r \(\{in: false/reduce \$win[] as \$r ({in: false/'
  mutate "пауза не розділяє епізоди" 's/\(\$rt - \.last_ks\) > \$gap/false/'
  mutate "rc=N дробить клас" 's/splits\("\[ :;=\]"\)/splits("[ :;]")/'
  mutate "auth_stop не в правилі трьох" 's/select\(\.result == "failed" or \.result == "auth_stop"\)/select(.result == "failed")/'
  mutate "--since ігнорується" 's/select\(\(t \/\/ -1\) >= \$since_t\)/select(true)/'
  rm -rf "$MUTDIR"
fi

if [[ "$fail" -eq 1 ]]; then
  echo "FAIL"
  exit 1
fi
say "Усі тести пройдено."
exit 0
