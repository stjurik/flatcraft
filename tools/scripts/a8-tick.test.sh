#!/usr/bin/env bash
# a8-tick.test.sh — наскрізний доказ демона черги A8 (a8-tick) без A8.
#
# Що СПРАВЖНЄ: шаблон демона a8-tick.sh.j2, запобіжник a8-guard.sh.j2 і журнал
# a8-journal.sh.j2 (відрендерені з ролі), логіка a8-tick-logic.sh, git (локальний
# bare-репозиторій як origin), файлова черга.
# Що ПІДМІНЕНО: контейнер (a8-run-agent) і `docker kill`. Заглушка контейнера,
# як і справжня обгортка, СПЕРШУ викликає `a8-guard check` — інакше порядок
# «лічильник після запуску» був би недоведеним.
#
# Мутації в кінці: ламаємо демон по одному місцю — набір мусить почервоніти.
#
# Запуск: tools/scripts/a8-tick.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROLE="$HERE/../../infra/ansible/roles/a8/templates"
TICK_SRC="${A8_TICK_UNDER_TEST:-$ROLE/a8-tick.sh.j2}"
fail=0
say() { [[ -z "${QUIET:-}" ]] && echo "$@"; return 0; }
ok() { say "✓ $1"; }
bad() {
  echo "✗ $1"
  fail=1
}

# render <шаблон> <вихід> — лише прості підстановки, яких вистачає цим шаблонам.
render() {
  sed -e "s|{{ ansible_managed }}|test render|" \
    -e "s|{{ a8_config_dir }}|$ETC|g" \
    -e "s|{{ a8_logs_dir }}|$LOGS|g" \
    -e "s|{{ a8_consecutive_failure_limit }}|3|g" "$1" >"$2"
  chmod +x "$2"
}

setup() { # setup [денний ліміт]
  ROOT="$(mktemp -d)"
  ETC="$ROOT/etc" LOGS="$ROOT/logs" QD="$ROOT/queue" BIN="$ROOT/bin"
  mkdir -p "$ETC" "$LOGS" "$QD" "$BIN" "$ROOT/wt"
  cat >"$ETC/a8.env" <<ENV
A8_KILL_SWITCH=$ROOT/STOP
A8_DAILY_TASK_LIMIT=${1:-5}
A8_CONSECUTIVE_FAILURE_LIMIT=3
A8_LOGS_DIR=$LOGS
A8_QUEUE_DIR=$QD
A8_REPO_DIR=$ROOT/repo
A8_WORKTREES_DIR=$ROOT/wt
A8_TASK_TIMEOUT=${TASK_TIMEOUT:-20}
A8_ORACLE_TIMEOUT=${ORACLE_TIMEOUT:-20}
A8_MAX_TURNS=10
A8_DEFAULT_MODEL=sonnet
A8_CLAUDE_TOKEN_FILE=$ROOT/token
A8_PUSH_CREDENTIAL_KIND=${PUSH_KIND:-none}
A8_PUSH_SSH_URL=$ROOT/origin.git
A8_SOURCES_ALLOWED="${SOURCES_ALLOWED:-human}"
ENV
  echo "tok" >"$ROOT/token"
  render "$TICK_SRC" "$BIN/a8-tick"
  render "$ROLE/a8-guard.sh.j2" "$BIN/a8-guard"
  render "$ROLE/a8-journal.sh.j2" "$BIN/a8-journal"

  # origin = bare-репо з одним комітом; головний клон — як /home/agent/hart.
  git init -q --bare -b main "$ROOT/origin.git"
  git clone -q "$ROOT/origin.git" "$ROOT/seed" 2>/dev/null
  git -C "$ROOT/seed" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$ROOT/seed" push -q origin main
  git clone -q "$ROOT/origin.git" "$ROOT/repo"

  # Заглушка a8-run-agent. Поведінка — зі змінних AGENT_MODE / HOOK_RC.
  # Шлях журналу викликів ВШИТИЙ, а не зі змінної: A8_LOGS_DIR у середовище
  # заглушки не експортується, і перевірка «claude не викликано» мовчки
  # проходила б на відсутньому файлі (спіймано першим прогоном, docs/16 §8.1).
  cat >"$BIN/a8-run-agent" <<STUB
#!/usr/bin/env bash
CALLS="$LOGS/runner-calls"
STOPFILE="$ROOT/STOP"
STUB
  cat >>"$BIN/a8-run-agent" <<'STUB'
wt="$1"; shift
# `check-run`, як і справжня обгортка. Якби тут лишився `check`, тест зеленів
# би на демоні, який на останній задачі дня валить власний оракул кодом 11.
"$A8_GUARD" check-run >/dev/null 2>&1 || exit $?
echo "run-agent $*" >>"$CALLS"
if [[ "$*" == *check-hook-loud* ]]; then exit "${HOOK_RC:-0}"; fi
if [[ "$1" == pnpm || "$*" == *"uv sync"* ]]; then exit "${DEPS_RC:-0}"; fi
# Оракул приходить як `bash -c <текст>` і ВИКОНУЄТЬСЯ по-справжньому, у
# worktree. Заглушка, що відповідала б за нього кодом зі змінної, доводила б
# лише «рядок викликано»; нам потрібне «оракул червоніє на неправильній
# роботі», а це видно тільки на справжньому виконанні проти справжнього дерева.
if [[ "$1" == bash && "$2" == -c ]]; then
  (cd "$wt" && bash -c "$3")
  exit $?
fi
case "${AGENT_MODE:-commit}" in
  commit)
    git -C "$wt" -c user.email=a@a -c user.name=a commit -q --allow-empty -m work
    echo '{"type":"result","is_error":false,"result":"done"}' ;;
  work)
    # Робота, яку оракул може ПЕРЕВІРИТИ: без файла той самий оракул червоніє.
    echo MARKER >"$wt/result.txt"
    git -C "$wt" add result.txt
    git -C "$wt" -c user.email=a@a -c user.name=a commit -q -m work
    echo '{"type":"result","is_error":false,"result":"done"}' ;;
  stopafter)
    git -C "$wt" -c user.email=a@a -c user.name=a commit -q --allow-empty -m work
    touch "$STOPFILE"
    echo '{"type":"result","is_error":false,"result":"done"}' ;;
  nocommit) echo '{"type":"result","is_error":false,"result":"nothing"}' ;;
  fail) echo '{"type":"result","is_error":true,"result":"boom"}'; exit 1 ;;
  auth) echo '{"type":"result","is_error":true,"num_turns":1,"result":"Failed to authenticate. API Error: 401 Invalid bearer token"}'; exit 1 ;;
  paused) exit 12 ;;
  hang) sleep 30 ;;
esac
STUB
  chmod +x "$BIN/a8-run-agent"
  printf '#!/usr/bin/env bash\necho "docker $*" >>"%s/docker-calls"\n' "$LOGS" >"$BIN/docker"
  chmod +x "$BIN/docker"

  export A8_CONFIG="$ETC/a8.env" A8_TICK_LOGIC="$HERE/a8-tick-logic.sh"
  export A8_GUARD="$BIN/a8-guard" A8_RUNNER="$BIN/a8-run-agent"
  export A8_JOURNAL="$BIN/a8-journal" A8_DOCKER="$BIN/docker"
}
teardown() { rm -rf "$ROOT"; }

enqueue() { # enqueue <файл> <json>
  printf '%s\n' "$2" >"$QD/$1.json"
}
# Оракул за замовчуванням тривіально зелений: сценарії, що перевіряють ІНШЕ,
# не мають падати на ньому. Хто перевіряє сам оракул — задає його явно.
valid() { with_oracle "$1" true; }
with_oracle() { # with_oracle <id> <текст оракула>
  jq -nc --arg id "$1" --arg o "$2" \
    '{id:$id, source:"human", origin:"direction", oracle:$o, prompt:("do "+$id)}'
}
tick() { bash "$BIN/a8-tick" >>"$LOGS/tick.out" 2>&1; }
tick_rc() {
  local rc=0
  bash "$BIN/a8-tick" >>"$LOGS/tick.out" 2>&1 || rc=$?
  echo "$rc"
}
last() { tail -n 1 "$LOGS/runs.log"; }
jl() { jq -r "$1" <<<"$(last)"; }

run_scenarios() {
  # 1. Kill switch → окремий стан, задача лишається в черзі.
  setup
  enqueue 001-a "$(valid a)"
  touch "$ROOT/STOP"
  tick
  [[ "$(jl .event)" == kill_switch && -e "$QD/001-a.json" ]] && ok "kill switch → event kill_switch, задача ціла в черзі" ||
    bad "kill switch: $(last)"
  teardown

  # 2. Денний ліміт → інший стан, не злитий із паузою.
  setup 1
  echo 1 >"$LOGS/counter-$(date -u +%Y-%m-%d)"
  enqueue 001-a "$(valid a)"
  tick
  [[ "$(jl .event)" == daily_limit ]] && ok "денний ліміт → event daily_limit (не paused)" || bad "ліміт: $(last)"
  teardown

  # 3. Невалідний запис: відмова з назвою ПОЛЯ, валідний за ним — виконується.
  setup
  enqueue 001-bad '{"id":"bad","source":"human","origin":"direction","prompt":"p"}'
  enqueue 002-ext '{"id":"ext","source":"external","origin":"feedback","oracle":"x","prompt":"p"}'
  enqueue 003-good "$(valid good)"
  tick
  r1="$(grep '"event":"reject"' "$LOGS/runs.log" | head -1)"
  r2="$(grep '"event":"reject"' "$LOGS/runs.log" | sed -n 2p)"
  [[ "$(jq -c .fields <<<"$r1")" == '["oracle:missing"]' && -e "$QD/rejected/001-bad.json" ]] &&
    ok "без oracle → reject з fields [oracle:missing], файл у rejected/" || bad "reject oracle: $r1"
  [[ "$(jq -c .fields <<<"$r2")" == '["source:not-allowed"]' ]] &&
    ok "external у режимі (а) → reject з fields [source:not-allowed] — інше «ні»" || bad "reject external: $r2"
  [[ "$(jl .task)" == good ]] && ok "після відмов узято наступну валідну задачу" || bad "не взято good: $(last)"
  teardown

  # 3b. Режим OQ-34 береться з КОНФІГУ, а не лише з дефолту логіки: інакше
  # змінна ролі a8_sources_allowed була б мертвою. Контроль до сценарію 3.
  SOURCES_ALLOWED="human external" setup
  enqueue 001-ext '{"id":"ext","source":"external","origin":"feedback","oracle":"x","prompt":"p"}'
  tick
  [[ "$(jl .task)" == ext && "$(jl .event)" == run ]] &&
    ok "конфіг дозволяє external → задачу взято (налаштування ролі живе)" || bad "config sources: $(last)"
  teardown

  # 4. Успіх без креденшала → no-credential, не «ok»; журнал має всі поля.
  setup
  enqueue 001-a "$(valid a)"
  tick
  [[ "$(jl .result)" == no-credential && -e "$QD/done/001-a.json" ]] &&
    ok "агент ok, креденшала немає → result no-credential, задача в done/" || bad "no-cred: $(last)"
  [[ "$(jl '[.branch,.worktree,.oracle,.origin,.exit_class,.model]|map(length>0)|all')" == true && "$(jl .branch)" == ai/a ]] &&
    ok "журнал: branch, worktree, oracle, origin, exit_class, model заповнені" || bad "поля: $(last)"
  git -C "$ROOT/repo" rev-parse --verify -q refs/heads/ai/a >/dev/null &&
    ok "гілка ai/a створена від origin/main" || bad "немає гілки ai/a"
  teardown

  # 5. Ліміт 1: єдина задача дня мусить ВИКОНАТИСЬ (лічильник — після запуску).
  setup 1
  enqueue 001-a "$(valid a)"
  tick
  [[ "$(jl .result)" == no-credential ]] &&
    ok "ліміт 1 → остання задача дня виконується, обгортка не відмовляє кодом 11" || bad "ліміт 1: $(last)"
  teardown

  # 6. 401 → STOP усієї черги, задача повертається, падіння НЕ рахується.
  setup
  enqueue 001-a "$(valid a)"
  AGENT_MODE=auth tick
  [[ "$(jl .result)" == auth_stop && -s "$ROOT/STOP" && -e "$QD/001-a.json" ]] &&
    ok "401 → auth_stop, kill switch створено з причиною, задача повернута в чергу" || bad "401: $(last)"
  grep -q failed "$LOGS/last-results" 2>/dev/null && bad "401 записано як failed" ||
    ok "401 не зараховано в падіння поспіль"
  AGENT_MODE=auth tick
  [[ "$(jl .event)" == kill_switch ]] && ok "наступний тік після 401 — не retry, а kill_switch" || bad "retry після 401: $(last)"
  # Людина перелогінилась і зняла STOP: повернута задача мусить ВИКОНАТИСЬ, а не
  # упасти на «гілка вже існує» (знайдено незалежним рев'ю №2).
  rm -f "$ROOT/STOP"
  tick
  [[ "$(jl .result)" == no-credential && "$(jl .task)" == a ]] &&
    ok "після зняття STOP повернута задача виконується (порожню гілку прибрано)" || bad "requeue після 401: $(last)"
  teardown

  # 6b. Запобіжник спрацював в обгортці (код 12) → stopped, задача в черзі,
  # і наступний тік її виконує.
  setup
  enqueue 001-a "$(valid a)"
  AGENT_MODE=paused tick
  [[ "$(jl .result)" == stopped && "$(jl .detail)" == paused && -e "$QD/001-a.json" ]] &&
    ok "обгортка повернула 12 → stopped paused, задача в черзі, не failed" || bad "stopped: $(last)"
  grep -q failed "$LOGS/last-results" 2>/dev/null && bad "stopped записано як failed" || ok "stopped не зараховано в падіння"
  tick
  [[ "$(jl .result)" == no-credential ]] && ok "після stopped задача виконується наступним тіком" || bad "requeue після stopped: $(last)"
  teardown

  # 7. Пауза рівно на третьому падінні; четвертий тік — paused.
  setup
  for i in 1 2 3 4; do enqueue "00$i" "$(valid "f$i")"; done
  AGENT_MODE=fail tick
  AGENT_MODE=fail tick
  grep -q '"event":"paused"' "$LOGS/runs.log" && bad "пауза вже після двох" || ok "два падіння — паузи ще немає"
  AGENT_MODE=fail tick
  [[ "$(jl .event)" == paused ]] && ok "третє падіння → event paused" || bad "третє: $(last)"
  AGENT_MODE=fail tick
  [[ "$(jl .event)" == paused && -e "$QD/004.json" ]] && ok "четвертий тік: guard → paused, задача не взята" || bad "четвертий: $(last)"
  teardown

  # 7b. Guard звітує падіння ПОСПІЛЬ, а не «скільки failed у вікні».
  # Рішення в обох редакціях однакове; різниться ЧИСЛО, яке читає людина.
  # `failed failed ok` — стан, на якому стара редакція друкувала 2 при нулі
  # падінь поспіль; саме його yurii побачив 2026-09-20 після успішного прогону.
  setup
  printf 'failed\nfailed\nok\n' >"$LOGS/last-results"
  [[ "$("$BIN/a8-guard" check)" == *"падінь поспіль 0 з 3"* ]] &&
    ok "після успіху guard звітує 0 падінь поспіль (вікно давало б 2)" ||
    bad "звіт guard після успіху: $("$BIN/a8-guard" check)"
  # Контроль: без нього перевірка не відрізняє «рахує» від «завжди друкує 0».
  printf 'ok\nfailed\nfailed\n' >"$LOGS/last-results"
  [[ "$("$BIN/a8-guard" check)" == *"падінь поспіль 2 з 3"* ]] &&
    ok "два падіння в хвості → guard звітує 2" || bad "звіт guard: $("$BIN/a8-guard" check)"
  teardown

  # 7c. Контракт двох дієслів: check гейтить НАБІР задачі, check-run — лише
  # виконання. Без цього поділу оракул останньої задачі дня падав би кодом 11.
  setup 1
  echo 1 >"$LOGS/counter-$(date -u +%Y-%m-%d)"
  "$BIN/a8-guard" check >/dev/null 2>&1
  c_limit=$?
  "$BIN/a8-guard" check-run >/dev/null 2>&1
  r_limit=$?
  printf 'failed\nfailed\nfailed\n' >"$LOGS/last-results"
  "$BIN/a8-guard" check-run >/dev/null 2>&1
  r_paused=$?
  touch "$ROOT/STOP"
  "$BIN/a8-guard" check-run >/dev/null 2>&1
  r_stop=$?
  [[ "$c_limit" == 11 && "$r_limit" == 0 && "$r_paused" == 0 ]] &&
    ok "вичерпаний ліміт і пауза зупиняють check (11), але не check-run (0)" ||
    bad "дієслова guard: check=$c_limit check-run=$r_limit paused=$r_paused"
  [[ "$r_stop" == 10 ]] &&
    ok "kill switch зупиняє і check-run (10) — єдиний запобіжник на межі контейнера" ||
    bad "check-run при kill switch: $r_stop"
  teardown

  # 8. Агент «ok», але комітів немає → failed no-commits.
  setup
  enqueue 001-a "$(valid a)"
  AGENT_MODE=nocommit tick
  [[ "$(jl .detail)" == no-commits && "$(jl .result)" == failed ]] && ok "rc 0 без комітів → failed no-commits" || bad "no-commits: $(last)"
  teardown

  # 9. Сирота в running/ → failed orphan.
  setup
  mkdir -p "$QD/running"
  valid orph >"$QD/running/000-orph.json"
  tick
  o="$(grep '"detail":"orphan"' "$LOGS/runs.log")"
  [[ -n "$o" && -e "$QD/failed/000-orph.json" ]] && ok "сирота з обірваного тіку → failed orphan, файл у failed/" || bad "orphan: $(tail -3 "$LOGS/runs.log")"
  [[ "$(tail -n 1 "$LOGS/last-results" 2>/dev/null)" == failed ]] &&
    ok "сирота записана в last-results як failed (рахується до паузи)" || bad "orphan last-results: $(cat "$LOGS/last-results" 2>/dev/null)"
  grep -q 'docker kill a8-orph' "$LOGS/docker-calls" 2>/dev/null &&
    ok "сирота → контейнер a8-orph убито (міг працювати без нагляду)" || bad "orphan kill: $(cat "$LOGS/docker-calls" 2>/dev/null)"
  teardown

  # 9b. Класифікатор упав → failed, НЕ push і НЕ done (fail closed).
  setup
  enqueue 001-a "$(valid a)"
  cat >"$BIN/logic-broken-classify" <<EOF
#!/usr/bin/env bash
[[ "\$1" == classify ]] && exit 1
exec bash "$HERE/a8-tick-logic.sh" "\$@"
EOF
  A8_TICK_LOGIC="$BIN/logic-broken-classify" tick
  [[ "$(jl .result)" == failed && "$(jl .detail)" == classifier:* && ! -e "$QD/done/001-a.json" ]] &&
    ok "класифікатор упав → failed classifier, не done" || bad "classifier fail-open: $(last)"
  teardown

  # 10. Декоративний pre-commit → агент НЕ запускається.
  setup
  enqueue 001-a "$(valid a)"
  HOOK_RC=1 tick
  # Контроль: файл викликів ІСНУЄ (виклик check-hook-loud записано) — інакше
  # «claude не викликано» було б правдою з неправильної причини.
  [[ "$(jl .detail)" == hooks-decorative ]] && grep -q 'check-hook-loud' "$LOGS/runner-calls" &&
    ! grep -q 'claude' "$LOGS/runner-calls" &&
    ok "check-hook-loud ≠ 0 → failed hooks-decorative, claude не викликано" || bad "hooks: $(last)"
  teardown

  # 10b. Залежності не встановились → агент не запускається.
  setup
  enqueue 001-a "$(valid a)"
  DEPS_RC=1 tick
  [[ "$(jl .detail)" == deps ]] && grep -q 'pnpm install' "$LOGS/runner-calls" && ! grep -q 'claude' "$LOGS/runner-calls" &&
    ok "pnpm install/uv sync упали → failed deps, claude не викликано" || bad "deps: $(last)"
  teardown

  # 11. Таймаут → failed timeout І контейнер убито.
  TASK_TIMEOUT=1 setup
  enqueue 001-a "$(valid a)"
  AGENT_MODE=hang tick
  [[ "$(jl .detail)" == timeout ]] && grep -q 'docker kill a8-a' "$LOGS/docker-calls" 2>/dev/null &&
    ok "таймаут → failed timeout і docker kill a8-a" || bad "timeout: $(last); docker: $(cat "$LOGS/docker-calls" 2>/dev/null)"
  teardown

  # 12. Гілка з таким id уже є → не перезаписуємо.
  setup
  git -C "$ROOT/repo" branch ai/a origin/main
  enqueue 001-a "$(valid a)"
  tick
  [[ "$(jl .result)" == failed && "$(jl .detail)" == *"уже існує"* ]] && ok "наявна гілка ai/a → failed, не перезапис" || bad "branch exists: $(last)"
  teardown

  # 13. Два тіки одночасно: другий не бере задачу.
  setup
  enqueue 001-a "$(valid a)"
  flock "$LOGS/tick.lock" sleep 5 &
  holder=$!
  sleep 0.5
  tick
  [[ "$(jl .event)" == busy && -e "$QD/001-a.json" ]] && ok "lock зайнятий → event busy, задача не взята" || bad "flock: $(last)"
  wait "$holder"
  teardown

  # 14. worktree не створився → merge-base guard ловить до запуску агента.
  setup
  enqueue 001-a "$(valid a)"
  chmod 555 "$ROOT/wt"
  tick
  chmod 755 "$ROOT/wt"
  [[ "$(jl .detail)" == "worktree не на origin/main" ]] && ! grep -q claude "$LOGS/runner-calls" 2>/dev/null &&
    ok "worktree не на origin/main → failed до запуску агента" || bad "merge-base guard: $(last)"
  teardown

  # 15. fetch упав → failed git fetch.
  setup
  enqueue 001-a "$(valid a)"
  mv "$ROOT/origin.git" "$ROOT/origin.gone"
  tick
  [[ "$(jl .detail)" == "git fetch" ]] && ok "git fetch упав → failed git fetch" || bad "fetch: $(last)"
  mv "$ROOT/origin.gone" "$ROOT/origin.git"
  teardown

  # 16. guard повернув невідомий код → guard_error і НЕНУЛЬОВИЙ вихід тіку.
  setup
  printf '#!/usr/bin/env bash\nexit 1\n' >"$BIN/guard-broken"
  chmod +x "$BIN/guard-broken"
  enqueue 001-a "$(valid a)"
  rc="$(A8_GUARD="$BIN/guard-broken" tick_rc)"
  [[ "$rc" == 1 && "$(jl .event)" == guard_error ]] && ok "guard → 1 → event guard_error, тік виходить з 1" || bad "guard_error: rc=$rc $(last)"
  teardown

  # 17. Push — гілки коду, не механіка креденшала (його не існує).
  PUSH_KIND=token_file setup
  enqueue 001-a "$(valid a)"
  tick
  [[ "$(jl .result)" == ok && "$(jl .detail)" == pushed ]] && git -C "$ROOT/origin.git" rev-parse -q --verify refs/heads/ai/a >/dev/null &&
    ok "token_file: push у origin → ok pushed, гілка ai/a на origin" || bad "push token_file: $(last)"
  teardown
  PUSH_KIND=deploy_key setup
  enqueue 001-a "$(valid a)"
  tick
  [[ "$(jl .result)" == ok ]] && git -C "$ROOT/origin.git" rev-parse -q --verify refs/heads/ai/a >/dev/null &&
    ok "deploy_key: push на A8_PUSH_SSH_URL → ok" || bad "push deploy_key: $(last)"
  teardown
  PUSH_KIND=token_file setup
  enqueue 001-a "$(valid a)"
  chmod -R a-w "$ROOT/origin.git"
  tick
  chmod -R u+w "$ROOT/origin.git"
  [[ "$(jl .result)" == failed && "$(jl .detail)" == push ]] && ok "push відхилено → failed push, не ok" || bad "push fail: $(last)"
  teardown
  PUSH_KIND=weird setup
  enqueue 001-a "$(valid a)"
  tick
  [[ "$(jl .result)" == failed ]] && ok "невідомий A8_PUSH_CREDENTIAL_KIND → failed" || bad "unknown kind: $(last)"
  teardown

  # ─── 18. Оракул приймання ────────────────────────────────────────────────
  # Головна пара сценаріїв: ОДИН І ТОЙ САМИЙ оракул на двох різних результатах
  # агента. Якщо вердикт не розходиться — оракул нічого не доводить (docs/02
  # п.4: він мусить червоніти на НЕПРАВИЛЬНОМУ результаті, а не лише на
  # відсутньому). Перевіряти «оракул викликано» замість цього означало б
  # повторити помилку 2026-09-20.
  PUSH_KIND=token_file setup
  enqueue 001-a "$(with_oracle a 'grep -q MARKER result.txt')"
  AGENT_MODE=work tick
  [[ "$(jl .result)" == ok && "$(jl .oracle_rc)" == 0 ]] &&
    git -C "$ROOT/origin.git" rev-parse -q --verify refs/heads/ai/a >/dev/null &&
    ok "агент зробив роботу → оракул зелений (oracle_rc 0), гілка на origin" || bad "оракул на правильній роботі: $(last)"
  teardown

  PUSH_KIND=token_file setup
  enqueue 001-a "$(with_oracle a 'grep -q MARKER result.txt')"
  AGENT_MODE=commit tick
  [[ "$(jl .result)" == failed && "$(jl .detail)" == oracle* && "$(jl .oracle_rc)" != 0 ]] &&
    ok "той самий оракул на порожньому коміті → failed oracle" || bad "оракул на неправильній роботі: $(last)"
  git -C "$ROOT/origin.git" rev-parse -q --verify refs/heads/ai/a >/dev/null &&
    bad "червоний оракул: гілку все одно запушено на origin" ||
    ok "червоний оракул → на origin не запушено нічого"
  git -C "$ROOT/repo" rev-parse --verify -q refs/heads/ai/a >/dev/null && [[ -d "$ROOT/wt/a" ]] &&
    ok "червоний оракул: гілка і worktree збережені як доказ для людини" || bad "доказ прибрано"
  teardown

  # 18b. Задача, що впала ДО оракула, мусить відрізнятись у журналі від
  # прийнятої машиною: oracle_rc = «-», а не 0.
  setup
  enqueue 001-a "$(valid a)"
  AGENT_MODE=nocommit tick
  [[ "$(jl .oracle_rc)" == "-" ]] &&
    ok "падіння до оракула → oracle_rc «-» (не плутається із зеленим 0)" || bad "oracle_rc: $(last)"
  teardown

  # 18c. МЕЖА, заради якої розділялись дієслова guard'а: остання дозволена
  # задача дня. Лічильник уже інкрементовано, і зі старим `check` в обгортці
  # оракул отримував би 11 — тобто демон валив би задачу, яку агент виконав.
  PUSH_KIND=token_file setup 1
  enqueue 001-a "$(with_oracle a 'grep -q MARKER result.txt')"
  AGENT_MODE=work tick
  [[ "$(jl .result)" == ok && "$(jl .oracle_rc)" == 0 ]] &&
    ok "ліміт 1: оракул останньої задачі дня проганяється і зеленіє" || bad "оракул на межі ліміту: $(last)"
  teardown

  # 18d. Kill switch посеред задачі теж дає ненульовий код — але через
  # обгортку. Записати це як «червоний оракул» означало б звинуватити агента
  # в рішенні людини.
  PUSH_KIND=token_file setup
  enqueue 001-a "$(valid a)"
  AGENT_MODE=stopafter tick
  [[ "$(jl .result)" == stopped && "$(jl .detail)" == *"kill switch"* ]] &&
    ok "kill switch під час оракула → stopped, а не failed oracle" || bad "kill switch під час оракула: $(last)"
  grep -q failed "$LOGS/last-results" 2>/dev/null &&
    bad "зупинка людиною зарахована в падіння поспіль" || ok "зупинка людиною не зарахована в падіння"
  teardown
}

run_scenarios

if [[ -z "${A8_TICK_UNDER_TEST:-}" ]]; then
  # Мутанти незалежні (кожен прогін — власні mktemp-теки), тож ганяємо їх
  # паралельно: послідовно набір ішов би ~6 хв на кожен PR.
  MUTDIR="$(mktemp -d)"
  trap 'rm -rf "$MUTDIR"' EXIT
  n=0
  mutate() { # mutate <назва> <perl-вираз>
    n=$((n + 1))
    local m="$MUTDIR/$n.sh"
    echo "$1" >"$MUTDIR/$n.name"
    perl -0pe "$2" "$ROLE/a8-tick.sh.j2" >"$m"
    if cmp -s "$m" "$ROLE/a8-tick.sh.j2"; then
      echo "stale" >"$MUTDIR/$n.res"
      return
    fi
    if ! bash -n <(sed 's/{{[^}]*}}/x/g' "$m") 2>/dev/null; then
      echo "syntax" >"$MUTDIR/$n.res"
      return
    fi
    (
      if QUIET=1 A8_TICK_UNDER_TEST="$m" bash "$0" >/dev/null 2>&1; then
        echo "survived" >"$MUTDIR/$n.res"
      else
        echo "killed" >"$MUTDIR/$n.res"
      fi
    ) &
    # Не більше 6 одночасно.
    while (($(jobs -rp | wc -l) >= 6)); do sleep 0.2; done
  }
  mutate "лічильник ДО запуску" 's/rc=0\ntimeout/"\$GUARD" count >\/dev\/null\nrc=0\ntimeout/; s/\n"\$GUARD" count >\/dev\/null\n\n# ─── 6/\n\n# ─── 6/'
  mutate "контейнер не вбивається при таймауті" 's/\[\[ "\$rc" == 124 \]\] && "\$DOCKER" kill[^\n]*\n//'
  mutate "401 без kill switch" 's/"\$id" "\$\(date -u \+%FT%TZ\)" >"\$A8_KILL_SWITCH"/"\$id" "\$(date -u +%FT%TZ)" >\/dev\/null/'
  mutate "no-credential як ok" 's/finish no-credential ok/finish ok ok/'
  mutate "відхилений запис лишається в черзі" 's/  mv "\$f" "\$Q\/rejected\/"\n//'
  mutate "перевірку хука прибрано" 's/if ! "\$RUNNER" "\$wt" bash tools\/scripts\/check-hook-loud.sh >>"\$log" 2>&1; then/if false; then/'
  mutate "case без гілки за замовчуванням" 's/  ok\) ;;\n  \*\)\n(.*?\n)*?    ;;\n(esac)/$2/'
  mutate "сироту не вбито" 's/  \[\[ -n "\$oid" \]\] && "\$DOCKER" kill[^\n]*\n//'
  mutate "залежності не ставляться" 's/if ! "\$RUNNER" "\$wt" pnpm install --frozen-lockfile >>"\$log" 2>&1 \|\|\n  ! "\$RUNNER" "\$wt" bash -c [^\n]*\n/if false; then\n/'
  mutate "режим OQ-34 не експортовано" 's/\nexport A8_SOURCES_ALLOWED\n/\n/'
  mutate "flock прибрано" 's/flock -n 9 \|\| \{/true || {/'
  mutate "merge-base guard прибрано" 's/if \[\[ "\$\(git -C "\$wt" rev-parse HEAD 2>\/dev\/null\)" != [^\n]*\]\]; then/if false; then/'
  mutate "падіння fetch ігнорується" 's/if ! git -C "\$A8_REPO_DIR" fetch/if ! true || git -C "\$A8_REPO_DIR" fetch/'
  mutate "сирота не записана як failed" 's/  "\$GUARD" count >\/dev\/null\n  "\$GUARD" record failed\n/  "\$GUARD" count >\/dev\/null\n/'
  mutate "guard_error виходить з 0" 's/\[\[ "\$gstate" == guard_error \]\] && exit 1/[[ "\$gstate" == guard_error ]] \&\& exit 0/'
  mutate "stopped як failed" 's/  stopped\)\n    if release_or_keep; then/  stopped)\n    fail_task stopped; exit 0\n    if release_or_keep; then/'
  mutate "порожню гілку не прибрано" 's/  if \[\[ "\$\(git -C "\$A8_REPO_DIR" rev-list --count "origin\/main\.\.\$branch"[^\n]*\n    git -C "\$A8_REPO_DIR" worktree remove[^\n]*\n    git -C "\$A8_REPO_DIR" branch -D[^\n]*\n/  if true; then\n/'
  mutate "невідомий kind → ok" 's/    fail_task "невідомий A8_PUSH_CREDENTIAL_KIND"/    finish ok ok unknown done/'
  mutate "push не перевіряється" 's/git -C "\$wt" -c credential.helper= push origin/true || git -C "\$wt" -c credential.helper= push origin/'
  mutate "класифікатор на спільному лозі" 's/logic classify "\$rc" "\$out"/logic classify "\$rc" "\$log"/'
  mutate "оракул не проганяється" 's/timeout "\$A8_ORACLE_TIMEOUT" "\$RUNNER" "\$wt" bash -c "\$oracle" >>"\$log" 2>&1 \|\| orc=\$\?/orc=0/'
  mutate "червоний оракул ігнорується" 's/if \(\(orc != 0\)\); then/if false; then/'
  mutate "оракул після push" 's/(# ─── 6b\. Оракул(?:.*?\n)*?^fi\n\n)(# ─── 7\.)/$2/m'
  mutate "oracle_rc завжди зелений" 's/oracle_rc="\$orc"/oracle_rc=0/'
  mutate "kill switch під час оракула як червоний оракул" 's/  if \[\[ -e "\$A8_KILL_SWITCH" \]\]; then\n    finish stopped[^\n]*\n    exit 0\n  fi\n//'
  mutate "стани guard злиті в один" 's/"\$JOURNAL" event "\$gstate"/"\$JOURNAL" event stopped/'
  wait
  for i in $(seq 1 "$n"); do
    name="$(cat "$MUTDIR/$i.name")"
    case "$(cat "$MUTDIR/$i.res" 2>/dev/null)" in
      killed) ok "мутація «$name» убита" ;;
      survived) bad "мутація «$name» ВИЖИЛА — набір зелений на зламаному демоні" ;;
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
