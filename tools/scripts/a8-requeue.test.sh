#!/usr/bin/env bash
# a8-requeue.test.sh — наскрізний доказ a8-requeue.sh без A8.
#
# Що СПРАВЖНЄ: сам скрипт, a8-guard.sh.j2 і a8-journal.sh.j2 (відрендерені з
# ролі), git (локальний bare-репозиторій як origin, головний клон, справжні
# worktree), файлова черга, flock на tick.lock.
# Що ПІДМІНЕНО: лише `ssh` і `scp` у сценарії --remote (заглушки пишуть кожен
# виклик у файл, тож перевіряється, що саме скрипт намагався зробити на хості).
#
# Тест червоніє без скрипта (одразу, до сценаріїв). Мутації в кінці: ламаємо
# скрипт по одному місцю — набір мусить почервоніти.
#
# Запуск: tools/scripts/a8-requeue.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROLE="$HERE/../../infra/ansible/roles/a8/templates"
SCRIPT="${A8_REQUEUE_UNDER_TEST:-$HERE/a8-requeue.sh}"
fail=0
say() { [[ -z "${QUIET:-}" ]] && echo "$@"; return 0; }
ok() { say "✓ $1"; }
bad() {
  echo "✗ $1"
  fail=1
}

if [[ ! -f "$SCRIPT" ]]; then
  bad "немає $SCRIPT — тест червоний без скрипта"
  echo "FAIL"
  exit 1
fi

# render <шаблон> <вихід> — лише прості підстановки, яких вистачає цим шаблонам.
render() {
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
ENV
  render "$ROLE/a8-guard.sh.j2" "$BIN/a8-guard"
  render "$ROLE/a8-journal.sh.j2" "$BIN/a8-journal"

  # origin = bare-репо з одним комітом; головний клон — як репозиторій на A8.
  # node_modules в .gitignore: ігнорований вміст worktree не робить його брудним.
  git init -q --bare -b main "$ROOT/origin.git"
  git clone -q "$ROOT/origin.git" "$ROOT/seed" 2>/dev/null
  echo 'node_modules/' >"$ROOT/seed/.gitignore"
  echo contract >"$ROOT/seed/CLAUDE.md"
  git -C "$ROOT/seed" add -A
  gitc -C "$ROOT/seed" commit -q -m init
  git -C "$ROOT/seed" push -q origin main
  git clone -q "$ROOT/origin.git" "$REPO"

  export A8_CONFIG="$ETC/a8.env" A8_JOURNAL="$BIN/a8-journal" A8_GUARD="$BIN/a8-guard"
}
teardown() {
  # Утримувач lock'а, якщо лишився: у його рядку запуску є $ROOT.
  pkill -9 -f "$ROOT/" 2>/dev/null
  rm -rf "$ROOT"
}

mkfailed() { # mkfailed <id> [ім'я файла без .json] — задача у failed/
  jq -nc --arg id "$1" '{id:$id, source:"human", origin:"direction", oracle:"true", prompt:("do "+$id)}' \
    >"$QD/failed/${2:-001-$1}.json"
}
mkbranch() { # mkbranch <id> — гілка ai/<id> і worktree від origin/main, як у тіку
  git -C "$REPO" worktree add -q -b "ai/$1" "$WT/$1" origin/main
}
commit_in() { gitc -C "$WT/$1" commit -q --allow-empty -m work; }
mkrun() { # mkrun <id> <result> — запис запуску в runs.log, як пише a8-journal append
  jq -nc --arg t "$1" --arg r "$2" '{ts:"2026-10-12T10:00:00Z", event:"run", task:$t, source:"human", result:$r, duration_s:1, model:"sonnet", note:""}' \
    >>"$LOGS/runs.log"
}
noop_journal() { # журнал-заглушка, що нічого не пише (runs.log лишається таким, яким його підготував тест)
  printf '#!/bin/sh\nexit 0\n' >"$BIN/noop-journal"
  chmod +x "$BIN/noop-journal"
}
branch_exists() { git -C "$REPO" show-ref --verify --quiet "refs/heads/ai/$1"; }
registered() { git -C "$REPO" worktree list --porcelain | grep -qx "worktree $WT/$1"; }
run_rq() { OUT="$(bash "$SCRIPT" "$@" 2>&1)"; RC=$?; }
last() { tail -n 1 "$LOGS/runs.log" 2>/dev/null; }
# Відбиток усього, що скрипт міг би змінити: черга (імена й вміст), гілки, worktree,
# журнали. tick.lock виключено — його створює сам lock.
fingerprint() {
  {
    find "$QD" -type f -printf '%P\n' | sort
    find "$QD" -type f -print0 | sort -z | xargs -0 -r md5sum
    git -C "$REPO" for-each-ref --format='%(refname) %(objectname)' refs/heads
    git -C "$REPO" worktree list --porcelain
    find "$WT" -mindepth 1 | sort
    ls -A "$LOGS" | grep -v '^tick.lock$'
    cat "$LOGS/last-results" 2>/dev/null
    cat "$LOGS/runs.log" 2>/dev/null
  } 2>&1 | md5sum
}
hold_lock() { # утримувач tick.lock у фоні; повертає 0, коли lock справді зайнятий
  flock -x "$LOGS/tick.lock" sleep 30 &
  HOLDER=$!
  local i
  for i in $(seq 1 50); do
    flock -n "$LOGS/tick.lock" true 2>/dev/null || return 0
    sleep 0.1
  done
  return 1
}
release_lock() {
  pkill -P "$HOLDER" 2>/dev/null
  kill "$HOLDER" 2>/dev/null
  wait "$HOLDER" 2>/dev/null
}
guard_rc() { "$A8_GUARD" check >/dev/null 2>&1; echo $?; }

run_scenarios() {
  # 1. Успіх: гілка й worktree прибрано, файл у черзі, подія в журналі.
  setup
  mkfailed a
  mkbranch a
  mkdir -p "$WT/a/node_modules" && echo x >"$WT/a/node_modules/pkg" # ігнорований вміст
  cp "$QD/failed/001-a.json" "$ROOT/a.orig"
  printf '%s\n' ok failed >"$LOGS/last-results"
  cp "$LOGS/last-results" "$ROOT/lr.orig"
  if branch_exists a; then
    git -C "$REPO" worktree add -q -b ai/a "$WT/a" origin/main 2>/dev/null &&
      bad "передумова: гілка ai/a мала б блокувати повторне створення (як у тіку)" ||
      ok "до requeue повторне створення гілки ai/a падає (проблема з тіком відтворена)"
  fi
  run_rq a
  [[ $RC -eq 0 && "$OUT" == *"OK a:"* ]] && ok "успіх → код 0 і рядок OK a" || bad "успіх: rc=$RC $OUT"
  ! branch_exists a && [[ ! -e "$WT/a" ]] && ! registered a &&
    ok "гілку ai/a, теку worktree і реєстрацію прибрано" || bad "залишки гілки/worktree: $(ls "$WT")"
  [[ -f "$QD/001-a.json" && ! -e "$QD/failed/001-a.json" ]] && cmp -s "$QD/001-a.json" "$ROOT/a.orig" &&
    ok "файл задачі переїхав з failed/ у чергу без змін вмісту" || bad "файл задачі: $(find "$QD" -name '*.json')"
  [[ "$(jq -r .event <<<"$(last)")" == requeue && "$(jq -r .detail <<<"$(last)")" == a ]] &&
    ok "журнал: подія requeue з id" || bad "журнал: $(last)"
  cmp -s "$LOGS/last-results" "$ROOT/lr.orig" && ok "без --reset-pause last-results не чіпається" ||
    bad "last-results змінено без прапорця"
  [[ -z "$(ls "$LOGS" | grep 'bak-')" ]] && ok "без --reset-pause копії last-results немає" || bad "зайва копія"
  git -C "$REPO" worktree add -q -b ai/a "$WT/a" origin/main 2>/dev/null &&
    ok "після requeue тік зміг би створити гілку й worktree знову" || bad "після requeue гілку створити не можна"
  teardown

  # 1b. Залишків немає (задача впала на fetch): все одно OK; і лише гілка / стара реєстрація.
  setup
  mkfailed n
  mkfailed g
  mkbranch g
  mkfailed s
  mkbranch s
  rm -rf "$WT/s" # теки немає, реєстрація worktree лишилась — гілку без prune не видалити
  run_rq n g s
  [[ $RC -eq 0 && "$OUT" == *"OK n:"* && "$OUT" == *"OK g:"* && "$OUT" == *"OK s:"* ]] &&
    ok "без залишків / із гілкою / зі старою реєстрацією worktree → усі OK" || bad "залишки: rc=$RC $OUT"
  ! branch_exists g && ! branch_exists s && [[ -e "$QD/001-n.json" && -e "$QD/001-g.json" && -e "$QD/001-s.json" ]] &&
    ok "гілки прибрано, три файли в черзі" || bad "стан після трьох OK"
  teardown

  # 2. Гілка з комітом — чиясь робота: SKIP, нічого не прибрано.
  setup
  mkfailed b
  mkbranch b
  commit_in b
  fp="$(fingerprint)"
  run_rq b
  [[ $RC -eq 1 && "$OUT" == *"SKIP b:"* && "$OUT" == *"на гілці ai/b"* ]] &&
    ok "гілка з комітом → SKIP з причиною, код 1" || bad "гілка з комітом: rc=$RC $OUT"
  [[ "$(fingerprint)" == "$fp" ]] && ok "SKIP нічого не змінив (гілка, worktree, черга, журнал)" || bad "стан змінено після SKIP"
  teardown

  # 2b. Коміт лише на відокремленому HEAD worktree: гілка порожня, статус чистий.
  setup
  mkfailed d
  mkbranch d
  git -C "$WT/d" checkout -q --detach
  commit_in d
  fp="$(fingerprint)"
  run_rq d
  [[ $RC -eq 1 && "$OUT" == *"SKIP d:"* && "$OUT" == *"HEAD"* && "$(fingerprint)" == "$fp" ]] &&
    ok "коміт на відокремленому HEAD → SKIP, роботу не втрачено" || bad "відокремлений HEAD: rc=$RC $OUT"
  teardown

  # 2c. Коміти гілки вже влито в origin/main (після останнього fetch): свіжий fetch → OK.
  setup
  mkfailed m
  mkbranch m
  commit_in m
  git -C "$WT/m" push -q origin HEAD:main
  run_rq m
  [[ $RC -eq 0 && "$OUT" == *"OK m:"* ]] && ! branch_exists m &&
    ok "гілку влито в origin/main → скрипт fetch-ить і повертає задачу" || bad "влита гілка: rc=$RC $OUT"
  teardown

  # 2c-bis. Гілка з комітом, а worktree вже немає: інших ознак роботи, крім гілки, нема.
  setup
  mkfailed z
  mkbranch z
  commit_in z
  git -C "$REPO" worktree remove --force "$WT/z"
  fp="$(fingerprint)"
  run_rq z
  [[ $RC -eq 1 && "$OUT" == *"на гілці ai/z"* && "$(fingerprint)" == "$fp" ]] && branch_exists z &&
    ok "гілка з комітом без worktree → SKIP, гілка ціла" || bad "гілка без worktree: rc=$RC $OUT"
  teardown

  # 2d. Помилка rev-list — SKIP, а не «0 комітів»: у гілці немає проміжного об'єкта.
  setup
  mkfailed q
  mkbranch q
  commit_in q
  commit_in q
  c1="$(git -C "$WT/q" rev-parse HEAD~1)"
  rm -f "$REPO/.git/objects/${c1:0:2}/${c1:2}"
  # Worktree прибрано, щоб перевірка гілки не прикривалась перевіркою HEAD у теці.
  rm -rf "$WT/q"
  git -C "$REPO" worktree prune
  fp="$(fingerprint)"
  run_rq q
  [[ $RC -eq 1 && "$OUT" == *"SKIP q:"* && "$OUT" == *"rev-list"* && "$(fingerprint)" == "$fp" ]] && branch_exists q &&
    ok "rev-list не вдався → SKIP, гілку не видалено" || bad "помилка rev-list: rc=$RC $OUT"
  teardown

  # 2e. git show-ref падає з іншим кодом, ніж «гілки немає» (1): SKIP, а не «гілки немає».
  # Заглушка git у PATH: справжній показ такої помилки ламає й fetch, тож інакше її не відтворити.
  setup
  mkfailed c
  mkbranch c
  mkdir -p "$ROOT/stub-git"
  printf '#!/usr/bin/env bash\ncase "$*" in *show-ref*) echo "fatal: заглушка" >&2; exit 128 ;; esac\nexec %s "$@"\n' \
    "$(command -v git)" >"$ROOT/stub-git/git"
  chmod +x "$ROOT/stub-git/git"
  fp="$(fingerprint)"
  OUT="$(PATH="$ROOT/stub-git:$PATH" bash "$SCRIPT" c 2>&1)"
  RC=$?
  [[ $RC -eq 1 && "$OUT" == *"SKIP c:"* && "$OUT" == *"show-ref"* && "$(fingerprint)" == "$fp" ]] &&
    ok "show-ref упав (не «гілки немає») → SKIP, нічого не прибрано" || bad "show-ref: rc=$RC $OUT"
  teardown

  # 3. Брудний worktree: невідстежений і змінений відстежений файл.
  setup
  mkfailed u
  mkbranch u
  echo new >"$WT/u/new.txt"
  mkfailed t
  mkbranch t
  echo edited >"$WT/t/CLAUDE.md"
  fp="$(fingerprint)"
  run_rq u t
  [[ $RC -eq 1 && "$OUT" == *"SKIP u:"* && "$OUT" == *"SKIP t:"* && "$OUT" == *"брудний"* ]] &&
    ok "брудний worktree (невідстежений і змінений файл) → SKIP" || bad "брудний: rc=$RC $OUT"
  [[ "$(fingerprint)" == "$fp" && -f "$WT/u/new.txt" ]] && ok "робота у worktree збережена" || bad "брудний worktree зачеплено"
  teardown

  # 4. Задачі немає у failed/: невідомий id, id лише в done/, чужий id у failed/.
  setup
  mkfailed other
  mkbranch other
  cp "$QD/failed/001-other.json" "$QD/done/001-x.json"
  jq '.id="x"' "$QD/done/001-x.json" >"$ROOT/x.json" && mv "$ROOT/x.json" "$QD/done/001-x.json"
  fp="$(fingerprint)"
  run_rq nothere x
  [[ $RC -eq 1 && "$OUT" == *"SKIP nothere:"* && "$OUT" == *"SKIP x:"* && "$OUT" == *"немає задачі"* ]] &&
    ok "id немає у failed/ (чи лише в done/) → SKIP" || bad "немає в failed: rc=$RC $OUT"
  [[ "$(fingerprint)" == "$fp" ]] && ok "чужа задача у failed/ і її гілка не зачеплені" || bad "чужу задачу зачеплено"
  teardown

  # 4b. Іншу задачу цього ж каталогу не чіпаємо; id порівнюється по полю, не по імені файла.
  setup
  mkfailed a 001-zzz
  mkbranch a
  mkfailed b 002-a
  mkbranch b
  run_rq a
  [[ $RC -eq 0 && -e "$QD/001-zzz.json" && -e "$QD/failed/002-a.json" ]] && branch_exists b &&
    ok "файл знайдено за полем .id (не за назвою); сусідня задача лишилась у failed/" || bad "пошук за id: rc=$RC $OUT"
  teardown

  # 4c. Два файли з одним id у failed/: не знаю, який повертати.
  setup
  mkfailed j 001-j
  mkfailed j 002-j
  fp="$(fingerprint)"
  run_rq j
  [[ $RC -eq 1 && "$OUT" == *"SKIP j:"* && "$OUT" == *"2 файлів"* && "$(fingerprint)" == "$fp" ]] &&
    ok "два файли з одним id у failed/ → SKIP" || bad "два файли: rc=$RC $OUT"
  teardown

  # 5. Той самий id у running/ (і лишній файл у failed/ теж є).
  setup
  mkfailed r
  mkbranch r
  jq -nc '{id:"r", source:"human", origin:"direction", oracle:"true", prompt:"p"}' >"$QD/running/001-r.json"
  fp="$(fingerprint)"
  run_rq r
  [[ $RC -eq 1 && "$OUT" == *"SKIP r:"* && "$OUT" == *"running/"* && "$(fingerprint)" == "$fp" ]] &&
    ok "той самий id у running/ → SKIP, нічого не змінено" || bad "running: rc=$RC $OUT"
  teardown

  # 5b. Файл у running/, який не розібрати, міг бути цією задачею: fail closed.
  setup
  mkfailed r
  echo '{не json' >"$QD/running/001-broken.json"
  run_rq r
  [[ $RC -eq 1 && "$OUT" == *"SKIP r:"* && "$OUT" == *"не розібрано"* && -e "$QD/failed/001-r.json" ]] &&
    ok "нерозібраний файл у running/ → SKIP (fail closed)" || bad "нерозібраний running: rc=$RC $OUT"
  teardown

  # 5c. Задача з цим id уже в черзі; і інший файл із такою самою назвою.
  setup
  mkfailed k
  jq -nc '{id:"k", source:"human", origin:"direction", oracle:"true", prompt:"p"}' >"$QD/005-k.json"
  mkfailed m 001-m
  mkbranch m
  jq -nc '{id:"zzz", source:"human", origin:"direction", oracle:"true", prompt:"p"}' >"$QD/001-m.json"
  fp="$(fingerprint)"
  run_rq k m
  [[ $RC -eq 1 && "$OUT" == *"SKIP k:"* && "$OUT" == *"уже в черзі"* && "$OUT" == *"SKIP m:"* && "$OUT" == *"вже є файл 001-m.json"* ]] &&
    ok "id уже в черзі і збіг назви файла → SKIP (перезапис не відбувся)" || bad "черга: rc=$RC $OUT"
  [[ "$(fingerprint)" == "$fp" ]] && ok "файли в черзі не затерто" || bad "чергу змінено"
  teardown

  # 6. Lock зайнятий (тік працює): 3 і без змін; навіть для --dry-run.
  setup
  mkfailed a
  mkbranch a
  fp="$(fingerprint)"
  if hold_lock; then
    run_rq a
    [[ $RC -eq 3 ]] && ok "тік тримає lock → код 3" || bad "lock: rc=$RC $OUT"
    run_rq --dry-run a
    [[ $RC -eq 3 ]] && ok "і для --dry-run: lock важить до будь-яких перевірок" || bad "lock+dry: rc=$RC $OUT"
    release_lock
    [[ "$(fingerprint)" == "$fp" ]] && ok "при зайнятому lock нічого не змінено" || bad "lock: стан змінено"
  else
    bad "утримувач lock не взяв tick.lock"
    release_lock
  fi
  teardown

  # 6b. Lock тримається ДО КІНЦЯ: у момент requeue його знову не взяти.
  setup
  mkfailed a
  mkbranch a
  # Журнал-заглушка перевіряє, що lock усе ще зайнятий, коли вже все зроблено.
  cat >"$BIN/probe-journal" <<STUB
#!/usr/bin/env bash
flock -n "$LOGS/tick.lock" true && echo FREE >"$ROOT/lock-state" || echo HELD >"$ROOT/lock-state"
exit 0
STUB
  chmod +x "$BIN/probe-journal"
  A8_JOURNAL="$BIN/probe-journal" run_rq a
  [[ "$(cat "$ROOT/lock-state" 2>/dev/null)" == HELD ]] &&
    ok "lock тримається, поки скрипт працює (журнал бачить його зайнятим)" || bad "lock відпущено завчасно: $(cat "$ROOT/lock-state" 2>/dev/null)"
  teardown

  # 7. --dry-run: усі перевірки, жодних змін.
  setup
  mkfailed a
  mkbranch a
  mkfailed b
  mkbranch b
  echo dirty >"$WT/b/x"
  mkrun b failed
  mkrun a failed
  printf '%s\n' ok failed failed >"$LOGS/last-results"
  fp="$(fingerprint)"
  run_rq --dry-run --reset-pause a b
  [[ $RC -eq 1 && "$OUT" == *"WOULD a:"* && "$OUT" == *"SKIP b:"* && "$OUT" == *"WOULD reset-pause:"* && "$OUT" == *"прибрав би 1 з 1"* ]] &&
    ok "--dry-run: WOULD для придатної, SKIP для брудної, WOULD reset-pause" || bad "dry-run: rc=$RC $OUT"
  [[ "$(fingerprint)" == "$fp" ]] && ok "--dry-run нічого не змінив (черга, гілки, worktree, last-results, журнал)" || bad "dry-run змінив стан"
  run_rq --dry-run a
  [[ $RC -eq 0 ]] && ! grep -q '"event":"requeue"' "$LOGS/runs.log" && ok "--dry-run без SKIP → код 0, подій requeue немає" || bad "dry-run чистий: rc=$RC"
  teardown

  # 8. --reset-pause. Знімаються лише падіння, які runs.log приписує ПОВЕРНЕНИМ задачам.
  # (а) `ok failed failed failed`, повернуто a і b (їхні падіння — два останні) → `ok failed`.
  setup
  mkfailed a
  mkbranch a
  mkfailed b
  mkbranch b
  mkrun o ok
  mkrun z failed
  mkrun a failed
  mkrun b failed
  printf '%s\n' ok failed failed failed >"$LOGS/last-results"
  cp "$LOGS/last-results" "$ROOT/lr.orig"
  [[ "$(guard_rc)" == 12 ]] && ok "передумова: три failed в кінці → a8-guard check дає 12 (пауза)" || bad "передумова паузи: $(guard_rc)"
  run_rq --reset-pause a b
  [[ $RC -eq 0 && "$(tr '\n' ' ' <"$LOGS/last-results")" == "ok failed " ]] &&
    ok "повернуто a і b → з «ok failed failed failed» лишається «ok failed»" || bad "reset (а): rc=$RC $(cat "$LOGS/last-results")"
  baks=("$LOGS"/last-results.bak-*)
  [[ ${#baks[@]} -eq 1 && -f "${baks[0]}" ]] && cmp -s "${baks[0]}" "$ROOT/lr.orig" &&
    ok "копія last-results.bak-<час> з початковим вмістом" || bad "копія: ${baks[*]}"
  [[ "$OUT" == *"прибрано 2 з 2"* && "$OUT" == *"a8-guard check → код 0"* ]] &&
    ok "друкує, скільки прибрано, і результат a8-guard check (пауза знята)" || bad "вивід reset: $OUT"
  teardown

  # (б) `failed ok failed`: лік зупиняє ok у runs.log → прибрано лише 1.
  setup
  mkfailed a
  mkfailed b
  mkrun a failed
  mkrun o ok
  mkrun b failed
  printf '%s\n' failed ok failed >"$LOGS/last-results"
  run_rq --reset-pause a b
  [[ "$(tr '\n' ' ' <"$LOGS/last-results")" == "failed ok " && "$OUT" == *"прибрано 1 з 1"* ]] &&
    ok "«failed ok failed»: ok у runs.log зупиняє лік → прибрано лише 1" || bad "reset (б): $(cat "$LOGS/last-results") / $OUT"
  teardown

  # (в) паузу дали a, b, c; повернуто всі три → прибрано 3, пауза знята.
  setup
  mkfailed a
  mkfailed b
  mkfailed c
  mkrun a failed
  mkrun b failed
  mkrun c failed
  printf '%s\n' failed failed failed >"$LOGS/last-results"
  run_rq --reset-pause a b c
  [[ ! -s "$LOGS/last-results" && "$(guard_rc)" == 0 && "$OUT" == *"прибрано 3 з 3"* ]] &&
    ok "повернуто a, b, c (усі три падіння) → прибрано 3, a8-guard check знову 0" || bad "reset (в): $(cat "$LOGS/last-results") / $OUT"
  teardown

  # (в-1) паузу дали a, b, c; повертаємо СТАРУ задачу x → нічого не знято, пауза лишається.
  setup
  mkfailed x
  mkrun x failed
  mkrun o ok
  mkrun a failed
  mkrun b failed
  mkrun c failed
  printf '%s\n' failed ok failed failed failed >"$LOGS/last-results"
  cp "$LOGS/last-results" "$ROOT/lr.orig"
  run_rq --reset-pause x
  cmp -s "$LOGS/last-results" "$ROOT/lr.orig" && [[ -z "$(ls "$LOGS" | grep 'bak-')" && "$(guard_rc)" == 12 && "$OUT" == *"не приписує"* ]] &&
    ok "повернуто стару x, паузу дали a, b, c → last-results не чіпається, пауза лишається" || bad "reset (в-1): $(cat "$LOGS/last-results") / $OUT"
  teardown

  # (в-2) те саме, повернуто лише c → знято 1, лишаються два (пауза знята, 2 < 3).
  setup
  mkfailed c
  mkrun o ok
  mkrun a failed
  mkrun b failed
  mkrun c failed
  printf '%s\n' ok failed failed failed >"$LOGS/last-results"
  run_rq --reset-pause c
  [[ "$(tr '\n' ' ' <"$LOGS/last-results")" == "ok failed failed " && "$OUT" == *"прибрано 1 з 1"* && "$(guard_rc)" == 0 ]] &&
    ok "повернуто лише c → знято 1 (лишились a і b), a8-guard check 0" || bad "reset (в-2): $(cat "$LOGS/last-results") / $OUT"
  teardown

  # (г) K рахує лише повернуті: a повернуто, b (з комітом) — SKIP, його падіння не знімається.
  setup
  mkfailed a
  mkfailed b
  mkbranch b
  commit_in b
  mkrun b failed
  mkrun a failed
  printf '%s\n' failed failed >"$LOGS/last-results"
  run_rq --reset-pause a b
  [[ $RC -eq 1 && "$(tr '\n' ' ' <"$LOGS/last-results")" == "failed " && "$OUT" == *"прибрано 1 з 1"* ]] &&
    ok "SKIP не рахується: повернуто лише a → прибрано один рядок failed" || bad "reset (г): rc=$RC $(cat "$LOGS/last-results") / $OUT"
  teardown

  # (д) нічого не повернуто → last-results не чіпається, копії немає.
  setup
  printf '%s\n' failed failed >"$LOGS/last-results"
  cp "$LOGS/last-results" "$ROOT/lr.orig"
  run_rq --reset-pause nothere
  [[ $RC -eq 1 ]] && cmp -s "$LOGS/last-results" "$ROOT/lr.orig" && [[ -z "$(ls "$LOGS" | grep 'bak-')" ]] &&
    [[ "$OUT" == *"жодної задачі не повернуто"* ]] &&
    ok "нічого не повернуто → last-results і копії не існує" || bad "reset (д): $OUT"
  teardown

  # (е) без прапорця при поверненій задачі last-results не чіпається, хоч runs.log її падіння знає.
  setup
  mkfailed a
  mkrun a failed
  printf '%s\n' ok failed failed >"$LOGS/last-results"
  cp "$LOGS/last-results" "$ROOT/lr.orig"
  run_rq a
  cmp -s "$LOGS/last-results" "$ROOT/lr.orig" && [[ -z "$(ls "$LOGS" | grep 'bak-')" ]] &&
    ok "без --reset-pause рядки failed лишаються" || bad "last-results без прапорця змінено"
  teardown

  # (є) рядки з \r і порожні рядки в кінці: нормалізація як в a8-guard.
  setup
  mkfailed a
  mkfailed b
  mkrun a failed
  mkrun b failed
  printf 'ok\r\nfailed\r\nfailed \r\n\n' >"$LOGS/last-results"
  run_rq --reset-pause a b
  [[ "$(tr -d '\r' <"$LOGS/last-results" | tr '\n' ' ')" == "ok " && "$OUT" == *"прибрано 2 з 2"* ]] &&
    ok "«failed\\r», «failed » і порожній рядок розпізнаються, як у гвардії" || bad "reset (є): $(od -c "$LOGS/last-results" | head -3) / $OUT"
  teardown

  # (ж) last-results немає: не падаємо.
  setup
  mkfailed a
  run_rq --reset-pause a
  [[ $RC -eq 0 && "$OUT" == *"прибирати нічого"* && ! -e "$LOGS/last-results" ]] &&
    ok "без last-results --reset-pause нічого не вигадує" || bad "reset (ж): rc=$RC $OUT"
  teardown

  # (з) runs.log немає: невідомо, чиї падіння, — не знімається нічого.
  setup
  mkfailed a
  noop_journal
  printf '%s\n' failed failed failed >"$LOGS/last-results"
  cp "$LOGS/last-results" "$ROOT/lr.orig"
  A8_JOURNAL="$BIN/noop-journal" run_rq --reset-pause a
  cmp -s "$LOGS/last-results" "$ROOT/lr.orig" && [[ "$OUT" == *"runs.log — не знаю"* && -z "$(ls "$LOGS" | grep 'bak-')" ]] &&
    ok "немає runs.log → last-results не чіпається, причину названо" || bad "reset (з): $OUT"
  teardown

  # (и) нерозбірний рядок у кінці runs.log — на ньому лік упирається: нічого не знімається.
  setup
  mkfailed a
  mkrun a failed
  echo '{не json' >>"$LOGS/runs.log"
  printf '%s\n' failed failed failed >"$LOGS/last-results"
  cp "$LOGS/last-results" "$ROOT/lr.orig"
  run_rq --reset-pause a
  cmp -s "$LOGS/last-results" "$ROOT/lr.orig" && [[ "$OUT" == *"не розібрано"* ]] &&
    ok "нерозбірний рядок у runs.log → last-results не чіпається, причину названо" || bad "reset (и): $OUT"
  teardown

  # (к) runs.log знає більше падінь, ніж лишилось у кінці last-results: знімається min(лік, кінцевих failed).
  setup
  mkfailed a
  mkfailed b
  mkrun a failed
  mkrun b failed
  printf '%s\n' failed ok failed >"$LOGS/last-results"
  run_rq --reset-pause a b
  [[ "$(tr '\n' ' ' <"$LOGS/last-results")" == "failed ok " && "$OUT" == *"прибрано 1 з 2"* ]] &&
    ok "лік 2, а в кінці last-results один failed → прибрано 1, ok зупиняє" || bad "reset (к): $(cat "$LOGS/last-results") / $OUT"
  teardown

  # 9. fetch не вдався → 2, нічого не змінено.
  setup
  mkfailed a
  mkbranch a
  git -C "$REPO" remote set-url origin "$ROOT/немає.git"
  fp="$(fingerprint)"
  run_rq a
  [[ $RC -eq 2 && "$OUT" == *fetch* && "$OUT" != *"OK a:"* && "$(fingerprint)" == "$fp" ]] &&
    ok "fetch не вдався → код 2, нічого не змінено" || bad "fetch: rc=$RC $OUT"
  teardown

  # 10. Помилки використання і конфігу → 2.
  setup
  run_rq
  [[ $RC -eq 2 ]] && ok "без id → код 2" || bad "без id: rc=$RC"
  run_rq --nope a
  [[ $RC -eq 2 ]] && ok "невідомий аргумент → код 2" || bad "невідомий аргумент: rc=$RC"
  run_rq ../x
  [[ $RC -eq 2 ]] && ok "id зі шляхом (../x) → код 2" || bad "id ../x: rc=$RC"
  run_rq a..b
  [[ $RC -eq 2 ]] && ok "id з «..» → код 2" || bad "id a..b: rc=$RC"
  run_rq 'a/b'
  [[ $RC -eq 2 ]] && ok "id з «/» → код 2" || bad "id a/b: rc=$RC"
  A8_CONFIG="$ROOT/немає.env" run_rq a
  [[ $RC -eq 2 ]] && ok "немає конфігу → код 2" || bad "без конфігу: rc=$RC"
  grep -v '^A8_WORKTREES_DIR=' "$ETC/a8.env" >"$ETC/short.env"
  A8_CONFIG="$ETC/short.env" run_rq a
  [[ $RC -eq 2 && "$OUT" == *A8_WORKTREES_DIR* ]] && ok "у конфігу немає A8_WORKTREES_DIR → код 2 з назвою змінної" || bad "неповний конфіг: rc=$RC $OUT"
  run_rq --help
  [[ $RC -eq 0 && "$OUT" == *"--reset-pause"* && "$OUT" == *"Використання"* ]] && ok "--help друкує шапку" || bad "--help: rc=$RC"
  teardown

  # 11. Worktree, який не можна чіпати.
  # (а) тека є, але не worktree цього репозиторію.
  setup
  mkfailed g
  mkdir -p "$WT/g" && echo keep >"$WT/g/file"
  fp="$(fingerprint)"
  run_rq g
  [[ $RC -eq 1 && "$OUT" == *"SKIP g:"* && "$OUT" == *"не зареєстрований"* && -f "$WT/g/file" && "$(fingerprint)" == "$fp" ]] &&
    ok "звичайна тека замість worktree → SKIP, вміст цілий" || bad "не worktree: rc=$RC $OUT"
  teardown
  # (б) симлінк.
  setup
  mkfailed h
  mkdir -p "$ROOT/elsewhere" && echo keep >"$ROOT/elsewhere/file"
  ln -s "$ROOT/elsewhere" "$WT/h"
  run_rq h
  [[ $RC -eq 1 && "$OUT" == *"SKIP h:"* && "$OUT" == *"символічне"* && -f "$ROOT/elsewhere/file" && -L "$WT/h" ]] &&
    ok "симлінк замість теки worktree → SKIP, ціль ціла" || bad "симлінк: rc=$RC $OUT"
  teardown
  # (в) заблокований worktree.
  setup
  mkfailed i
  mkbranch i
  git -C "$REPO" worktree lock "$WT/i"
  fp="$(fingerprint)"
  run_rq i
  [[ $RC -eq 1 && "$OUT" == *"SKIP i:"* && "$OUT" == *"заблоковано"* && "$(fingerprint)" == "$fp" ]] &&
    ok "заблокований worktree → SKIP" || bad "lock worktree: rc=$RC $OUT"
  teardown
  # (г) гілка відкрита в іншому worktree, власного немає.
  setup
  mkfailed f
  git -C "$REPO" worktree add -q -b ai/f "$ROOT/other" origin/main
  fp="$(fingerprint)"
  run_rq f
  [[ $RC -eq 1 && "$OUT" == *"SKIP f:"* && "$OUT" == *"іншому worktree"* && "$(fingerprint)" == "$fp" ]] &&
    ok "гілка відкрита деінде → SKIP, нічого не прибрано" || bad "гілка деінде: rc=$RC $OUT"
  teardown

  # (д) у теці задачі чекаутили іншу гілку (без комітів понад origin/main).
  setup
  mkfailed w
  mkbranch w
  git -C "$WT/w" checkout -q -b other
  fp="$(fingerprint)"
  run_rq w
  [[ $RC -eq 1 && "$OUT" == *"SKIP w:"* && "$OUT" == *"інша гілка"* && "$(fingerprint)" == "$fp" ]] &&
    ok "у worktree відкрита чужа гілка → SKIP, нічого не прибрано" || bad "чужа гілка в worktree: rc=$RC $OUT"
  teardown
  # (е) відокремлений HEAD без комітів — це залишок, не робота.
  setup
  mkfailed v
  mkbranch v
  git -C "$WT/v" checkout -q --detach
  run_rq v
  [[ $RC -eq 0 && "$OUT" == *"OK v:"* && ! -e "$WT/v" ]] &&
    ok "відокремлений HEAD без комітів → OK" || bad "відокремлений HEAD без комітів: rc=$RC $OUT"
  teardown

  # 12. Змішаний запуск і дублікати id.
  setup
  mkfailed a
  mkbranch a
  mkfailed b
  mkbranch b
  commit_in b
  run_rq a b a
  [[ $RC -eq 1 && "$(grep -c '^OK a:' <<<"$OUT")" -eq 1 && "$(grep -c '^SKIP b:' <<<"$OUT")" -eq 1 && "$OUT" == *"OK=1, SKIP=1"* ]] &&
    ok "OK і SKIP в одному запуску: код 1; дублікат id оброблено раз" || bad "змішаний: rc=$RC $OUT"
  [[ -e "$QD/001-a.json" && -e "$QD/failed/001-b.json" ]] && branch_exists b &&
    ok "придатну повернуто, непридатна лишилась зі своєю гілкою" || bad "змішаний: стан"
  teardown

  # 13. Журнал не записався: задачу повернуто, але вихід 1 і попередження.
  setup
  mkfailed a
  printf '#!/bin/sh\nexit 1\n' >"$BIN/bad-journal"
  chmod +x "$BIN/bad-journal"
  A8_JOURNAL="$BIN/bad-journal" run_rq a
  [[ $RC -eq 1 && "$OUT" == *"УВАГА a:"* && "$OUT" == *"OK a:"* && -e "$QD/001-a.json" ]] &&
    ok "збій журналу: задача повернена, але гучно і з кодом 1" || bad "збій журналу: rc=$RC $OUT"
  teardown

  # 14. --remote: скрипт копіює себе на хост, виконує від agent, прибирає файл.
  setup
  STUB="$ROOT/stub"
  CALLS="$ROOT/remote-calls"
  mkdir -p "$STUB"
  : >"$CALLS"
  cat >"$STUB/ssh" <<STUB
#!/usr/bin/env bash
CALLS="$CALLS"
STUB
  cat >>"$STUB/ssh" <<'STUB'
echo "ssh $*" >>"$CALLS"
case "$*" in
  *mktemp*)
    # STUB_BANNER: банер і рядок із ~/.bashrc перед відповіддю, зокрема схожий на назву.
    if [[ -n "${STUB_BANNER:-}" ]]; then
      echo "Welcome to the host"
      echo "/tmp/a8-requeue.DECOY1"
      echo "Last login: yesterday"
    fi
    echo "${STUB_TMPNAME:-/tmp/a8-requeue.Ab12Cd}" ;;
  *sudo*) exit "${STUB_RUN_RC:-0}" ;;
  *"rm -f"*) exit "${STUB_RM_RC:-0}" ;;
esac
exit 0
STUB
  cat >"$STUB/scp" <<STUB
#!/usr/bin/env bash
echo "scp \$*" >>"$CALLS"
exit 0
STUB
  chmod +x "$STUB/ssh" "$STUB/scp"
  rrun() { OUT="$(PATH="$STUB:$PATH" A8_CONFIG="$ROOT/немає.env" "$@" 2>&1)"; RC=$?; }
  self="$(readlink -f "$SCRIPT")"
  rrun bash "$SCRIPT" --remote a8-ts --dry-run --reset-pause a b
  [[ $RC -eq 0 ]] && grep -qx "scp -q -- $self a8-ts:/tmp/a8-requeue.Ab12Cd" "$CALLS" &&
    ok "--remote: скрипт копіюється на хост під унікальну назву" || bad "scp: rc=$RC $(cat "$CALLS")"
  grep -qx "ssh -t a8-ts cd /tmp && sudo -u agent bash /tmp/a8-requeue.Ab12Cd --dry-run --reset-pause a b" "$CALLS" &&
    ok "--remote: ssh -t, sudo -u agent bash, опції й id передано, без --remote" || bad "ssh-запуск: $(cat "$CALLS")"
  [[ "$(tail -n 1 "$CALLS")" == "ssh a8-ts rm -f -- /tmp/a8-requeue.Ab12Cd" ]] &&
    ok "--remote: тимчасовий файл прибрано після запуску" || bad "прибирання: $(tail -n 1 "$CALLS")"
  : >"$CALLS"
  STUB_RUN_RC=1 rrun bash "$SCRIPT" --remote a8-ts a
  [[ $RC -eq 1 && "$(tail -n 1 "$CALLS")" == "ssh a8-ts rm -f -- /tmp/a8-requeue.Ab12Cd" ]] &&
    ok "--remote: код віддаленого запуску (1) повернено, файл прибрано і після невдачі" || bad "код 1: rc=$RC $(cat "$CALLS")"
  : >"$CALLS"
  STUB_RUN_RC=3 rrun bash "$SCRIPT" --remote a8-ts a
  [[ $RC -eq 3 ]] && ok "--remote: код 3 (тік працює) доходить до виклику" || bad "код 3: rc=$RC"
  : >"$CALLS"
  STUB_RUN_RC=255 rrun bash "$SCRIPT" --remote a8-ts a
  [[ $RC -eq 2 && "$(tail -n 1 "$CALLS")" == "ssh a8-ts rm -f -- /tmp/a8-requeue.Ab12Cd" ]] &&
    ok "--remote: 255 від ssh → код 2" || bad "код 255: rc=$RC"
  : >"$CALLS"
  STUB_RM_RC=1 rrun bash "$SCRIPT" --remote a8-ts a
  [[ $RC -eq 0 && "$OUT" == *"УВАГА"* && "$OUT" == *"/tmp/a8-requeue.Ab12Cd"* ]] &&
    ok "--remote: не вдалося прибрати файл → УВАГА з назвою, код запуску збережено" || bad "rm впав: rc=$RC $OUT"
  : >"$CALLS"
  STUB_TMPNAME='/tmp/a8-requeue.x; rm -rf /' rrun bash "$SCRIPT" --remote a8-ts a
  [[ $RC -eq 2 && "$(grep -c '^scp' "$CALLS")" -eq 0 && "$(grep -c 'rm -f' "$CALLS")" -eq 0 ]] &&
    ok "--remote: дивна назва файла від хоста → відмова до scp, rm не викликається" || bad "дивна назва: rc=$RC $(cat "$CALLS")"
  : >"$CALLS"
  STUB_BANNER=1 rrun bash "$SCRIPT" --remote a8-ts a
  [[ $RC -eq 0 ]] && grep -qx "scp -q -- $self a8-ts:/tmp/a8-requeue.Ab12Cd" "$CALLS" &&
    [[ "$(tail -n 1 "$CALLS")" == "ssh a8-ts rm -f -- /tmp/a8-requeue.Ab12Cd" ]] &&
    ok "--remote: банер у відповіді ssh не ламає розбір — береться останній рядок-назва" || bad "банер: rc=$RC $(cat "$CALLS")"
  : >"$CALLS"
  rrun bash "$SCRIPT" --remote -oProxyCommand=x a
  [[ $RC -eq 2 && ! -s "$CALLS" ]] && ok "--remote: хост з «-» на початку відхилено, ssh не викликано" || bad "хост з дефісом: rc=$RC $(cat "$CALLS")"
  rrun bash "$SCRIPT" --remote
  [[ $RC -eq 2 && ! -s "$CALLS" ]] && ok "--remote без хоста → код 2" || bad "--remote без хоста: rc=$RC"
  rrun bash "$SCRIPT" --remote a8-ts '../x'
  [[ $RC -eq 2 && ! -s "$CALLS" ]] && ok "--remote: id перевіряється ДО ssh" || bad "id до ssh: rc=$RC $(cat "$CALLS")"
  teardown
}

run_scenarios

# КОНТРОЛЬ ПЕРЕД МУТАЦІЯМИ. Мутант вважається вбитим, якщо набір на ньому падає.
# Якщо набір падає вже БЕЗ мутації, кожен мутант виглядає вбитим — і «усі убиті»
# стає хибно-зеленим (a8-tick.test.sh, той самий контроль).
if [[ -z "${A8_REQUEUE_UNDER_TEST:-}" && "$fail" -ne 0 ]]; then
  echo
  echo "✗ мутації НЕ ганялись: базовий набір червоний (див. ✗ вище)."
elif [[ -z "${A8_REQUEUE_UNDER_TEST:-}" ]]; then
  MUTDIR="$(mktemp -d)"
  trap 'rm -rf "$MUTDIR"' EXIT
  n=0
  mutate() { # mutate <назва> <perl-вираз>
    n=$((n + 1))
    local m="$MUTDIR/$n.sh"
    echo "$1" >"$MUTDIR/$n.name"
    perl -0pe "$2" "$SCRIPT" >"$m"
    if cmp -s "$m" "$SCRIPT"; then
      echo "stale" >"$MUTDIR/$n.res"
      return
    fi
    if ! bash -n "$m" 2>/dev/null; then
      echo "syntax" >"$MUTDIR/$n.res"
      return
    fi
    (
      if QUIET=1 A8_REQUEUE_UNDER_TEST="$m" bash "$0" >/dev/null 2>&1; then
        echo "survived" >"$MUTDIR/$n.res"
      else
        echo "killed" >"$MUTDIR/$n.res"
      fi
    ) &
    # Не більше 4 одночасно: кожен мутант — повний набір з git-репозиторіями.
    while (($(jobs -rp | wc -l) >= 4)); do sleep 0.2; done
  }
  mutate "перевірку комітів гілки прибрано" 's/if \(\(n != 0\)\); then\n      skip "на гілці/if false; then\n      skip "на гілці/'
  mutate "перевірку брудного worktree прибрано" 's/if \[\[ -n "\$st" \]\]; then/if false; then/'
  mutate "reset прибирає всі кінцеві failed" 's/ && r < k\)/)/'
  mutate "reset: старий алгоритм (K = скільки повернуто)" 's/  ATTR="\$\(jq -r \.c <<<"\$res"\)"/  ATTR=\$#/'
  mutate "reset: лік не зупиняє ok чи чужа задача" 's/            else \.done = true\n            end/            else .\n            end/'
  mutate "reset: не-run події зупиняють лік" 's/elif \(\$o\.event \/\/ ""\) != "run" then \./elif false then ./'
  mutate "reset: нерозбірний рядок ігнорується" 's/\.done = true \| \.bad = true/./'
  mutate "reset: немає runs.log не перевіряється" 's/  if \[\[ ! -r "\$runs" \]\]; then/  if false; then/'
  mutate "reset: runs.log нуль падінь теж знімає" 's/    elif \(\(ATTR == 0\)\); then/    elif false; then/'
  mutate "reset не зупиняється на ok" 's/          break\n/          i--; continue\n/'
  mutate "без flock" 's/if ! flock -n 9; then/if false; then/'
  mutate "fetch не виконується" 's/if ! timeout 120 git -C "\$A8_REPO_DIR" fetch --quiet origin main 9>&-; then/if false; then/'
  mutate "падіння fetch ігнорується" 's/  die "git fetch origin main не вдався/  echo "git fetch origin main не вдався/'
  mutate "running/ не перевіряється" 's/if \(\(\$\{#MATCHES\[@\]\} > 0\)\); then\n    skip "задача з таким id зараз у running\//if false; then\n    skip "задача з таким id зараз у running\//'
  mutate "нерозібраний running/ не рахується" 's/  if \(\(UNPARSED > 0\)\); then\n    skip "у running\//  if false; then\n    skip "у running\//'
  mutate "id у failed не звіряється" 's/if \[\[ "\$got" == "\$2" \]\]; then MATCHES/if true; then MATCHES/'
  mutate "два файли з id не відсіюються" 's/if \(\(\$\{#MATCHES\[@\]\} > 1\)\); then/if false; then/'
  mutate "--dry-run змінює стан" 's/  if \(\(dry\)\); then\n    printf .WOULD/  if false; then\n    printf \x27WOULD/'
  mutate "reset без копії" 's/cp -p -- "\$STATE" "\$bak" \|\|/true ||/'
  mutate "reset у --dry-run пише файл" 's/      elif \(\(dry\)\); then\n        rm -f -- "\$tmp"\n/      elif false; then\n        rm -f -- "\$tmp"\n/'
  mutate "reset: пробіли й \\r не нормалізуються" 's/; sub\(\/\[\[:space:\]\]\+\$\/, "", s\)//'
  mutate "подія requeue не пишеться" 's/if ! "\$JOURNAL" event requeue "\$id"; then/if ! true; then/'
  mutate "збій журналу мовчить" 's/    journal_failed=1/    journal_failed=0/'
  mutate "гілку не видаляє" 's/repo branch -D "\$branch" >\/dev\/null 2>&1 \|\| \{/true || {/'
  mutate "worktree не прибирається" 's/    repo worktree remove --force "\$wt" >\/dev\/null 2>&1 \|\| true\n    if \[\[ -e "\$wt" \]\]; then\n      rm -rf -- "\$wt" 2>\/dev\/null \|\| true\n    fi\n//'
  mutate "prune прибрано" 's/repo worktree prune >\/dev\/null 2>&1 \|\| \{/true || {/'
  mutate "файл задачі не переїжджає" 's/  \{ mkdir -p -- "\$destdir" && mv -n -- "\$taskfile" "\$destdir\/"; \} \|\| rc=\$\?/  true || rc=\$?/'
  mutate "коміти на HEAD worktree не перевіряються" 's/    if \(\(n != 0\)\); then\n      skip "HEAD у/    if false; then\n      skip "HEAD у/'
  mutate "гілка в іншому worktree не враховується" 's/  if \[\[ -n "\$ELSEWHERE" \]\]; then/  if false; then/'
  mutate "незареєстрована тека не відсіюється" 's/    if \(\(!REG\)\); then/    if false; then/'
  mutate "заблокований worktree не відсіюється" 's/    if \(\(LOCKED\)\); then/    if false; then/'
  mutate "симлінк не відсіюється" 's/  if \[\[ -L "\$wt" \]\]; then/  if false; then/'
  mutate "перезапис файла в черзі" 's/  if \[\[ -e "\$destfile" \]\]; then\n    skip "у черзі вже є файл/  if false; then\n    skip "у черзі вже є файл/'
  mutate "id у черзі не перевіряється" 's/  scan_dir "\$Q" "\$id"\n  if \(\(\$\{#MATCHES\[@\]\} > 0\)\); then/  scan_dir "\$Q" "\$id"\n  if false; then/'
  mutate "помилка rev-list = 0 комітів" 's/(n="\$\(repo rev-list --count "refs\/remotes\/origin\/main\.\.\$bref" 2>\/dev\/null\)" \|\|)\n\s+\{\n\s+skip[^\n]*\n\s+return 1\n\s+\}/$1 n=0/'
  mutate "помилка show-ref = гілки немає" 's/    \*\)\n      skip "git show-ref не вдався[^\n]*\n      return 1\n      ;;/    *) ;;/'
  mutate "reset рахує всі id, а не повернуті" 's/reset_pause "\$\{returned\[@\]\}"/reset_pause "\${uniq_ids[@]}"/'
  mutate "SKIP не дає код 1" 's/\(\(skipped == 0 && journal_failed == 0\)\) \|\| exit 1/true || exit 1/'
  mutate "дублікати id не прибираються" 's/  if \[\[ -z "\$\{seen\[\$id\]:-\}" \]\]; then/  if true; then/'
  mutate "ssh -t без термінала" 's/ssh -t "\$remote"/ssh "\$remote"/'
  mutate "--remote не прибирає файл" 's/  trap cleanup_remote EXIT\n//'
  mutate "назва файла від хоста не перевіряється" 's/  \[\[ -n "\$made" \]\] \|\| die[^\n]*\n//'
  mutate "хост з дефісом дозволено" 's/  \[\[ "\$remote" =~ \^\[A-Za-z0-9\][^\n]*\n//'
  mutate "чужа гілка в worktree не відсіюється" 's/        if \[\[ "\$head_ref" != "\$bref" \]\]; then/        if false; then/'
  mutate "відокремлений HEAD вважається чужою гілкою" 's/      1\) ;; # відокремлений HEAD[^\n]*\n/      1)\n        skip "x"\n        return 1\n        ;;\n/'
  mutate "банер: береться перший збіг" 's/tail -n 1 \|\| true/head -n 1 || true/'
  mutate "банер: уся відповідь як назва" 's/ \| grep -E \x27[^\x27]*\x27 \| tail -n 1 \|\| true//'
  mutate "код 255 від ssh не змінюється" 's/  \(\(rc == 255\)\) && die[^\n]*\n//'
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
