#!/usr/bin/env bash
# check-monitor-script.test.sh — скрипт монітора staging правильно розрізняє здорові й хворі
# контейнери і не губить алерти.
#
# Навіщо: 2026-09-25 після переїзду staging монітор (monitor.sh.j2) брав стан здоров'я з поля
# `.Status` у `docker ps`. Там рядок «Up 5 hours (healthy)», який ніколи не дорівнює `healthy`,
# тож кожен здоровий контейнер ставав «проблемою». Перший алерт Discord відхилив (title 560
# символів при ліміті 256), а стан PROBLEM усе одно записався — повтору вже не було б.
#
# Як: шаблон рендериться Jinja зі змінними ролі, `docker` і `curl` підмінено. Підмінений `docker`
# віддає поля такого вигляду, як справжній на сервері 2026-09-25 (`docker ps` → «Up 5 hours
# (healthy)», `docker inspect` → `healthy`), без `-a` не показує зупинених контейнерів, як і
# справжній, і падає на полі, якого не знає, — щоб тест не зеленів на шаблоні, який питає в docker
# щось інше.
#
# Запуск: tools/scripts/check-monitor-script.test.sh [шлях до monitor.sh.j2]
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TPL="${1:-$ROOT/infra/ansible/roles/monitoring/templates/monitor.sh.j2}"
fail=0
ok() { echo "✓ $1"; }
bad() {
  echo "✗ $1"
  fail=1
}

for dep in jq python3; do
  command -v "$dep" >/dev/null || {
    echo "✗ немає $dep — перевірити монітор неможливо"
    exit 1
  }
done
if ! python3 -c 'import jinja2' 2>/dev/null; then
  echo "✗ немає python3-модуля jinja2 — перевірити монітор неможливо"
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

# Рендер як у модуля template в Ansible (trim_blocks). StrictUndefined: нова змінна в шаблоні
# без значення тут — падіння тесту, а не порожній рядок.
render_tpl() { # render_tpl <поріг диска, %> <куди>
  python3 - "$TPL" "$1" "$2" <<'PY'
import sys, jinja2
env = jinja2.Environment(trim_blocks=True, keep_trailing_newline=True, undefined=jinja2.StrictUndefined)
src = open(sys.argv[1], encoding="utf-8").read()
out = env.from_string(src).render(
    ansible_managed="test",
    monitor_interval_minutes=5,
    monitor_disk_threshold_pct=int(sys.argv[2]),
    discord_webhook="http://webhook.invalid/",
)
open(sys.argv[3], "w", encoding="utf-8").write(out)
PY
}
render_tpl 101 "$tmp/monitor.sh" || exit 1    # диск не дає проблем
render_tpl 0 "$tmp/monitor-disk.sh" || exit 1 # диск завжди «вище порогу»

# Фікстура: рядок на контейнер — ім'я|State.Status|State.Health.Status (порожньо = без
# healthcheck)|поле .Status у docker ps. Прапорці ps — окремо (`-a -q`), як у шаблоні.
cat >"$tmp/bin/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
sub=$1
shift
fmt="" quiet=0 all=0 ids=()
while [ $# -gt 0 ]; do
  case $1 in
    --format) fmt=$2; shift 2 ;;
    --filter) shift 2 ;;
    -q) quiet=1; shift ;;
    -a) all=1; shift ;;
    *) ids+=("$1"); shift ;;
  esac
done
render() { # render <ім'я> <state> <health> <ps-status>
  local out=$fmt h=${3:-none}
  out=${out//'{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}'/$h}
  out=${out//'{{.Name}}'//$1}
  out=${out//'{{.Names}}'/$1}
  out=${out//'{{.State.Status}}'/$2}
  out=${out//'{{.State}}'/$2}
  out=${out//'{{.Status}}'/$4}
  case $out in *'{{'*)
    echo "підмінений docker: невідоме поле в шаблоні: $out" >&2
    exit 2 ;;
  esac
  printf '%s\n' "$out"
}
while IFS='|' read -r name state health ps_status; do
  [ -n "$name" ] || continue
  case $sub in
    ps)
      # Без -a справжній docker ps не показує exited/created/dead.
      case $state in running | restarting | paused) ;; *) [ "$all" = 1 ] || continue ;; esac
      if [ "$quiet" = 1 ]; then echo "$name"; else render "$name" "$state" "$health" "$ps_status"; fi ;;
    inspect) for id in "${ids[@]}"; do [ "$id" = "$name" ] && render "$name" "$state" "$health" "$ps_status"; done ;;
    *) echo "підмінений docker: невідома команда $sub" >&2; exit 2 ;;
  esac
done <"$FAKE_DOCKER_FIXTURE"
SH
# Один виклик — один рядок «CALL <тіло -d одним рядком JSON>». FAKE_CURL_FAIL=1 — webhook
# відповідає 400, як 2026-09-25.
cat >"$tmp/bin/curl" <<'SH'
#!/usr/bin/env bash
body=""
while [ $# -gt 0 ]; do case $1 in -d) body=$2; shift 2 ;; *) shift ;; esac; done
printf 'CALL %s\n' "$(printf '%s' "$body" | jq -c .)" >>"$FAKE_CURL_LOG"
if [ "${FAKE_CURL_FAIL:-0}" = 1 ]; then
  echo "curl: (22) The requested URL returned error: 400" >&2
  exit 22
fi
SH
chmod +x "$tmp/bin/docker" "$tmp/bin/curl"

# run <фікстура> <попередній стан або ""> [скрипт] → OUT, STATE, CALLS. CURL_FAIL=1 — webhook падає.
CURL_FAIL=0
run() {
  printf '%s\n' "$1" >"$tmp/fixture"
  rm -f "$tmp/state" "$tmp/curl.log"
  : >"$tmp/curl.log"
  [ -n "$2" ] && echo "$2" >"$tmp/state"
  OUT=$(PATH="$tmp/bin:$PATH" MONITOR_STATE_FILE="$tmp/state" FAKE_DOCKER_FIXTURE="$tmp/fixture" \
    FAKE_CURL_LOG="$tmp/curl.log" FAKE_CURL_FAIL="$CURL_FAIL" bash "${3:-$tmp/monitor.sh}" 2>&1)
  STATE=$(cat "$tmp/state" 2>/dev/null)
  CALLS=$(grep -c '^CALL' "$tmp/curl.log")
}

# Сім сервісів staging — рядки як у `docker ps` на сервері 2026-09-25.
healthy_stack() {
  local s
  for s in caddy web api umami cad-worker postgres redis; do
    echo "flatcraft-$s-1|running|healthy|Up 5 hours (healthy)"
  done
}
# with <сервіс> <state|health|ps-status> — здоровий стек, де один сервіс замінено.
with() { healthy_stack | sed "s/^flatcraft-$1-1|.*/flatcraft-$1-1|$2/"; }

# Ліміти Discord для embed: title ≤ 256, description ≤ 4096. Інакше webhook відповідає 400 і
# сповіщення не доходить (2026-09-25: title на 560 символів).
discord_limits_ok() {
  sed -n 's/^CALL //p' "$tmp/curl.log" |
    jq -e -s 'length > 0 and all(.[].embeds[]; (.title | length) <= 256 and ((.description // "") | length) <= 4096)' >/dev/null
}

run "$(healthy_stack)" ""
if [[ $OUT == *"OK (disk"*", 7 containers)"* && $STATE == OK && $CALLS == 0 ]]; then
  ok "усі сім здорові → OK, без сповіщення"
else
  bad "усі сім здорові → очікувано OK без сповіщення; стан=$STATE, сповіщень=$CALLS, вивід: $OUT"
fi

run "$(with api 'running|unhealthy|Up 5 hours (unhealthy)')" ""
if [[ $OUT == *"PROBLEMS: Container flatcraft-api-1 health=unhealthy (state=running)" && $STATE == PROBLEM && $CALLS == 1 ]] &&
  grep -q '\[ERROR\]' "$tmp/curl.log"; then
  ok "один unhealthy → PROBLEM лише для нього, одне сповіщення ERROR"
else
  bad "один unhealthy → очікувано PROBLEM лише для api; стан=$STATE, сповіщень=$CALLS, вивід: $OUT"
fi

run "$(healthy_stack)" "PROBLEM"
if [[ $STATE == OK && $CALLS == 1 ]] && grep -q '\[OK\]' "$tmp/curl.log"; then
  ok "після PROBLEM усі здорові → OK і сповіщення про відновлення"
else
  bad "відновлення → очікувано OK і одне сповіщення OK; стан=$STATE, сповіщень=$CALLS, вивід: $OUT"
fi

run "flatcraft-web-1|running|starting|Up 3 seconds (health: starting)
flatcraft-redis-1|running||Up 5 hours" ""
if [[ $STATE == OK && $CALLS == 0 ]]; then
  ok "starting і контейнер без healthcheck — не проблема"
else
  bad "starting / без healthcheck → очікувано OK; стан=$STATE, вивід: $OUT"
fi

run "$(healthy_stack | sed 's/|healthy|Up 5 hours (healthy)$/|unhealthy|Up 5 hours (unhealthy)/')" ""
if [[ $STATE == PROBLEM && $CALLS == 1 ]] && discord_limits_ok &&
  sed -n 's/^CALL //p' "$tmp/curl.log" | jq -e '.embeds[0].description | contains("flatcraft-redis-1")' >/dev/null; then
  ok "сім unhealthy → одне сповіщення в межах лімітів Discord, усі сім у тексті"
else
  bad "сім unhealthy → сповіщення поза лімітами Discord або без усіх контейнерів; сповіщень=$CALLS, тіло: $(cat "$tmp/curl.log")"
fi

# Впалий контейнер: після on-failure:5 він exited, а останній health лишається, яким був.
run "$(with api 'exited|healthy|Exited (1) 2 minutes ago')" "PROBLEM"
if [[ $OUT == *"PROBLEMS: Container flatcraft-api-1 health=healthy (state=exited)" && $STATE == PROBLEM && $CALLS == 0 ]]; then
  ok "контейнер exited серед шести робочих → PROBLEM, а не хибне «recovered»"
else
  bad "exited → очікувано PROBLEM без «recovered»; стан=$STATE, сповіщень=$CALLS, вивід: $OUT"
fi

run "$(with redis 'restarting||Restarting (1) 5 seconds ago')" ""
if [[ $OUT == *"PROBLEMS: Container flatcraft-redis-1 health=none (state=restarting)" && $STATE == PROBLEM ]]; then
  ok "контейнер без healthcheck у restarting → PROBLEM"
else
  bad "restarting без healthcheck → очікувано PROBLEM; стан=$STATE, вивід: $OUT"
fi

run "$(healthy_stack)" "" "$tmp/monitor-disk.sh"
if [[ $OUT == *"PROBLEMS: Disk usage / = "*"% (threshold 0%)"* && $STATE == PROBLEM && $CALLS == 1 ]]; then
  ok "диск вище порогу → PROBLEM і сповіщення"
else
  bad "диск → очікувано PROBLEM зі сповіщенням; стан=$STATE, сповіщень=$CALLS, вивід: $OUT"
fi

# Webhook не прийняв сповіщення → стан не міняється, наступний запуск повторить спробу.
CURL_FAIL=1
run "$(with api 'running|unhealthy|Up 5 hours (unhealthy)')" ""
if [[ $OUT == *"WARNING: Discord notify failed"* && $STATE != PROBLEM && $CALLS == 1 ]]; then
  ok "алерт не доставлено → стан PROBLEM не записано, буде повтор"
else
  bad "недоставлений алерт → очікувано без стану PROBLEM; стан=$STATE, сповіщень=$CALLS, вивід: $OUT"
fi
run "$(healthy_stack)" "PROBLEM"
if [[ $OUT == *"не доставлено"* && $STATE == PROBLEM && $CALLS == 1 ]]; then
  ok "«recovered» не доставлено → стан лишається PROBLEM, буде повтор"
else
  bad "недоставлене відновлення → очікувано стан PROBLEM; стан=$STATE, сповіщень=$CALLS, вивід: $OUT"
fi
CURL_FAIL=0

run "" ""
if [[ $OUT == *"Stack down: 0 containers running."* && $STATE == PROBLEM ]]; then
  ok "жодного контейнера → Stack down"
else
  bad "жодного контейнера → очікувано Stack down; стан=$STATE, вивід: $OUT"
fi

exit "$fail"
