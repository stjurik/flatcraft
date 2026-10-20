#!/usr/bin/env bash
# a8-queue.test.sh — наскрізний доказ a8-queue.sh і a8-ctl.sh без A8.
#
# ОБИДВА ТРАНСПОРТИ (рішення yurii 2026-10-20): кожен сценарій іде двічі — локальним
# викликом `a8-queue <дієслово>` і через ssh-обгортку `a8-ctl` з
# SSH_ORIGINAL_COMMAND, як її викликає sshd. Логіка мусить поводитись однаково; від
# транспорту залежить лише поле `via` у журналі викликів.
#
# Що СПРАВЖНЄ: a8-queue.sh, a8-ctl.sh, a8-tick-logic.sh (validate), a8-requeue.sh,
# a8-guard.sh.j2 і a8-journal.sh.j2 (відрендерені з ролі), git (bare origin і
# головний клон), файлова черга.
# Що ПІДМІНЕНО: лише sshd — його роль (покласти команду в SSH_ORIGINAL_COMMAND і
# передати stdin) грає функція call.
#
# Мутації в кінці: ламаємо скрипти по одному місцю — набір мусить почервоніти.
#
# Запуск: tools/scripts/a8-queue.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROLE="$HERE/../../infra/ansible/roles/a8/templates"
QUEUE="${A8_QUEUE_UNDER_TEST:-$HERE/a8-queue.sh}"
CTL="${A8_CTL_UNDER_TEST:-$HERE/a8-ctl.sh}"
fail=0
say() { [[ -z "${QUIET:-}" ]] && echo "$@"; return 0; }
ok() { say "✓ $1"; }
bad() {
  echo "✗ $1"
  fail=1
}

for f in "$QUEUE" "$CTL"; do
  if [[ ! -f "$f" ]]; then
    bad "немає $f — тест червоний без скрипта"
    echo "FAIL"
    exit 1
  fi
done

render() { # render <шаблон> <вихід>
  sed -e "s|{{ ansible_managed }}|test render|" \
    -e "s|{{ a8_config_dir }}|$ETC|g" \
    -e "s|{{ a8_logs_dir }}|$LOGS|g" \
    -e "s|{{ a8_consecutive_failure_limit }}|3|g" "$1" >"$2"
  chmod +x "$2"
}
gitc() { git -c user.email=t@t -c user.name=t "$@"; }

setup() {
  ROOT="$(mktemp -d)"
  ETC="$ROOT/etc" LOGS="$ROOT/logs" QD="$ROOT/queue" BIN="$ROOT/bin" WT="$ROOT/wt" REPO="$ROOT/repo"
  mkdir -p "$ETC" "$LOGS" "$BIN" "$WT" "$QD/running" "$QD/done" "$QD/failed" "$QD/rejected"
  cat >"$ETC/a8.env" <<ENV
A8_KILL_SWITCH=$ROOT/STOP
A8_DAILY_TASK_LIMIT=5
A8_CONSECUTIVE_FAILURE_LIMIT=3
A8_LOGS_DIR=$LOGS
A8_QUEUE_DIR=$QD
A8_REPO_DIR=$REPO
A8_WORKTREES_DIR=$WT
A8_SOURCES_ALLOWED="human"
ENV
  render "$ROLE/a8-guard.sh.j2" "$BIN/a8-guard"
  render "$ROLE/a8-journal.sh.j2" "$BIN/a8-journal"
  # Копії під тестом — виконувані, як після встановлення роллю (a8-ctl робить exec).
  cp "$QUEUE" "$BIN/a8-queue" && chmod +x "$BIN/a8-queue"
  cp "$CTL" "$BIN/a8-ctl" && chmod +x "$BIN/a8-ctl"

  git init -q --bare -b main "$ROOT/origin.git"
  git clone -q "$ROOT/origin.git" "$ROOT/seed" 2>/dev/null
  echo contract >"$ROOT/seed/CLAUDE.md"
  git -C "$ROOT/seed" add -A
  gitc -C "$ROOT/seed" commit -q -m init
  git -C "$ROOT/seed" push -q origin main 2>/dev/null
  git clone -q "$ROOT/origin.git" "$REPO"

  export A8_CONFIG="$ETC/a8.env" A8_JOURNAL="$BIN/a8-journal" A8_GUARD="$BIN/a8-guard"
  export A8_TICK_LOGIC="$HERE/a8-tick-logic.sh" A8_REQUEUE="$HERE/a8-requeue.sh"
  export A8_QUEUE_BIN="$BIN/a8-queue"
  unset A8_CTL_VIA SSH_ORIGINAL_COMMAND
}
teardown() {
  pkill -9 -f "$ROOT/" 2>/dev/null
  rm -rf "$ROOT"
}

# call <дієслово> [аргументи…] — виклик через транспорт $MODE; stdin — далі.
# Результат: $OUT, $ERR, $RC.
call() {
  RC=0
  if [[ "$MODE" == local ]]; then
    "$BIN/a8-queue" "$@" >"$ROOT/out" 2>"$ROOT/err" || RC=$?
  else
    SSH_ORIGINAL_COMMAND="$*" "$BIN/a8-ctl" >"$ROOT/out" 2>"$ROOT/err" || RC=$?
  fi
  OUT="$(cat "$ROOT/out")" ERR="$(cat "$ROOT/err")"
}
# call_raw <рядок> — лише ssh: команда як є, без розбиття на аргументи.
call_raw() {
  RC=0
  SSH_ORIGINAL_COMMAND="$1" "$BIN/a8-ctl" >"$ROOT/out" 2>"$ROOT/err" </dev/null || RC=$?
  OUT="$(cat "$ROOT/out")" ERR="$(cat "$ROOT/err")"
}

task() { # task <id> [поле=значення ігнорується] — валідний запис
  jq -nc --arg id "$1" '{id:$id, source:"human", origin:"direction", oracle:"true", prompt:("do "+$id)}'
}
qfiles() { find "$QD" -maxdepth 1 -name '*.json' -printf '%f\n' | LC_ALL=C sort; }
leftovers() { find "$QD" "$QD/urgent" -maxdepth 1 -name '.enqueue.*' 2>/dev/null | wc -l; }
lastctl() { tail -n 1 "$LOGS/ctl.log" 2>/dev/null; }
ctl() { jq -r "$1" <<<"$(lastctl)"; }
events() { grep -c "\"event\":\"$1\"" "$LOGS/runs.log" 2>/dev/null || true; }

run_suite() { # run_suite <local|ssh>
  MODE="$1"
  local T="[$MODE]"

  # 1. status на порожній черзі.
  setup
  call status </dev/null
  [[ "$RC" == 0 && "$OUT" == *"STOP: немає"* && "$OUT" == *"черга: urgent=0 planned=0 running=0"* && "$OUT" == *"плановий потік: працює"* ]] &&
    ok "$T status на порожній черзі → 0, STOP немає, черга 0, потік працює" || bad "$T status: rc=$RC $OUT $ERR"
  [[ "$(ctl .verb)" == status && "$(ctl .via)" == "$MODE" && "$(ctl .rc)" == 0 ]] &&
    ok "$T status → рядок у ctl.log (via=$MODE, rc=0)" || bad "$T ctl.log status: $(lastctl)"
  teardown

  # 2. enqueue валідного запису: у черзі, 0644, байт-у-байт, подія, журнал.
  setup
  task a1 >"$ROOT/in.json"
  call enqueue <"$ROOT/in.json"
  f="$(qfiles)"
  [[ "$RC" == 0 && "$f" == *-a1.json && "$(grep -c . <<<"$f")" == 1 ]] &&
    ok "$T enqueue валідного → 0, один файл *-a1.json у корені черги" || bad "$T enqueue: rc=$RC files=[$f] $ERR"
  [[ -n "$f" ]] && cmp -s "$ROOT/in.json" "$QD/$f" && [[ "$(stat -c %a "$QD/$f")" == 644 ]] &&
    ok "$T файл у черзі — байт-у-байт той, що прийшов, права 0644" || bad "$T вміст/права: $(stat -c %a "$QD/$f" 2>/dev/null)"
  [[ "$(events enqueue)" == 1 && "$(ctl .verb)" == enqueue && "$(ctl .ids)" == a1 && "$(ctl .rc)" == 0 ]] &&
    ok "$T подія enqueue у runs.log і рядок ctl.log з id" || bad "$T журнали enqueue: $(lastctl)"
  [[ "$(leftovers)" == 0 ]] && ok "$T тимчасових файлів не лишилось" || bad "$T лишились .enqueue.*"
  # 3. Той самий id удруге — відмова.
  call enqueue <"$ROOT/in.json"
  [[ "$RC" == 1 && "$(qfiles | grep -c .)" == 1 && "$ERR" == *"уже є в черзі"* ]] &&
    ok "$T той самий id удруге → 1, у черзі як і було один" || bad "$T дублікат: rc=$RC $(qfiles) $ERR"
  teardown

  # 4. Невалідний запис — відмова з назвою поля, у черзі нічого.
  setup
  jq -nc '{id:"b1", source:"human", origin:"direction", prompt:"p"}' >"$ROOT/in.json"
  call enqueue <"$ROOT/in.json"
  [[ "$RC" == 1 && -z "$(qfiles)" && "$ERR" == *"oracle:missing"* && "$(leftovers)" == 0 ]] &&
    ok "$T без оракула → 1, oracle:missing, у черзі нічого" || bad "$T невалідний: rc=$RC $(qfiles) $ERR"
  [[ "$(ctl .rc)" == 1 && "$(ctl .detail)" == *"oracle:missing"* ]] &&
    ok "$T відмова записана в ctl.log з причиною" || bad "$T ctl.log відмови: $(lastctl)"
  # source external у режимі (а) — теж відмова (режим з конфігу).
  jq -nc '{id:"b2", source:"external", origin:"feedback", oracle:"x", prompt:"p"}' >"$ROOT/in.json"
  call enqueue <"$ROOT/in.json"
  [[ "$RC" == 1 && -z "$(qfiles)" && "$ERR" == *"source:not-allowed"* ]] &&
    ok "$T external у режимі (а) → 1, source:not-allowed" || bad "$T external: rc=$RC $ERR"
  # Не JSON, порожньо, завеликий запис.
  call enqueue <<<'not json'
  [[ "$RC" == 1 && -z "$(qfiles)" ]] && ok "$T не JSON → 1" || bad "$T не JSON: rc=$RC"
  call enqueue </dev/null
  [[ "$RC" == 1 && -z "$(qfiles)" ]] && ok "$T порожній stdin → 1" || bad "$T порожній: rc=$RC"
  jq -nc --arg p "$(head -c 70000 /dev/zero | tr '\0' x)" '{id:"b3", source:"human", origin:"direction", oracle:"true", prompt:$p}' >"$ROOT/in.json"
  call enqueue <"$ROOT/in.json"
  [[ "$RC" == 1 && -z "$(qfiles)" && "$(leftovers)" == 0 ]] && ok "$T запис > 64 КіБ → 1, нічого не лишилось" || bad "$T завеликий: rc=$RC"
  # Короткий валідний запис і 70 000 пробілів за ним: обрізаний на 64 КіБ, він
  # лишається валідним JSON, тож відхилити його може лише ліміт розміру, а не
  # валідація (без цього кейсу мутант «розмір не обмежено» виживав).
  { task b4; head -c 70000 /dev/zero | tr '\0' ' '; } >"$ROOT/in.json"
  call enqueue <"$ROOT/in.json"
  [[ "$RC" == 1 && -z "$(qfiles)" && "$ERR" == *"довший за"* ]] && ok "$T валідний JSON + хвіст пробілів > 64 КіБ → 1 саме через ліміт" ||
    bad "$T ліміт розміру: rc=$RC $(qfiles) $ERR"
  teardown

  # 5. id, у якого вже є гілка ai/<id> — тік на ній упав би.
  setup
  git -C "$REPO" branch ai/c1 origin/main
  call enqueue < <(task c1)
  [[ "$RC" == 1 && -z "$(qfiles)" && "$ERR" == *"гілка ai/c1"* ]] &&
    ok "$T гілка ai/<id> уже є → 1" || bad "$T гілка: rc=$RC $ERR"
  # id у failed/ чи done/ — теж зайнятий.
  task c2 >"$QD/done/c2.json"
  call enqueue < <(task c2)
  [[ "$RC" == 1 && "$ERR" == *"(done)"* ]] && ok "$T id уже в done/ → 1" || bad "$T done: rc=$RC $ERR"
  teardown

  # 6. --urgent: в urgent/, лише одна одночасно.
  setup
  call enqueue --urgent < <(task u1)
  u="$(find "$QD/urgent" -maxdepth 1 -name '*.json' -printf '%f\n')"
  [[ "$RC" == 0 && "$u" == urgent-*-u1.json && -z "$(qfiles)" ]] &&
    ok "$T enqueue --urgent → urgent/urgent-…-u1.json, корінь порожній" || bad "$T urgent: rc=$RC [$u] $ERR"
  call enqueue --urgent < <(task u2)
  [[ "$RC" == 1 && "$ERR" == *"лише одна"* ]] && ok "$T друга невідкладна, поки перша чекає → 1" || bad "$T друга urgent: rc=$RC $ERR"
  mv "$QD/urgent/$u" "$QD/running/"
  call enqueue --urgent < <(task u3)
  [[ "$RC" == 1 && "$ERR" == *"виконується"* ]] && ok "$T невідкладна, поки інша виконується → 1" || bad "$T urgent у running: rc=$RC $ERR"
  call enqueue < <(task p1)
  [[ "$RC" == 0 ]] && ok "$T планова, поки йде невідкладна → 0" || bad "$T планова поруч з urgent: rc=$RC $ERR"
  teardown

  # 7. pause / resume: подія лише при зміні стану.
  setup
  call pause </dev/null
  [[ "$RC" == 0 && -e "$LOGS/planned-paused" && "$(events planned_paused)" == 1 ]] &&
    ok "$T pause → прапорець і одна подія planned_paused" || bad "$T pause: rc=$RC $ERR"
  call pause </dev/null
  [[ "$RC" == 0 && "$(events planned_paused)" == 1 ]] && ok "$T повторний pause → без нової події" || bad "$T pause двічі: $(events planned_paused)"
  call status </dev/null
  [[ "$OUT" == *"плановий потік: ПАУЗА"* ]] && ok "$T status показує паузу планового потоку" || bad "$T status паузи: $OUT"
  call resume </dev/null
  [[ "$RC" == 0 && ! -e "$LOGS/planned-paused" && "$(events planned_resumed)" == 1 ]] &&
    ok "$T resume → прапорця немає, одна подія planned_resumed" || bad "$T resume: rc=$RC"
  call resume </dev/null
  [[ "$RC" == 0 && "$(events planned_resumed)" == 1 ]] && ok "$T повторний resume → без нової події" || bad "$T resume двічі"
  teardown

  # 8. requeue — через a8-requeue.sh: порожня впала задача повертається, невідома — SKIP.
  setup
  task r1 >"$QD/failed/001-r1.json"
  call requeue r1 </dev/null
  [[ "$RC" == 0 && -e "$QD/001-r1.json" && ! -e "$QD/failed/001-r1.json" ]] &&
    ok "$T requeue r1 → задача з failed/ у черзі" || bad "$T requeue: rc=$RC $OUT $ERR"
  [[ "$(ctl .verb)" == requeue && "$(ctl .ids)" == r1 && "$(ctl .rc)" == 0 ]] && ok "$T requeue → рядок ctl.log з id" || bad "$T ctl requeue: $(lastctl)"
  call requeue nope </dev/null
  [[ "$RC" == 1 && "$OUT" == *"SKIP nope"* ]] && ok "$T requeue невідомого id → 1, SKIP" || bad "$T requeue nope: rc=$RC $OUT"
  # Гілка з комітами — робота, а не залишок: a8-requeue її не чіпає.
  task r2 >"$QD/failed/001-r2.json"
  git -C "$REPO" worktree add -q -b ai/r2 "$WT/r2" origin/main
  gitc -C "$WT/r2" commit -q --allow-empty -m work
  call requeue r2 </dev/null
  [[ "$RC" == 1 && -e "$QD/failed/001-r2.json" && "$OUT" == *"комітів"* ]] &&
    ok "$T requeue задачі з комітами → SKIP, гілка ціла" || bad "$T requeue з комітами: rc=$RC $OUT"
  teardown

  # 9. Аргументи поза контрактом — відмова, нічого не змінено.
  setup
  call requeue --remote x </dev/null
  [[ "$RC" == 2 && "$ERR" == *"невідомий прапорець '--remote'"* ]] && ok "$T requeue --remote → 2, до a8-requeue не дійшло" || bad "$T requeue --remote: rc=$RC $ERR"
  call enqueue extra < <(task e1)
  [[ ( "$RC" == 2 || "$RC" == 126 ) && -z "$(qfiles)" ]] && ok "$T enqueue з аргументом → відмова, у черзі нічого" || bad "$T enqueue arg: rc=$RC"
  call status now </dev/null
  [[ "$RC" == 2 || "$RC" == 126 ]] && ok "$T status з аргументом → відмова" || bad "$T status arg: rc=$RC"
  teardown
}

# Лише ssh: усе, що не одне з п'яти дієслів чи містить метасимвол, відхиляє a8-ctl
# — до a8-queue, і без оболонки. Кожна відмова — рядок у ctl.log.
run_ssh_only() {
  MODE=ssh
  setup
  local c
  for c in "" "   " "bash" "sh -i" "rm -rf /" "status; touch $ROOT/pwned" "status && touch $ROOT/pwned" \
    "status | touch $ROOT/pwned" "\$(touch $ROOT/pwned)" "\`touch $ROOT/pwned\`" "status > $ROOT/pwned" \
    "_denied x" "requeue ../../etc" $'status\ntouch '"$ROOT/pwned" "enqueue --urgent'"; do
    call_raw "$c"
    if [[ "$RC" != 126 || -e "$ROOT/pwned" ]]; then
      bad "[ssh] «${c//$'\n'/\\n}» → rc=$RC (треба 126), pwned=$([[ -e "$ROOT/pwned" ]] && echo так || echo ні)"
    fi
  done
  [[ ! -e "$ROOT/pwned" ]] && ok "[ssh] метасимволи, оболонка, невідомі дієслова → 126, нічого не виконано" || bad "[ssh] щось виконалось"
  # requeue ../../etc проходить алфавіт, тож це a8-queue/a8-requeue — 1 чи 2; решта — 126.
  n_denied="$(grep -c '"verb":"denied"' "$LOGS/ctl.log" 2>/dev/null || true)"
  ((n_denied >= 13)) && ok "[ssh] кожна відмова a8-ctl записана в ctl.log (verb=denied, via=ssh): $n_denied" ||
    bad "[ssh] відмов у ctl.log: ${n_denied:-0}"
  [[ "$(grep '"verb":"denied"' "$LOGS/ctl.log" | jq -r .via | sort -u)" == ssh ]] && ok "[ssh] відмови мають via=ssh" || bad "[ssh] via відмов"
  teardown
}

for m in local ssh; do run_suite "$m"; done
run_ssh_only

# ─── Мутації ────────────────────────────────────────────────────────────────
# Контроль перед мутаціями: на червоному базисі кожен мутант «вбитий» за визначенням.
if [[ -z "${A8_QUEUE_UNDER_TEST:-}${A8_CTL_UNDER_TEST:-}" && "$fail" -ne 0 ]]; then
  echo
  echo "✗ мутації НЕ ганялись: базовий набір червоний (див. ✗ вище)."
elif [[ -z "${A8_QUEUE_UNDER_TEST:-}${A8_CTL_UNDER_TEST:-}" ]]; then
  MUTDIR="$(mktemp -d)"
  trap 'rm -rf "$MUTDIR"' EXIT
  n=0
  mutate() { # mutate <queue|ctl> <назва> <perl-вираз>
    n=$((n + 1))
    local src var m="$MUTDIR/$n.sh"
    if [[ "$1" == queue ]]; then src="$QUEUE" var=A8_QUEUE_UNDER_TEST; else src="$CTL" var=A8_CTL_UNDER_TEST; fi
    echo "$2" >"$MUTDIR/$n.name"
    perl -0pe "$3" "$src" >"$m"
    if cmp -s "$m" "$src"; then
      echo stale >"$MUTDIR/$n.res"
      return
    fi
    if ! bash -n "$m" 2>/dev/null; then
      echo syntax >"$MUTDIR/$n.res"
      return
    fi
    (
      if env QUIET=1 "$var=$m" bash "$0" >/dev/null 2>&1; then
        echo survived >"$MUTDIR/$n.res"
      else
        echo killed >"$MUTDIR/$n.res"
      fi
    ) &
    while (($(jobs -rp | wc -l) >= 6)); do sleep 0.2; done
  }
  mutate queue "enqueue без валідації" 's/verdict="\$\(bash "\$LOGIC" validate "\$tmp"\)" \|\|/verdict=ok ||/'
  mutate queue "enqueue пише поза чергу" 's/  dest="\$tmpdir\/\$name"/  dest="\$A8_LOGS_DIR\/\$name"/'
  mutate queue "дублікат id приймається" 's/  \[\[ -z "\$where" \]\] \|\| die 1/  true || die 1/'
  mutate queue "гілка ai\/<id> не перевіряється" 's/if git -C "\$A8_REPO_DIR" show-ref --verify --quiet "refs\/heads\/ai\/\$id"/if false/'
  mutate queue "невідкладних кілька" 's/    if \[\[ "\$\(count_json "\$URGENT"\)" != 0 \]\]; then/    if false; then/'
  mutate queue "--urgent у плановий потік" 's/    tmpdir="\$URGENT"/    tmpdir="\$Q"/'
  mutate queue "pause пише подію щоразу" 's/  if \[\[ -e "\$PAUSE_FLAG" \]\]; then\n    log_detail="already"/  if false; then\n    log_detail="already"/'
  mutate queue "журнал викликів не пишеться" 's/\ntrap ctl_log EXIT\n/\n/'
  mutate queue "via не з транспорту" 's/\[\[ "\$VIA" == ssh \]\] \|\| VIA=local/VIA=local/'
  mutate queue "requeue пропускає будь-які прапорці" 's/      -\*\) die 2 "requeue: невідомий прапорець/      -*) flags+=("\$a") ;; -NEVER) die 2 "requeue: невідомий прапорець/'
  mutate queue "розмір запису не обмежено" 's/\(\(size <= MAX_TASK_BYTES\)\) \|\| die 1/true || die 1/'
  mutate ctl "a8-ctl виконує команду оболонкою" 's/exec "\$QUEUE" "\$\{argv\[@\]\}"/exec bash -c "\$cmd"/'
  mutate ctl "a8-ctl пропускає метасимволи" 's/\[\[ "\$cmd" =~ \^\[A-Za-z0-9\._\\ -\]\+\$ \]\] \|\| deny/true || deny/'
  mutate ctl "a8-ctl пропускає будь-яке дієслово" 's/  status \| enqueue \| requeue \| pause \| resume\) ;;\n  \*\) deny/  *) ;;\n  NEVER) deny/'
  mutate ctl "a8-ctl не записує відмову" 's/  A8_CTL_VIA=ssh "\$QUEUE" _denied "\$1" <\/dev\/null >\/dev\/null 2>&1\n//'
  wait
  for i in $(seq 1 "$n"); do
    name="$(cat "$MUTDIR/$i.name")"
    case "$(cat "$MUTDIR/$i.res" 2>/dev/null)" in
      killed) ok "мутація «$name» убита" ;;
      survived) bad "мутація «$name» ВИЖИЛА — набір зелений на зламаному скрипті" ;;
      stale) bad "мутація «$name» нічого не змінила — вираз застарів" ;;
      syntax) bad "мутація «$name» ламає синтаксис — некоректна, а не вбита" ;;
      *) bad "мутація «$name» — результату немає" ;;
    esac
  done
fi

if [[ "$fail" -eq 1 ]]; then
  echo "FAIL"
  exit 1
fi
say "Усі тести пройдено."
exit 0
