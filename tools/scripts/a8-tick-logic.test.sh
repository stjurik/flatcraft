#!/usr/bin/env bash
# a8-tick-logic.test.sh — доказ логіки рішень демона черги A8.
#
# Дві частини:
#   1. сценарії — вхід → очікуваний вихід (код ТА текст, docs/16 §8.1: код
#      виходу сам по собі — слабке твердження);
#   2. мутації — ламаємо логіку по одному місцю і вимагаємо, щоб набір
#      ПОЧЕРВОНІВ. Набір, що зеленіє на зламаному коді, доводить лише власну
#      присутність. Мутації живуть тут, а не в звіті, щоб CI перевіряв їх щоразу.
#
# Запуск: tools/scripts/a8-tick-logic.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LOGIC="${A8_LOGIC_UNDER_TEST:-$HERE/a8-tick-logic.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

check() { # check <назва> <очікуваний код> <очікуваний текст> -- <команда...>
  local name="$1" want_rc="$2" want_out="$3"
  shift 4
  local out rc=0
  out="$("$@" 2>&1)" || rc=$?
  if [[ "$rc" == "$want_rc" && "$out" == "$want_out" ]]; then
    [[ -z "${QUIET:-}" ]] && echo "✓ $name"
  else
    echo "✗ $name — очікував [$want_rc] '$want_out', отримав [$rc] '$out'"
    fail=1
  fi
}

task() { # task <ім'я> <json> — фікстура запису черги
  printf '%s\n' "$2" >"$TMP/$1.json"
  echo "$TMP/$1.json"
}

# Змінну режиму НЕ виставляємо: тест мусить бачити ДЕФОЛТ логіки, інакше
# мутація дефолту («external дозволено за замовчуванням») вижила б.
L() { env -u A8_SOURCES_ALLOWED bash "$LOGIC" "$@"; }

run_scenarios() {
  local ok='"id":"t-1","source":"human","origin":"direction","oracle":"pnpm test","prompt":"зроби X"'

  # ── Запис черги: fail closed, і КОЖНЕ «ні» назване своїм полем ────────────
  check "валідний запис → прийнято" 0 "ok" -- L validate "$(task valid "{$ok}")"
  check "без source → відмова source:missing" 3 "reject source:missing" -- \
    L validate "$(task nosrc '{"id":"t-1","origin":"direction","oracle":"x","prompt":"p"}')"
  check "source поза переліком → source:invalid" 3 "reject source:invalid" -- \
    L validate "$(task badsrc '{"id":"t-1","source":"yurii","origin":"direction","oracle":"x","prompt":"p"}')"
  # Режим (а) OQ-34: external ВІДОМИЙ, але ще не дозволений — окрема причина,
  # не злита з «невідомим». Фікстура розводить ці два значення (docs/16 §8.1).
  check "source external у режимі (а) → source:not-allowed" 3 "reject source:not-allowed" -- \
    L validate "$(task ext '{"id":"t-1","source":"external","origin":"feedback","oracle":"x","prompt":"p"}')"
  check "той самий external, коли дозволено → прийнято (контроль до попереднього)" 0 "ok" -- \
    env A8_SOURCES_ALLOWED="human external" bash "$LOGIC" validate "$TMP/ext.json"
  check "без origin → origin:missing" 3 "reject origin:missing" -- \
    L validate "$(task noorig '{"id":"t-1","source":"human","oracle":"x","prompt":"p"}')"
  check "origin поза трьома джерелами → origin:invalid" 3 "reject origin:invalid" -- \
    L validate "$(task badorig '{"id":"t-1","source":"human","origin":"agent-idea","oracle":"x","prompt":"p"}')"
  check "без oracle → oracle:missing" 3 "reject oracle:missing" -- \
    L validate "$(task noorc '{"id":"t-1","source":"human","origin":"direction","prompt":"p"}')"
  check "oracle із самих пробілів → oracle:missing" 3 "reject oracle:missing" -- \
    L validate "$(task wsorc '{"id":"t-1","source":"human","origin":"direction","oracle":"   ","prompt":"p"}')"
  check "два поля погані → названо ОБИДВА, у фіксованому порядку" 3 "reject source:missing,oracle:missing" -- \
    L validate "$(task two '{"id":"t-1","origin":"direction","prompt":"p"}')"
  check "id з ../ → id:invalid (іде в ім'я гілки)" 3 "reject id:invalid" -- \
    L validate "$(task dots '{"id":"../main","source":"human","origin":"direction","oracle":"x","prompt":"p"}')"
  check "не JSON → reject json" 3 "reject json" -- L validate "$(task broken 'not json')"
  check "без id → id:missing" 3 "reject id:missing" -- \
    L validate "$(task noid '{"source":"human","origin":"direction","oracle":"x","prompt":"p"}')"
  check "порожній prompt → prompt:missing" 3 "reject prompt:missing" -- \
    L validate "$(task noprompt '{"id":"t-1","source":"human","origin":"direction","oracle":"x","prompt":"  "}')"
  check "oracle — об'єкт, не рядок → oracle:not-string (не «ok»)" 3 "reject oracle:not-string" -- \
    L validate "$(task objorc '{"id":"t-1","source":"human","origin":"direction","oracle":{},"prompt":"p"}')"
  check "source — число → source:not-string, без зайвого source:missing" 3 "reject source:not-string" -- \
    L validate "$(task numsrc '{"id":"t-1","source":1,"origin":"direction","oracle":"x","prompt":"p"}')"
  # Межі id — ті, що git не прийме як ім'я гілки ai/<id>.
  check "id з .. → id:invalid (git check-ref-format)" 3 "reject id:invalid" -- \
    L validate "$(task dd '{"id":"a..b","source":"human","origin":"direction","oracle":"x","prompt":"p"}')"
  check "id на .lock → id:invalid" 3 "reject id:invalid" -- \
    L validate "$(task lock '{"id":"x.lock","source":"human","origin":"direction","oracle":"x","prompt":"p"}')"
  check "id 64 символи → прийнято (межа)" 0 "ok" -- \
    L validate "$(task id64 "{\"id\":\"$(printf 'a%.0s' {1..64})\",\"source\":\"human\",\"origin\":\"direction\",\"oracle\":\"x\",\"prompt\":\"p\"}")"
  check "id 65 символів → id:invalid" 3 "reject id:invalid" -- \
    L validate "$(task id65 "{\"id\":\"$(printf 'a%.0s' {1..65})\",\"source\":\"human\",\"origin\":\"direction\",\"oracle\":\"x\",\"prompt\":\"p\"}")"

  # ── Смуга виконавця (PR-B #262): executor, тести приймання, лічильник ────
  local b='"id":"t-1","source":"human","origin":"direction","oracle":"x","prompt":"p"'
  check "executor відсутній → прийнято (виконує claude)" 0 "ok" -- L validate "$(task ex-none "{$b}")"
  check "executor gemini → прийнято" 0 "ok" -- L validate "$(task ex-gem "{$b,\"executor\":\"gemini\"}")"
  check "executor claude → прийнято" 0 "ok" -- L validate "$(task ex-cl "{$b,\"executor\":\"claude\"}")"
  check "executor codex → executor:invalid" 3 "reject executor:invalid" -- \
    L validate "$(task ex-bad "{$b,\"executor\":\"codex\"}")"
  check "executor Gemini (регістр) → executor:invalid" 3 "reject executor:invalid" -- \
    L validate "$(task ex-case "{$b,\"executor\":\"Gemini\"}")"
  check "executor порожній → executor:invalid, не «claude за замовчуванням»" 3 "reject executor:invalid" -- \
    L validate "$(task ex-empty "{$b,\"executor\":\"\"}")"
  check "executor масив → executor:not-string" 3 "reject executor:not-string" -- \
    L validate "$(task ex-arr "{$b,\"executor\":[\"gemini\"]}")"
  check "acceptance_tests — масив шляхів → прийнято" 0 "ok" -- \
    L validate "$(task at-ok "{$b,\"acceptance_tests\":[\"apps/web/a.test.ts\",\"tests/acc/\"]}")"
  check "acceptance_tests — рядок → acceptance_tests:not-array" 3 "reject acceptance_tests:not-array" -- \
    L validate "$(task at-str "{$b,\"acceptance_tests\":\"a.test.ts\"}")"
  check "acceptance_tests з ../ → acceptance_tests:invalid" 3 "reject acceptance_tests:invalid" -- \
    L validate "$(task at-dots "{$b,\"acceptance_tests\":[\"apps/../CLAUDE.md\"]}")"
  check "acceptance_tests з абсолютним шляхом → acceptance_tests:invalid" 3 "reject acceptance_tests:invalid" -- \
    L validate "$(task at-abs "{$b,\"acceptance_tests\":[\"/etc/x\"]}")"
  check "acceptance_tests з порожнім рядком → acceptance_tests:invalid" 3 "reject acceptance_tests:invalid" -- \
    L validate "$(task at-empty "{$b,\"acceptance_tests\":[\"\"]}")"
  check "acceptance_tests з числом → acceptance_tests:invalid" 3 "reject acceptance_tests:invalid" -- \
    L validate "$(task at-num "{$b,\"acceptance_tests\":[1]}")"
  check "oracle_failures 1 → прийнято" 0 "ok" -- L validate "$(task of-1 "{$b,\"oracle_failures\":1}")"
  check "oracle_failures -1 → oracle_failures:invalid" 3 "reject oracle_failures:invalid" -- \
    L validate "$(task of-neg "{$b,\"oracle_failures\":-1}")"
  check "oracle_failures \"1\" → oracle_failures:invalid" 3 "reject oracle_failures:invalid" -- \
    L validate "$(task of-str "{$b,\"oracle_failures\":\"1\"}")"

  # Backstop тестів приймання: точний шлях і шлях у теці — так; схожий префікс — ні.
  local at
  at="$(task at-list "{$b,\"acceptance_tests\":[\"apps/web/a.test.ts\",\"tests/acc/\"]}")"
  check "змінено файл тесту приймання → названо, exit 1" 1 "apps/web/a.test.ts" -- \
    bash -c 'printf "%s\n" src/x.ts apps/web/a.test.ts | env -u A8_SOURCES_ALLOWED bash "$0" acceptance-violations "$1"' "$LOGIC" "$at"
  check "змінено файл у теці тестів приймання → названо, exit 1" 1 "tests/acc/b.py" -- \
    bash -c 'printf "%s\n" tests/acc/b.py | bash "$0" acceptance-violations "$1"' "$LOGIC" "$at"
  check "схожий префікс (a.test.ts.bak, tests/accX) — не тест приймання → exit 0" 0 "" -- \
    bash -c 'printf "%s\n" apps/web/a.test.ts.bak tests/accX/c.py | bash "$0" acceptance-violations "$1"' "$LOGIC" "$at"
  check "задача без переліку → нічого не захищено, exit 0" 0 "" -- \
    bash -c 'printf "%s\n" apps/web/a.test.ts | bash "$0" acceptance-violations "$1"' "$LOGIC" "$TMP/ex-none.json"

  # Профіль agy «виконавець»: читання й запис — рівно worktree, команди — без agy.
  printf '%s\n' '{"model":"m","permissions":{"allow":["write_file(*)"]}}' >"$TMP/agy-settings.json"
  printf '%s\n' '{"allow":["read_file(@WT@)","write_file(@WT@)","command(git)","command(pnpm)"],"deny":["write_file(/tmp)"]}' >"$TMP/tpl-ok.json"
  check "профіль виконавця: worktree підставлено, решта налаштувань ціла" 0 \
    '{"model":"m","permissions":{"allow":["read_file(/w/t1)","write_file(/w/t1)","command(git)","command(pnpm)"],"deny":["write_file(/tmp)"]}}' -- \
    bash -c 'bash "$0" agy-settings "$1" "$2" /w/t1 | jq -c .' "$LOGIC" "$TMP/agy-settings.json" "$TMP/tpl-ok.json"
  check "шаблон репо (tools/agy/executor-permissions.json) проходить охорону" 0 "ok" -- \
    bash -c 'bash "$0" agy-settings "$1" "$2" /w/t1 >/dev/null && echo ok' "$LOGIC" "$TMP/agy-settings.json" "$HERE/../agy/executor-permissions.json"
  printf '%s\n' '{"allow":["read_file(@WT@)","write_file(*)"],"deny":["write_file(/tmp)"]}' >"$TMP/tpl-wide.json"
  check "запис будь-куди → відмова" 1 "" -- \
    bash -c 'bash "$0" agy-settings "$1" "$2" /w/t1 2>/dev/null' "$LOGIC" "$TMP/agy-settings.json" "$TMP/tpl-wide.json"
  printf '%s\n' '{"allow":["read_file(@WT@)","command(agy)"],"deny":["write_file(/tmp)"]}' >"$TMP/tpl-agy.json"
  check "command(agy) — agy запускає сам себе → відмова" 1 "" -- \
    bash -c 'bash "$0" agy-settings "$1" "$2" /w/t1 2>/dev/null' "$LOGIC" "$TMP/agy-settings.json" "$TMP/tpl-agy.json"
  printf '%s\n' '{"allow":["read_file(@WT@)","command(pnpm *)"],"deny":["write_file(/tmp)"]}' >"$TMP/tpl-star.json"
  check "command з * → відмова" 1 "" -- \
    bash -c 'bash "$0" agy-settings "$1" "$2" /w/t1 2>/dev/null' "$LOGIC" "$TMP/agy-settings.json" "$TMP/tpl-star.json"
  printf '%s\n' '{"allow":["read_file(@WT@)"]}' >"$TMP/tpl-nodeny.json"
  check "без deny write_file(/tmp) → відмова" 1 "" -- \
    bash -c 'bash "$0" agy-settings "$1" "$2" /w/t1 2>/dev/null' "$LOGIC" "$TMP/agy-settings.json" "$TMP/tpl-nodeny.json"
  check "налаштувань agy немає → відмова" 1 "" -- \
    bash -c 'bash "$0" agy-settings "$1" "$2" /w/t1 2>/dev/null' "$LOGIC" "$TMP/none.json" "$TMP/tpl-ok.json"
  check "worktree з дужкою → відмова (вийшов би за межі правила)" 1 "" -- \
    bash -c 'bash "$0" agy-settings "$1" "$2" "/w/t1) read_file(/" 2>/dev/null' "$LOGIC" "$TMP/agy-settings.json" "$TMP/tpl-ok.json"

  # ── Коди guard'а: три РІЗНІ стани ─────────────────────────────────────────
  check "guard 0 → ok" 0 "ok" -- L guard-state 0
  check "guard 10 → kill_switch" 0 "kill_switch" -- L guard-state 10
  check "guard 11 → daily_limit" 0 "daily_limit" -- L guard-state 11
  check "guard 12 → paused" 0 "paused" -- L guard-state 12
  check "guard 1 (немає конфігу) → guard_error, не ok" 0 "guard_error" -- L guard-state 1

  # ── Класифікатор: лише бачені сигнатури ───────────────────────────────────
  printf '{"type":"result","is_error":true,"num_turns":1,"result":"Failed to authenticate. API Error: 401 Invalid bearer token","total_cost_usd":0}\n' >"$TMP/401.log"
  printf 'warning: some stderr line\n{"type":"result","is_error":true,"num_turns":0,"result":"Failed to authenticate. API Error: 401 Invalid bearer token"}\n' >"$TMP/401-noisy.log"
  printf '{"type":"result","is_error":false,"num_turns":12,"result":"Готово. У docs/13 описано: Failed to authenticate. API Error: 401 Invalid bearer token."}\n' >"$TMP/mention.log"
  # Прогін упав з ІНШОЇ причини після багатьох кроків, а текст цитує сигнатуру.
  printf '{"type":"result","subtype":"error_max_turns","is_error":true,"num_turns":200,"result":"Зупинився. Нагадую: Failed to authenticate. API Error: 401 Invalid bearer token — це про токен."}\n' >"$TMP/mention-fail.log"
  printf 'Failed to authenticate. API Error: 401 Invalid bearer token\n' >"$TMP/401-raw.log"
  # Успіх за ОДИН крок, що цитує сигнатуру: розводить умову is_error і умову
  # num_turns — без цієї фікстури мутація «без is_error» виживала (виміряно).
  printf '{"type":"result","is_error":false,"num_turns":1,"result":"Failed to authenticate. API Error: 401 Invalid bearer token — так виглядає 401."}\n' >"$TMP/mention-1turn.log"
  printf 'Error: rate limit reached, usage quota exceeded, try later\n' >"$TMP/quota-ish.log"
  printf '{"type":"result","is_error":false,"result":"done"}\n' >"$TMP/ok.log"
  printf '{"type":"result","is_error":true,"result":"something broke"}\n' >"$TMP/iserr.log"

  check "401 + is_error, rc=1 → auth_stop (STOP, не retry)" 0 "auth_stop 401" -- L classify 1 "$TMP/401.log"
  check "401 + is_error, rc=0 → теж auth_stop" 0 "auth_stop 401" -- L classify 0 "$TMP/401.log"
  # Розводимо «рядок 401 є» і «прогін упав через 401»: агент згадав сигнатуру
  # в успішному прогоні — це НЕ зупинка черги.
  check "згадка 401 в УСПІШНОМУ прогоні → ok, не auth_stop" 0 "ok -" -- L classify 0 "$TMP/mention.log"
  check "згадка 401 у прогоні, що впав ІНАКШЕ після 200 кроків → failed, не auth_stop" 0 "failed rc=1" -- \
    L classify 1 "$TMP/mention-fail.log"
  check "401 із рядком stderr перед JSON → усе одно auth_stop" 0 "auth_stop 401" -- L classify 1 "$TMP/401-noisy.log"
  check "успіх за 1 крок із цитатою 401 → ok (is_error=false)" 0 "ok -" -- L classify 0 "$TMP/mention-1turn.log"
  check "без JSON, rc≠0, повна фраза 401 → auth_stop" 0 "auth_stop 401" -- L classify 1 "$TMP/401-raw.log"
  check "без JSON, rc=0, повна фраза 401 → не auth_stop" 0 "ok -" -- L classify 0 "$TMP/401-raw.log"
  check "невідома сигнатура «quota» → failed, НЕ quota" 0 "failed rc=1" -- L classify 1 "$TMP/quota-ish.log"
  check "rc=0 без помилки → ok" 0 "ok -" -- L classify 0 "$TMP/ok.log"
  check "rc=0, але is_error → failed" 0 "failed is_error" -- L classify 0 "$TMP/iserr.log"
  check "таймаут 124 → failed timeout" 0 "failed timeout" -- L classify 124 "$TMP/ok.log"
  check "обгортка повернула 11 → stopped daily_limit, не failed" 0 "stopped daily_limit" -- L classify 11 "$TMP/ok.log"
  # Виконавець gemini: сигнатура 401 Claude у виводі agy — цитата, не зупинка черги.
  check "gemini: 401 Claude у виводі agy, rc=1 → failed, не auth_stop" 0 "failed rc=1" -- L classify 1 "$TMP/401-raw.log" gemini
  check "gemini: 401 у JSON-формі → failed, не auth_stop" 0 "failed rc=1" -- L classify 1 "$TMP/401.log" gemini
  check "gemini: rc=0 → ok" 0 "ok -" -- L classify 0 "$TMP/ok.log" gemini
  check "claude явно: 401 → auth_stop, як і без аргументу" 0 "auth_stop 401" -- L classify 1 "$TMP/401.log" claude

  # ── Пауза рівно на третьому ───────────────────────────────────────────────
  printf 'failed\nfailed\n' >"$TMP/r2"
  printf 'failed\nfailed\nfailed\n' >"$TMP/r3"
  printf 'failed\nfailed\nok\n' >"$TMP/r-ok"
  printf 'failed\nfailed\nfailed\n\n' >"$TMP/r3-trailing"
  printf 'failed\r\nfailed\r\nfailed\r\n' >"$TMP/r3-crlf"
  check "два падіння → ще працюємо" 1 "continue" -- L should-pause 3 "$TMP/r2"
  check "третє падіння → пауза" 0 "pause" -- L should-pause 3 "$TMP/r3"
  check "три, але останній ok → працюємо" 1 "continue" -- L should-pause 3 "$TMP/r-ok"
  check "три + порожній рядок у кінці → все одно пауза" 0 "pause" -- L should-pause 3 "$TMP/r3-trailing"
  check "три з CRLF → все одно пауза" 0 "pause" -- L should-pause 3 "$TMP/r3-crlf"
  check "файлу немає → працюємо" 1 "continue" -- L should-pause 3 "$TMP/none"
  # Розводимо «failed усього» і «failed серед останніх трьох»: без tail набір
  # не відрізнив би ці два значення (знайдено незалежним рев'ю №2).
  printf 'failed\nfailed\nfailed\nok\nfailed\nfailed\n' >"$TMP/r-history"
  printf 'failed \nfailed  \nfailed\t\n' >"$TMP/r3-trailing-ws"
  check "стара серія з трьох + ok + два нові → працюємо" 1 "continue" -- L should-pause 3 "$TMP/r-history"
  check "три з хвостовими пробілами → все одно пауза" 0 "pause" -- L should-pause 3 "$TMP/r3-trailing-ws"
}

run_scenarios

# ── Мутації: кожна МУСИТЬ зробити набір червоним ────────────────────────────
if [[ -z "${A8_LOGIC_UNDER_TEST:-}" ]]; then
  mutate() { # mutate <назва> <sed-вираз>
    local name="$1" expr="$2" m="$TMP/mutant.sh"
    sed "$expr" "$LOGIC" >"$m"
    if cmp -s "$m" "$LOGIC"; then
      echo "✗ мутація «$name» нічого не змінила — вираз застарів"
      fail=1
      return
    fi
    # Синтаксично битий мутант «гине» від усіх сценаріїв одразу і нічого не
    # доводить про свою перевірку (знайдено незалежним рев'ю №2).
    if ! bash -n "$m" 2>/dev/null; then
      echo "✗ мутація «$name» ламає синтаксис — вона некоректна, а не вбита"
      fail=1
      return
    fi
    if QUIET=1 A8_LOGIC_UNDER_TEST="$m" bash "$0" >/dev/null 2>&1; then
      echo "✗ мутація «$name» ВИЖИЛА — набір зелений на зламаному коді"
      fail=1
    else
      echo "✓ мутація «$name» убита"
    fi
  }
  mutate "401 без умови num_turns" 's/ and ((.num_turns \/\/ 0) <= 1)//'
  mutate "401 без умови is_error" 's/    if ((is_error)) \&\&$/    if true \&\&/'
  mutate "401 у сирому виводі навіть при rc=0" 's/  elif \[\[ "\$rc" != 0 \]\] \&\& grep -Fq/  elif grep -Fq/'
  mutate "клас quota з повітря" 's/echo "failed rc=\$rc"/echo "quota -"/'
  mutate "external дозволено за замовчуванням" 's/A8_SOURCES_ALLOWED:-human}/A8_SOURCES_ALLOWED:-human external}/'
  mutate "перевірку origin прибрано" 's/    reasons+=("origin:invalid")/    :/'
  mutate "перевірку prompt прибрано" 's/    reasons+=("prompt:missing")/    :/'
  mutate "перевірку id прибрано" 's/|| reasons+=("id:missing")/|| :/'
  mutate "тип поля не перевіряється" 's/      reasons+=("\$f:not-string")/      :/'
  mutate "id без правил git" 's/ || "\$id" == \*\.\.\* ||/ ||/'
  mutate "пауза на другому" 's/((n >= limit))/((n >= limit - 1))/'
  mutate "tail прибрано" 's/tail -n "\$limit" | //'
  mutate "хвостові пробіли не зрізаються" "s/ | sed 's\/\[\[:space:\]\]\*\$\/\/'//"
  mutate "лише перша причина" 's/echo "reject \${reasons\[\*\]}"/echo "reject ${reasons[0]}"/'
  mutate "guard 11 злитий з 12" 's/11) echo daily_limit/11) echo paused/'
  mutate "пробіли як оракул" 's/\${oracle\/\/\[\[:space:\]\]\/}/${oracle}/'
  # Смуга виконавця (PR-B #262).
  mutate "невідомий executor прийнято" 's/    reasons+=("executor:invalid")/    :/'
  mutate "executor не перевіряється на тип" 's/for f in id source origin oracle prompt executor; do/for f in id source origin oracle prompt; do/'
  mutate "codex у переліку виконавців" 's/A8_EXECUTORS_KNOWN="gemini claude"/A8_EXECUTORS_KNOWN="gemini claude codex"/'
  mutate "порожній executor = claude" 's/has("executor") and (.executor | type) == "string"/has("executor") and (.executor | type) == "string" and .executor != ""/'
  mutate "acceptance_tests не масив — прийнято" 's/    reasons+=("acceptance_tests:not-array")/    :/'
  mutate "acceptance_tests з .. — прийнято" 's/ or \. == "\.\."//'
  mutate "oracle_failures не перевіряється" 's/    reasons+=("oracle_failures:invalid")/    :/'
  mutate "backstop тестів лише на точний шлях" 's/ || "\$path" == "\$t\/"\*//'
  mutate "backstop тестів за префіксом рядка" 's/"\$path" == "\$t\/"\*/"$path" == "$t"*/'
  mutate "backstop тестів завжди зелений" 's/  ((hit == 0))$/  true/'
  mutate "профіль: запис будь-куди пропущено" 's/select(\. != \$r and \. != \$w and/select(. != $r and/'
  mutate "профіль: command(agy) пропущено" 's/select(\. == "command(agy)")/select(. == "command(none)")/'
  mutate "профіль: * у команді пропущено" 's/A-Za-z0-9\._-\]+/A-Za-z0-9._ *-]+/'
  mutate "профіль без deny /tmp" 's/index("write_file(\/tmp)") != null/true/'
  mutate "профіль: дужка у worktree пропущена" 's/"\$wt" != \*\[\\(\\)\\\*\\ \]\*/true/'
  mutate "gemini: 401 зупиняє чергу" 's/  \[\[ "\$executor" == gemini \]\] \&\& auth=0/  :/'
fi

if [[ "$fail" -eq 1 ]]; then
  echo "FAIL"
  exit 1
fi
[[ -z "${QUIET:-}" ]] && echo "Усі тести пройдено."
exit 0
