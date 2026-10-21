#!/usr/bin/env bash
# a8-queue.sh — дієслова черги A8: status, enqueue, requeue, pause, resume.
#
# ЧОМУ ЦЕЙ СКРИПТ ІСНУЄ. Кожен пакет задач A8 ставив yurii командою з `sudo` (#78),
# бо профіль оркестратора `sudo` не дає: продукт щоразу чекав на ручний крок
# (#231). Тепер оркестратор ставить, повертає й зупиняє задачі сам — лише цими
# дієсловами, а кожен виклик лишає рядок у журналі на A8.
#
# НЕ ЗАЛЕЖИТЬ ВІД ТРАНСПОРТУ (рішення yurii 2026-10-20). Уся логіка тут, і скрипт
# однаково працює, хоч його викликали локально на A8 (`a8-queue status` від
# agent), хоч через ssh-ключ із forced-command `a8-ctl`. `a8-ctl` лише перекладає
# SSH_ORIGINAL_COMMAND в аргументи цього скрипта й ставить A8_CTL_VIA=ssh — власної
# логіки в ньому немає. Тест (`a8-queue.test.sh`) ганяє ті самі сценарії обома
# шляхами.
#
# ДІЄСЛОВА:
#   status                    лише читання: STOP, стан запобіжників, плановий
#                             потік, lock тіку, черга по теках, last-results, хвіст
#                             runs.log (разом з останнім ротованим).
#   enqueue [--urgent]        ОДИН запис задачі зі stdin (≤ 64 КіБ) →
#                             a8-tick-logic.sh validate → у чергу атомарно, 0644.
#                             Невалідний запис, id, що вже є в черзі чи має гілку
#                             ai/<id>, — відмова, у черзі нічого. --urgent кладе в
#                             urgent/: тік бере її першою, навіть коли плановий
#                             потік на паузі. Невідкладна — лише одна одночасно
#                             (рішення yurii 2026-10-19, #262).
#   requeue [--reset-pause] <id>…
#                             встановлений роллю a8-requeue.sh: лише порожні гілки
#                             й чисті worktree (усі його перевірки — там).
#                             Невідкладна повертається в urgent/. --reset-pause —
#                             лише локально, не через a8-ctl (див. нижче).
#   pause | resume            плановий потік: на паузі тік бере лише urgent/.
#                             Задачу, що вже йде, пауза не зупиняє — вона дограє
#                             (рішення 19.10). Подія в runs.log — лише при зміні
#                             стану; повторний pause чи resume нічого не пише.
#
# ЖУРНАЛ ВИКЛИКІВ. Кожен виклик, зокрема відмова й status, — рядок JSON у
# $A8_LOGS_DIR/ctl.log: час, через що (local|ssh), дієслово, id, код виходу,
# пояснення. Окремий файл, а не runs.log: status оркестратор кличе щопівгодини, і
# в runs.log ці рядки витісняли б записи прогонів під час ротації (#231, 13.10).
# У runs.log ідуть лише зміни стану: enqueue, planned_paused, planned_resumed
# (requeue пише туди сам a8-requeue.sh).
#
# ЧОГО НЕ РОБИТЬ. Не запускає тік, не знімає STOP і паузу після падінь (окрім
# локального `requeue --reset-pause`, і то лише облік повернених задач), не змінює
# денного ліміту, не читає вміст задач у done/ чи failed/ понад поле id.
#
# --reset-pause — ЛИШЕ ЛОКАЛЬНО, ВІД ВЛАСНИКА ЧЕРГИ (рішення yurii 2026-10-21).
# Пауза після трьох падінь — STOP-тригер (CLAUDE.md §0 п.7): її знімає людина.
# Оркестратор, що сам знімає облік падінь, міг би крутити зламану задачу до денного
# ліміту (контрприклад 2, PR #272). Тому через a8-ctl — відмова, а адміністратор
# запускає `sudo -u agent a8-queue requeue --reset-pause <id>…`.
#
# ВІД ROOT — ВІДМОВА ДЛЯ ВСІХ ДІЄСЛІВ. Root виконав би їх від себе: файли root у
# черзі, queue.lock і planned-paused, яких тік від agent не змінить; запис root у
# теку agent, де agent може підкласти симлінк; git у чужому репозиторії — «dubious
# ownership» (контрприклади Argon 1, 3а, 3б, PR #272). Запускай від власника черги.
#
# МЕЖА — ОКРЕМИЙ КОРИСТУВАЧ, А НЕ ЦЕЙ СКРИПТ. Перевірка via — це двері, а не
# механічна межа: процес від agent прочитає й запише файли черги напряму, без
# a8-queue (контрприклад Argon 2(1)). Межу дає окремий користувач orchestrator, для
# якого a8-ctl — єдині двері до черги, і локально на A8 теж. Це ADR контракту A8
# (спринт 02.11); доки його немає, оркестратор працює з чергою лише з T470 через
# a8-ctl.
#
# LOCK СТАНУ ЧЕРГИ — $A8_LOGS_DIR/queue.lock. Під ним enqueue перевіряє «id ще
# немає, невідкладної немає» і пише; під ним же тік і a8-requeue.sh роблять кожне
# переміщення задачі між теками. Інакше перевірка тек по черзі не була б знімком:
# задача, яку requeue переносить з failed/ у корінь між перевірками кореня й
# failed/, не знайшлася б ніде (контрприклад 3, PR #272). Окремий від tick.lock:
# тік тримає свій lock усю задачу, а постановка мусить іти й тоді.
#
# Змінні (точки підміни для тесту, як у тіку): A8_CONFIG (/etc/a8/a8.env),
# A8_TICK_LOGIC (/usr/local/lib/a8/a8-tick-logic.sh), A8_REQUEUE
# (/usr/local/lib/a8/a8-requeue.sh), A8_JOURNAL (/usr/local/bin/a8-journal),
# A8_GUARD (/usr/local/bin/a8-guard), A8_CTL_VIA (local|ssh; ставить a8-ctl),
# A8_ENQUEUE_HOLD_S (лише тест гонки enqueue).
# Через ssh-ключ із `restrict` sshd змінних середовища не приймає, тож підмінити
# їх ззовні не можна.
#
# Виходи: 0 — зроблено; 1 — відмова по суті (невалідний запис, id уже є, SKIP у
# requeue); 2 — помилка використання чи конфігу; 3 — зайнято (lock тіку для
# requeue, queue.lock для enqueue).
set -uo pipefail

CONFIG="${A8_CONFIG:-/etc/a8/a8.env}"
LOGIC="${A8_TICK_LOGIC:-/usr/local/lib/a8/a8-tick-logic.sh}"
REQUEUE="${A8_REQUEUE:-/usr/local/lib/a8/a8-requeue.sh}"
JOURNAL="${A8_JOURNAL:-/usr/local/bin/a8-journal}"
GUARD="${A8_GUARD:-/usr/local/bin/a8-guard}"
VIA="${A8_CTL_VIA:-local}"
[[ "$VIA" == ssh ]] || VIA=local
MAX_TASK_BYTES=65536

verb="${1:-}"
(($# > 0)) && shift
args=("$@")
log_ids=""
log_detail=""
enq_tmp=""

# ─── Журнал виклику — на будь-якому виході ──────────────────────────────────
# Конфіг ще міг не прочитатися: тоді журналу немає куди писати, і це видно з коду
# виходу 2 й stderr.
ctl_log() {
  local rc=$?
  # Недописаний запис enqueue не лишається: тимчасовий файл прибирається тут, ПІСЛЯ
  # того, як код виходу вже взято (окремий trap з `rm` підмінив би його кодом rm).
  [[ -z "$enq_tmp" ]] || rm -f -- "$enq_tmp"
  [[ -n "${A8_LOGS_DIR:-}" && -d "${A8_LOGS_DIR:-}" ]] || return "$rc"
  # Від root — нічого не пише: відмова видна з коду й stderr (див. заголовок).
  ((EUID != 0)) || return "$rc"
  jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg via "$VIA" --arg verb "$verb" \
    --arg ids "$log_ids" --argjson rc "$rc" --arg detail "$log_detail" \
    '{ts:$ts, via:$via, verb:$verb, ids:$ids, rc:$rc, detail:$detail}' \
    >>"$A8_LOGS_DIR/ctl.log" 2>/dev/null
  return "$rc"
}
trap ctl_log EXIT

die() { # die <код> <пояснення>
  log_detail="$2"
  echo "a8-queue: $2" >&2
  exit "$1"
}

usage() {
  sed -n '2,/^set -/{/^set -/!p}' "$0" | sed 's/^# \?//'
}

# ─── Від root — відмова, до будь-якого читання й запису (див. заголовок) ──────
((EUID != 0)) ||
  die 1 "від root не працюю — запускай від власника черги: sudo -u agent a8-queue …"

# ─── Конфіг ─────────────────────────────────────────────────────────────────
case "$verb" in
  -h | --help)
    usage
    exit 0
    ;;
esac
[[ -r "$CONFIG" ]] || die 2 "немає $CONFIG — скрипт працює на A8"
# shellcheck disable=SC1090
source "$CONFIG" || die 2 "не вдалося прочитати $CONFIG"
for v in A8_QUEUE_DIR A8_LOGS_DIR A8_REPO_DIR A8_KILL_SWITCH; do
  [[ -n "${!v:-}" ]] || die 2 "у $CONFIG немає $v"
done
# Режим OQ-34 — з конфігу, як у тіку: інакше enqueue прийняв би те, що тік відхилить.
export A8_SOURCES_ALLOWED
Q="$A8_QUEUE_DIR"
URGENT="$Q/urgent"
PAUSE_FLAG="$A8_LOGS_DIR/planned-paused"
[[ -d "$Q" ]] || die 2 "немає теки черги $Q"

# Задачі черги й іменування — ті самі, що бачить тік: *.json у корені (плановий
# потік) і в urgent/ (невідкладні). Тимчасові файли починаються з крапки й
# закінчуються не на .json — тік їх не бачить.
STATE_DIRS=("$Q" "$URGENT" "$Q/running" "$Q/failed" "$Q/done")

# find_id <id> → друкує першу теку стану, де лежить задача з цим id (або нічого).
find_id() {
  local d f got
  for d in "${STATE_DIRS[@]}"; do
    [[ -d "$d" ]] || continue
    for f in "$d"/*.json; do
      [[ -e "$f" ]] || continue
      got="$(jq -r '.id // "" | tostring' "$f" 2>/dev/null)" || continue
      if [[ "$got" == "$1" ]]; then
        if [[ "$d" == "$Q" ]]; then echo planned; else echo "${d##*/}"; fi
        return 0
      fi
    done
  done
  return 0
}

count_json() { # count_json <тека>
  local n=0 f
  [[ -d "$1" ]] || {
    echo 0
    return 0
  }
  for f in "$1"/*.json; do [[ -e "$f" ]] && n=$((n + 1)); done
  echo "$n"
}

list_json() { # list_json <тека> [<скільки>] — імена файлів у порядку, в якому їх бере тік
  [[ -d "$1" ]] || return 0
  find "$1" -maxdepth 1 -type f -name '*.json' -printf '%f\n' | LC_ALL=C sort | head -n "${2:-20}"
}

# ─── status ─────────────────────────────────────────────────────────────────
do_status() {
  local grc=0 gout lock="вільний" n
  echo "== A8: стан черги ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
  if [[ -e "$A8_KILL_SWITCH" ]]; then
    echo "STOP: Є — $(head -c 300 "$A8_KILL_SWITCH" | head -n 1)"
  else
    echo "STOP: немає"
  fi
  gout="$("$GUARD" check 2>&1)" || grc=$?
  echo "запобіжники: $(bash "$LOGIC" guard-state "$grc") (a8-guard check → $grc: ${gout%%$'\n'*})"
  if [[ -e "$PAUSE_FLAG" ]]; then
    echo "плановий потік: ПАУЗА з $(head -n 1 "$PAUSE_FLAG") — тік бере лише urgent/"
  else
    echo "плановий потік: працює"
  fi
  # Lock перевіряється спробою взяти його на мить: якщо тік працює, спроба не
  # вдається. Тік, що стартує саме в цю мить, запише `busy` і візьме задачу
  # наступним тіком — ціна однієї миті, а не втрата задачі.
  if [[ -e "$A8_LOGS_DIR/tick.lock" ]] && ! flock -n "$A8_LOGS_DIR/tick.lock" true 2>/dev/null; then
    lock="ЗАЙНЯТИЙ (тік або requeue працює)"
  fi
  echo "tick.lock: $lock"
  echo "черга: urgent=$(count_json "$URGENT") planned=$(count_json "$Q") running=$(count_json "$Q/running") failed=$(count_json "$Q/failed") done=$(count_json "$Q/done") rejected=$(count_json "$Q/rejected")"
  for n in urgent planned running; do
    case "$n" in
      urgent) d="$URGENT" ;;
      planned) d="$Q" ;;
      running) d="$Q/running" ;;
    esac
    if [[ "$(count_json "$d")" != 0 ]]; then
      echo "-- $n (у порядку, в якому їх бере тік):"
      list_json "$d" 20 | sed 's/^/   /'
    fi
  done
  echo "-- last-results (хвіст):"
  tail -n 5 "$A8_LOGS_DIR/last-results" 2>/dev/null | sed 's/^/   /'
  # Останній ротований файл теж: logrotate ріже runs.log щодня, і хвіст живого
  # файла одразу після ротації порожній (#231, 13.10).
  echo "-- runs.log (останні 10 записів, з runs.log.1):"
  {
    [[ -f "$A8_LOGS_DIR/runs.log.1.gz" ]] && zcat -- "$A8_LOGS_DIR/runs.log.1.gz" 2>/dev/null
    [[ -f "$A8_LOGS_DIR/runs.log.1" ]] && cat -- "$A8_LOGS_DIR/runs.log.1"
    [[ -f "$A8_LOGS_DIR/runs.log" ]] && cat -- "$A8_LOGS_DIR/runs.log"
  } | tail -n 10 | sed 's/^/   /'
  log_detail="ok"
  return 0
}

# ─── enqueue ────────────────────────────────────────────────────────────────
do_enqueue() {
  local urgent=0 tmpdir tmp verdict id where dest name stamp size grc
  while (($# > 0)); do
    case "$1" in
      --urgent) urgent=1 ;;
      *) die 2 "enqueue: невідомий аргумент '$1' (задача йде лише через stdin)" ;;
    esac
    shift
  done

  if ((urgent)); then
    mkdir -p "$URGENT" || die 2 "не вдалося створити $URGENT"
    tmpdir="$URGENT"
  else
    tmpdir="$Q"
  fi
  # Тимчасовий файл — у тій самій теці, що й ціль: mv тоді атомарний. Назва з
  # крапкою і без .json — тік його не бачить, навіть якщо ми впадемо посередині.
  tmp="$(mktemp "$tmpdir/.enqueue.XXXXXX")" || die 2 "не вдалося створити тимчасовий файл у $tmpdir"
  enq_tmp="$tmp"

  # Не більше ліміту + 1 байт: так видно, що запис довший, без читання нескінченного stdin.
  head -c $((MAX_TASK_BYTES + 1)) >"$tmp" || die 2 "не вдалося прочитати stdin"
  size="$(wc -c <"$tmp")"
  ((size > 0)) || die 1 "порожній stdin — задачу не передано"
  ((size <= MAX_TASK_BYTES)) || die 1 "запис довший за $MAX_TASK_BYTES байт"

  verdict="$(bash "$LOGIC" validate "$tmp")" || die 1 "невалідний запис: ${verdict#reject }"
  id="$(jq -r '.id' "$tmp")"
  log_ids="$id"

  # Перевірка «id ще немає, невідкладної ще немає» і запис — під lock'ом стану
  # черги (див. LOCK у заголовку): інакше дві одночасні постановки обидві бачили б
  # порожньо й обидві писали б (рецензія Flash, PR #272), а переміщення тіком чи
  # requeue посеред перевірки ховало б задачу (контрприклад 3).
  { exec 7>"$A8_LOGS_DIR/queue.lock"; } 2>/dev/null || die 2 "не відкрито $A8_LOGS_DIR/queue.lock"
  flock -w 30 7 || die 3 "queue.lock зайнятий понад 30 с — нічого не змінено"

  where="$(find_id "$id")"
  [[ -z "$where" ]] || die 1 "id '$id' уже є в черзі ($where)"
  # Гілка лишається після done і після падіння з комітами: тік на ній упав би
  # «гілка вже існує» (a8-tick, крок 3) і записав би `failed`.
  # Помилка git (не «гілки немає», а, скажімо, «dubious ownership») — не «вільно».
  grc=0
  git -C "$A8_REPO_DIR" show-ref --verify --quiet "refs/heads/ai/$id" 2>/dev/null || grc=$?
  case "$grc" in
    0) die 1 "гілка ai/$id уже є в $A8_REPO_DIR — тік на ній упав би; новий id або a8-queue requeue" ;;
    1) ;;
    *) die 2 "git show-ref не вдався (код $grc) — не можу перевірити гілку ai/$id; у черзі нічого" ;;
  esac
  if ((urgent)); then
    # Одночасно — лише одна невідкладна: і в urgent/, і та, що вже йде.
    if [[ "$(count_json "$URGENT")" != 0 ]]; then
      die 1 "невідкладна задача вже чекає в urgent/ — одночасно лише одна"
    fi
    if compgen -G "$Q/running/urgent-*.json" >/dev/null; then
      die 1 "невідкладна задача вже виконується — одночасно лише одна"
    fi
  fi

  # Назва — час постановки з наносекундами: тік бере найменшу назву (LC_ALL=C).
  # Постановки йдуть по одній під queue.lock, тож мітки різні й порядок — порядок
  # постановки; з мітками в секундах дві задачі з однієї секунди йшли б за id
  # (контрприклад 4, PR #272). Не гарантує лише крок системного годинника назад.
  # requeue повертає задачу з її старою назвою — на первісне місце в черзі.
  # Префікс urgent- лишається за задачею в running/ — за ним видно, що
  # невідкладна ще йде.
  stamp="$(date -u +%Y%m%dT%H%M%S%NZ)"
  name="$stamp-$id.json"
  ((urgent)) && name="urgent-$name"
  dest="$tmpdir/$name"
  [[ ! -e "$dest" ]] || die 1 "файл $name уже є"
  # Лише для тесту гонки: затримка між перевірками й записом. Через ssh-ключ із
  # `restrict` змінних середовища не передати.
  [[ -z "${A8_ENQUEUE_HOLD_S:-}" ]] || sleep "$A8_ENQUEUE_HOLD_S"
  chmod 0644 "$tmp" || die 2 "chmod не вдався"
  mv -n -- "$tmp" "$dest" || die 2 "mv у чергу не вдався"
  [[ -e "$dest" && ! -e "$tmp" ]] || die 2 "файл $name не з'явився в черзі"
  enq_tmp=""

  "$JOURNAL" event enqueue "id=$id $( ((urgent)) && echo urgent || echo planned) file=$name via=$VIA" >/dev/null 2>&1 ||
    echo "a8-queue: УВАГА: задачу поставлено, але a8-journal не записав подію" >&2
  log_detail="ok $( ((urgent)) && echo urgent || echo planned) $name"
  echo "OK $id → ${dest#"$Q"/}"
  return 0
}

# ─── requeue ────────────────────────────────────────────────────────────────
do_requeue() {
  local a rc=0 flags=() ids=()
  for a in "$@"; do
    case "$a" in
      --reset-pause)
        [[ "$VIA" != ssh ]] ||
          die 1 "requeue --reset-pause через a8-ctl заборонено: паузу після падінь знімає людина (CLAUDE.md §0 п.7)"
        flags=(--reset-pause)
        ;;
      -*) die 2 "requeue: невідомий прапорець '$a' (дозволено лише --reset-pause)" ;;
      *)
        ids+=("$a")
        log_ids+="${log_ids:+ }$a"
        ;;
    esac
  done
  [[ -n "$log_ids" ]] || die 2 "requeue: потрібен хоча б один id"
  [[ -r "$REQUEUE" ]] || die 2 "немає $REQUEUE — роль A8 не застосована?"
  # --remote і --dry-run сюди не пропускаються: перший копіював би скрипт на інший
  # хост, другий тут не потрібен (є status).
  A8_CONFIG="$CONFIG" A8_JOURNAL="$JOURNAL" A8_GUARD="$GUARD" bash "$REQUEUE" "${flags[@]}" -- "${ids[@]}" || rc=$?
  case "$rc" in
    0) log_detail="ok" ;;
    1) log_detail="skip" ;;
    3) log_detail="busy" ;;
    *) log_detail="error rc=$rc" ;;
  esac
  return "$rc"
}

# ─── pause / resume ─────────────────────────────────────────────────────────
do_pause() {
  local tmp
  if [[ -e "$PAUSE_FLAG" ]]; then
    log_detail="already"
    echo "плановий потік уже на паузі з $(head -n 1 "$PAUSE_FLAG")"
    return 0
  fi
  tmp="$(mktemp "$A8_LOGS_DIR/.planned-paused.XXXXXX")" || die 2 "не вдалося створити прапорець паузи"
  date -u +%Y-%m-%dT%H:%M:%SZ >"$tmp" && mv -f -- "$tmp" "$PAUSE_FLAG" ||
    {
      rm -f -- "$tmp"
      die 2 "не вдалося записати $PAUSE_FLAG"
    }
  "$JOURNAL" event planned_paused "via=$VIA" >/dev/null 2>&1 || true
  log_detail="ok"
  echo "плановий потік на паузі; urgent/ тік бере й далі"
}

do_resume() {
  if [[ ! -e "$PAUSE_FLAG" ]]; then
    log_detail="already"
    echo "плановий потік і так працює"
    return 0
  fi
  rm -f -- "$PAUSE_FLAG" || die 2 "не вдалося прибрати $PAUSE_FLAG"
  "$JOURNAL" event planned_resumed "via=$VIA" >/dev/null 2>&1 || true
  log_detail="ok"
  echo "плановий потік відновлено"
}

case "$verb" in
  status)
    (($# == 0)) || die 2 "status без аргументів"
    do_status
    ;;
  enqueue) do_enqueue "${args[@]}" ;;
  requeue) do_requeue "${args[@]}" ;;
  pause)
    (($# == 0)) || die 2 "pause без аргументів"
    do_pause
    ;;
  resume)
    (($# == 0)) || die 2 "resume без аргументів"
    do_resume
    ;;
  _denied)
    # Лише для a8-ctl: записати в ctl.log відмову, яку він дав до a8-queue. Через
    # ключ недосяжне — a8-ctl пропускає тільки п'ять дієслів вище.
    verb="denied"
    log_detail="${args[0]:-}"
    exit 126
    ;;
  "") die 2 "потрібне дієслово: status | enqueue [--urgent] | requeue [--reset-pause] <id>… | pause | resume" ;;
  *) die 2 "невідоме дієслово '$verb' (status | enqueue | requeue | pause | resume)" ;;
esac
