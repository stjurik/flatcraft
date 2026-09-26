#!/usr/bin/env bash
# a8-metrics.sh — числа критеріїв виходу кроків 5 і 6 треку T5 із журналу A8.
#
# ЧОМУ ЦЕЙ СКРИПТ ІСНУЄ. Критерії кроків 5 і 6 (docs/02, трек T5) — числа.
# Рахувати їх руками з журналу — це щоразу заново вирішувати, що таке
# «поспіль», «у вікні» чи «покриття», і щоразу трохи інакше. Тут кожне
# визначення записано один раз, а a8-metrics.test.sh тримає його на
# синтетичному журналі з відомою відповіддю і мутаціями.
#
# ЧОГО НЕ РАХУЄ. Числа, яких у журналі немає, друкуються як «НЕ З ЖУРНАЛУ» з
# указанням, де їх брати: злиття без доробок (GitHub), питання класу A
# (механізму питань ще немає), повернення після ребуту (a8-report.sh після
# ребуту). Вигадане число гірше за порожнє місце (CLAUDE.md §0 п.3).
#
# ВИЗНАЧЕННЯ:
#   end-to-end   — запис `run` з result=ok: оракул зелений і гілку запушено.
#                  Draft PR створює Action a8-pr.yml, з журналу його не видно;
#   поспіль      — серед записів `run`, у порядку часу; `no-credential`,
#                  `failed`, `stopped`, `auth_stop` серію рвуть, події — ні;
#   вікно        — записи з ts у [зараз − N днів, зараз] (крок 6: N = 14);
#   покриття     — частка прогонів у вікні, де оракул справді виконався
#                  (oracle_rc — число, не «-»);
#   навч. зупинка — епізод kill switch (подія kill_switch або stopped через
#                  kill switch). Новий епізод — після запису іншого типу або
#                  паузи понад --episode-gap-min хв (дефолт 30 = 3 інтервали тіку
#                  a8_tick_interval_minutes): поки STOP лежить, кожен тік пише
#                  kill_switch, а черга, що простоює, не пише нічого. Епізод, якому
#                  безпосередньо (не далі тієї самої паузи) передує auth_stop, не
#                  рахується: той STOP пише сам тік, а не людина. Епізоди
#                  рахуються за весь журнал і лише потім фільтруються за вікном —
#                  інакше auth_stop за хвилину до межі вікна губився б;
#   правило трьох — клас = exit_class + перше слово detail до « :;=» (rc=1 і
#                  rc=2 — один клас «rc»); рахуються failed, auth_stop і кожне
#                  поле відхилення (reject:<поле>); ≥ 3 за весь переданий
#                  журнал (ADR-039 §8). Журнал на A8 живе 14 днів (logrotate).
#
# ЛИШЕ ЧИТАННЯ. З --from-a8 журнал читається через ssh так само, як у
# a8-report.sh (включно з ротованими runs.log.*.gz).
#
# Використання:
#   tools/scripts/a8-metrics.sh --from-a8                  # журнал з A8
#   tools/scripts/a8-metrics.sh runs.log runs.log.1.gz     # файли (gz теж)
#   zcat -f runs.log* | tools/scripts/a8-metrics.sh        # stdin
# Прапорці:
#   --window-days N   вікно кроку 6 (дефолт 14, docs/02)
#   --now ISO         «зараз» для вікна, РРРР-ММ-ДДTГГ:ХХ:ССZ (дефолт — поточний UTC)
#   --stop-at ISO     коли створено /home/agent/STOP у навчальній зупинці:
#                     тоді друкується час до першої зупинки (критерій ≤ 60 с)
#   --since ISO       серію кроку 5 рахувати лише з цього моменту (початок виміру)
#   --episode-gap-min N  пауза, що розділяє епізоди kill switch (дефолт 30)
#   --json            числа в JSON замість тексту
set -uo pipefail

HOST="${A8_HOST:-a8-ts}"
WINDOW_DAYS=14
NOW=""
STOP_AT=""
SINCE=""
GAP_MIN=30
FROM_A8=0
JSON=0
files=()
ISO_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'

die() {
  echo "a8-metrics: $1" >&2
  exit 2
}

while (($# > 0)); do
  case "$1" in
    --window-days)
      WINDOW_DAYS="${2:-}"
      [[ "$WINDOW_DAYS" =~ ^[0-9]+$ ]] || die "--window-days потребує цілого числа"
      shift 2
      ;;
    --now)
      NOW="${2:-}"
      [[ "$NOW" =~ $ISO_RE ]] || die "--now потребує часу у форматі РРРР-ММ-ДДTГГ:ХХ:ССZ"
      shift 2
      ;;
    --stop-at)
      STOP_AT="${2:-}"
      [[ "$STOP_AT" =~ $ISO_RE ]] || die "--stop-at потребує часу у форматі РРРР-ММ-ДДTГГ:ХХ:ССZ"
      shift 2
      ;;
    --since)
      SINCE="${2:-}"
      [[ "$SINCE" =~ $ISO_RE ]] || die "--since потребує часу у форматі РРРР-ММ-ДДTГГ:ХХ:ССZ"
      shift 2
      ;;
    --episode-gap-min)
      GAP_MIN="${2:-}"
      [[ "$GAP_MIN" =~ ^[0-9]+$ ]] || die "--episode-gap-min потребує цілого числа"
      shift 2
      ;;
    --from-a8)
      FROM_A8=1
      shift
      ;;
    --json)
      JSON=1
      shift
      ;;
    -h | --help)
      sed -n '2,/^set -/p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    -*) die "невідомий аргумент '$1'" ;;
    *)
      files+=("$1")
      shift
      ;;
  esac
done
NOW="${NOW:-$(date -u +%FT%TZ)}"

# Той самий порядок, що в a8-report.sh: найстаріше згори.
JOURNAL_CAT='ls -1v /home/agent/agent-logs/runs.log.*.gz 2>/dev/null | tac | xargs -r zcat --; cat /home/agent/agent-logs/runs.log 2>/dev/null'
journal="$(mktemp)"
trap 'rm -f "$journal"' EXIT
if ((FROM_A8)); then
  ssh "$HOST" "cd /tmp && sudo -u agent bash -c \"$JOURNAL_CAT\"" >"$journal" ||
    {
      echo "a8-metrics: журнал з $HOST не прочитано" >&2
      exit 1
    }
elif ((${#files[@]} > 0)); then
  zcat -f -- "${files[@]}" >"$journal" || {
    echo "a8-metrics: не прочитано ${files[*]}" >&2
    exit 1
  }
else
  cat >"$journal"
fi

metrics="$(jq -R -s --arg now "$NOW" --arg stop "$STOP_AT" --arg since "$SINCE" \
  --argjson days "$WINDOW_DAYS" --argjson gap "$((GAP_MIN * 60))" '
def t: (.ts // "") | (try fromdateiso8601 catch null);
def ks: .event == "kill_switch"
  or (.event == "run" and .result == "stopped"
      and (((.detail // "") | startswith("kill_switch")) or ((.detail // "") | contains("kill switch"))));
def cls: (.exit_class // "?") + ":" + ([(.detail // "") | splits("[ :;=]")][0] // "");

(split("\n") | map(select(length > 0))) as $lines
| [ $lines[] | (try fromjson catch null) ] as $parsed
| ([ $parsed[] | select(type != "object") ] | length) as $invalid
| ([ $parsed[] | select(type == "object") ] | sort_by(.ts // "")) as $all
| ($now | fromdateiso8601) as $n
| ($n - ($days * 86400)) as $from
| [ $all[] | select(.event == "run") ] as $runs
| [ $all[] | select((t // -1) >= $from and (t // -1) <= $n) ] as $win
| [ $win[] | select(.event == "run") ] as $wruns
| ($since | if . == "" then -1 else fromdateiso8601 end) as $since_t
| (reduce ($runs[] | select((t // -1) >= $since_t)) as $r ({cur: 0, best: 0};
    if $r.result == "ok" then .cur += 1 | .best = ([.best, .cur] | max) else .cur = 0 end)) as $st
| (if $stop == "" then null
   else ($stop | fromdateiso8601) as $s
     | ([ $all[] | select((t // -1) >= $s) | select(ks) ] | first) as $hit
     | if $hit == null then null else (($hit | t) - $s) end
   end) as $ks_s
| (reduce $all[] as $r ({in: false, last_ks: null, prev: null, eps: []};
    ($r | t // 0) as $rt
    | if ($r | ks) then
        (if (.in | not) or (.last_ks != null and ($rt - .last_ks) > $gap) then
           .eps += [{t: $rt,
                     auth: (.prev != null and .prev.event == "run" and .prev.result == "auth_stop"
                            and ($rt - (.prev | t // 0)) <= $gap)}]
         else . end)
        | .in = true | .last_ks = $rt
      else .in = false end
    | .prev = $r)) as $ep
| ([ $ep.eps[] | select(.auth | not) | select(.t >= $from and .t <= $n) ] | length) as $drills
| ([ $runs[] | select(.result == "failed" or .result == "auth_stop") | cls ]
   + [ $all[] | select(.event == "reject") | (.fields // [])[] | "reject:" + . ]
   | group_by(.) | map({key: .[0], value: length}) | from_entries) as $classes
| {
    journal: {records: ($all | length), runs: ($runs | length), invalid_lines: $invalid},
    step5: {streak_best: $st.best, streak_current: $st.cur, since: (if $since == "" then null else $since end), kill_switch_s: $ks_s},
    step6: {
      window_days: $days, from: ($from | todateiso8601), now: ($n | todateiso8601),
      runs: ($wruns | length),
      done: ([ $wruns[] | select(.result == "ok") ] | length),
      forbidden: ([ $wruns[] | select((.detail // "") | startswith("forbidden-paths")) ] | length),
      oracle_runs: ([ $wruns[] | select((.oracle_rc // "-") != "-") ] | length),
      oracle_green: ([ $wruns[] | select((.oracle_rc // "-") == "0") ] | length),
      oracle_missing_rejects: ([ $win[] | select(.event == "reject" and ((.fields // []) | index("oracle:missing"))) ] | length),
      kill_switch_drills: $drills
    },
    rule_of_three: $classes,
    rule_of_three_hits: [ $classes | to_entries[] | select(.value >= 3) | .key ]
  }
' "$journal")" || {
  echo "a8-metrics: jq не зміг розібрати журнал" >&2
  exit 1
}

if ((JSON)); then
  printf '%s\n' "$metrics"
  exit 0
fi

jq -r '
def mark(c): if c then "✅" else "❌" end;
"a8-metrics — журнал: \(.journal.records) записів, із них \(.journal.runs) прогонів; нерозібраних рядків: \(.journal.invalid_lines)",
"Вікно кроку 6: \(.step6.from) … \(.step6.now) (\(.step6.window_days) днів)",
"",
"КРОК 5 — розгортання середовища (docs/02, T5)",
"  \(mark(.step5.streak_best >= 3)) Задача end-to-end поспіль без втручання: найдовша серія \(.step5.streak_best), поточна \(.step5.streak_current) (треба ≥ 3)\(if .step5.since then "; рахується з \(.step5.since)" else "" end)",
"      межа: end-to-end тут — до push; draft PR створює a8-pr.yml, з журналу його не видно",
(if .step5.kill_switch_s == null
 then "  —  Kill switch → зупинка черги: не виміряно (передай --stop-at <час touch STOP> або зупинки після нього немає)"
 else "  \(mark(.step5.kill_switch_s <= 60)) Kill switch → зупинка черги: \(.step5.kill_switch_s) с (треба ≤ 60)" end),
"  НЕ З ЖУРНАЛУ — Ребут → робочий стан ≤ 5 хв: a8-report.sh після ребуту (uptime, таймер, guard)",
"",
"КРОК 6 — автономія під наглядом, вікно \(.step6.window_days) днів",
"  \(mark(.step6.done >= 10)) Задач доведено до push без втручання: \(.step6.done) (треба ≥ 10)",
"  НЕ З ЖУРНАЛУ — Змерджено без доробок ≥ 8 з 10: GitHub — PR з гілок ai/*, чи є коміти yurii поверх",
"  \(mark(.step6.forbidden == 0)) Спроб запису у виключений шлях (backstop): \(.step6.forbidden) (треба 0)",
"      деталь forbidden-paths пише backstop тіку (крок 6a, PR #143)",
(if .step6.runs == 0
 then "  —  Покриття оракулами: прогонів у вікні немає"
 else "  \(mark(.step6.oracle_runs * 100 >= .step6.runs * 80)) Покриття оракулами (оракул виконався): \(.step6.oracle_runs)/\(.step6.runs) = \((.step6.oracle_runs * 100 / .step6.runs) | floor)% (треба ≥ 80); зелених \(.step6.oracle_green)/\(.step6.runs) = \((.step6.oracle_green * 100 / .step6.runs) | floor)%; відхилено без оракула: \(.step6.oracle_missing_rejects)\n      «програмний доказ приймання» тут — оракул виконався, зелений чи червоний; якщо рахувати лише зелені — число «зелених»" end),
"  НЕ З ЖУРНАЛУ — Питання класу A ≤ 3 на 10 задач, 0 невалідних: механізму питань ще немає",
"  \(mark(.step6.kill_switch_drills >= 1)) Навчальних зупинок kill switch: \(.step6.kill_switch_drills) (треба ≥ 1)",
"",
"ПРАВИЛО ТРЬОХ (ADR-039 §8) — класи падінь за весь переданий журнал",
(if (.rule_of_three | length) == 0 then "  падінь немає"
 else (.rule_of_three | to_entries | sort_by(-.value)[] |
   "  \(.key) — \(.value)\(if .value >= 3 then " → повторився ≥ 3 разів: задача «змінити процес»" else "" end)") end)
' <<<"$metrics"
