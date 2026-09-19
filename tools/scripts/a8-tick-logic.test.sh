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
fi

if [[ "$fail" -eq 1 ]]; then
  echo "FAIL"
  exit 1
fi
[[ -z "${QUIET:-}" ]] && echo "Усі тести пройдено."
exit 0
