#!/usr/bin/env bash
# a8-tick-logic.sh — логіка РІШЕНЬ демона черги A8, окремо від запуску.
#
# ЧОМУ ОКРЕМО. Демон (`infra/ansible/roles/a8/templates/a8-tick.sh.j2`) робить
# побічні дії: worktree, контейнер, push. Їх у CI не доведеш. Рішення — чи брати
# задачу, як назвати вихід, чи ставити паузу — чисті функції від входу, і саме
# вони визначають, чи демон зробить шкоду. Тому вони тут, під тестом
# (`a8-tick-logic.test.sh`), а демон їх лише викликає.
#
# Використання (CLI — так їх кличе демон):
#   a8-tick-logic.sh validate <task.json>        → "ok" (exit 0) | "reject <поля>" (exit 3)
#   a8-tick-logic.sh guard-state <rc>            → ok | kill_switch | daily_limit | paused | guard_error
#   a8-tick-logic.sh classify <rc> <log>         → "<клас> <деталь>"
#   a8-tick-logic.sh should-pause <limit> <файл> → "pause" (exit 0) | "continue" (exit 1)
#
# Або `source` і виклик функцій a8_* напряму.
set -uo pipefail

# ─── Запис черги ────────────────────────────────────────────────────────────
# Два НЕЗАЛЕЖНІ поля, два різні «ні» (рішення yurii, 2026-09-18, Q1-а):
#
#   source — ДОВІРА до тексту задачі (OQ-34): human | external | derived.
#            Режим (а) OQ-34: доки звужені набори дозволів для external/derived
#            не реалізовані й не покриті тестом, приймається лише human.
#            Це НЕ те саме, що «невідоме значення», тому окрема причина.
#   origin — ДЖЕРЕЛО задачі (CLAUDE.md §0, «три джерела, інших немає»):
#            direction (напрямок yurii) | analytics (аналітика платформи) |
#            feedback (зворотний зв'язок користувачів і виробництва).
#
# Плюс oracle (docs/02: задача без оракула в роботу не береться), id і prompt.
A8_SOURCES_KNOWN="human external derived"
A8_ORIGINS_KNOWN="direction analytics feedback"
# Перевизначається лише тестом або свідомою зміною режиму OQ-34.
A8_SOURCES_ALLOWED="${A8_SOURCES_ALLOWED:-human}"

_a8_in_list() { # _a8_in_list <значення> <список через пробіл>
  local v="$1" item
  for item in $2; do [[ "$item" == "$v" ]] && return 0; done
  return 1
}

# a8_validate_task <файл> — друкує "ok" або "reject <причина>[,<причина>...]".
#
# Причини названі ПОЛЕМ (`source:not-allowed`, `origin:missing` …), і
# перелічуються ВСІ, а не перша: запис у журналі мусить казати, котре саме поле
# відхилило задачу, а два fail closed — це два різні «ні».
a8_validate_task() {
  local file="$1" reasons=() id src origin oracle prompt
  if ! jq -e 'type == "object"' "$file" >/dev/null 2>&1; then
    echo "reject json"
    return 3
  fi
  # Поле, що є, але не рядок (`"oracle": {}`), — не «порожнє», а невалідне:
  # `tostring` зробив би з нього непорожній текст і пропустив би задачу.
  local f
  for f in id source origin oracle prompt; do
    if jq -e --arg k "$f" 'has($k) and (.[$k] | type) != "string"' "$file" >/dev/null; then
      reasons+=("$f:not-string")
    fi
  done
  id="$(jq -r '.id | strings' "$file")"
  src="$(jq -r '.source | strings' "$file")"
  origin="$(jq -r '.origin | strings' "$file")"
  oracle="$(jq -r '.oracle | strings' "$file")"
  prompt="$(jq -r '.prompt | strings' "$file")"

  # id іде в ім'я гілки й шляхи. Лише безпечний алфавіт — інакше
  # `../`, пробіл чи `;` у полі черги стали б частиною команди git/шляху.
  # Плюс правила git для імен гілок (`git check-ref-format`): без `..`, не
  # закінчується на `.lock` чи `.` — інакше `worktree add -b ai/<id>` упав би вже
  # ПІСЛЯ того, як задачу взято.
  if [[ -z "$id" ]]; then
    [[ " ${reasons[*]} " == *" id:not-string "* ]] || reasons+=("id:missing")
  elif [[ ! "$id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ || "$id" == *..* ||
    "$id" == *.lock || "$id" == *. ]]; then
    reasons+=("id:invalid")
  fi

  if [[ -z "$src" ]]; then
    [[ " ${reasons[*]} " == *" source:not-string "* ]] || reasons+=("source:missing")
  elif ! _a8_in_list "$src" "$A8_SOURCES_KNOWN"; then
    reasons+=("source:invalid")
  elif ! _a8_in_list "$src" "$A8_SOURCES_ALLOWED"; then
    reasons+=("source:not-allowed")
  fi

  if [[ -z "$origin" ]]; then
    [[ " ${reasons[*]} " == *" origin:not-string "* ]] || reasons+=("origin:missing")
  elif ! _a8_in_list "$origin" "$A8_ORIGINS_KNOWN"; then
    reasons+=("origin:invalid")
  fi

  # Порожній рядок і рядок із самих пробілів — однаково «оракула немає».
  if [[ -z "${oracle//[[:space:]]/}" && " ${reasons[*]} " != *" oracle:not-string "* ]]; then
    reasons+=("oracle:missing")
  fi
  if [[ -z "${prompt//[[:space:]]/}" && " ${reasons[*]} " != *" prompt:not-string "* ]]; then
    reasons+=("prompt:missing")
  fi

  if ((${#reasons[@]} > 0)); then
    local IFS=,
    echo "reject ${reasons[*]}"
    return 3
  fi
  echo "ok"
}

# ─── Коди a8-guard ──────────────────────────────────────────────────────────
# Три стани НЕ зливаються в одне «не працює»: пауза після падінь і вичерпаний
# ліміт лікуються по-різному (перше — людина дивиться журнал, друге — чекати
# доби). Невідомий код — guard_error, не «ok»: fail closed.
a8_guard_state() {
  case "$1" in
    0) echo ok ;;
    10) echo kill_switch ;;
    11) echo daily_limit ;;
    12) echo paused ;;
    *) echo guard_error ;;
  esac
}

# ─── Класифікатор виходу (ADR-039 §4) ───────────────────────────────────────
# Матчимо ЛИШЕ сигнатури, реально бачені в логах проєкту. 401 — дослівно
# (docs/13_PROGRESS_LOG.md, п'ять прогонів 2026-07; docs/17 §9):
#   `Failed to authenticate. API Error: 401 Invalid bearer token`, миттєвий
#   `is_error`, 0–1 turn, `total_cost_usd: 0`.
# Класу «quota» НЕМАЄ: сигнатуру вичерпаної квоти в проєкті не спостерігали
# жодного разу (ADR-039 §4, вимір №3 відкритий). Вигадати її регулярку — рівно
# та помилка, проти якої написаний CLAUDE.md §0 п.3. Усе невідоме → failed.
#
# НА ВХОДІ — ЛИШЕ вивід `claude` (демон пише його в окремий файл), а не спільний
# лог тіку: там `git fetch`, `pnpm install`, `check-hook-loud`.
#
# Коли вивід — JSON-результат (`--output-format json`), 401 визнається лише за
# ДОКУМЕНТОВАНОЮ формою: `is_error: true`, `num_turns` ≤ 1 і текст сигнатури в
# полі `result`. Агент, який читав ADR-039 чи docs/13 і процитував рядок —
# в успішному прогоні або в прогоні, що впав з іншої причини після багатьох
# кроків, — чергу не зупиняє (знайдено незалежним рев'ю №2 демона).
# Якщо JSON-результату немає зовсім (CLI впав раніше), шукаємо повну фразу в
# сирому виводі — формат такого падіння CLI у проєкті не виміряний.
#
# Коди 10/11/12 від a8-run-agent означають, що запобіжник спрацював уже в
# обгортці (між перевіркою демона і запуском контейнера) — це стоп, не падіння.
A8_SIG_401='Failed to authenticate. API Error: 401 Invalid bearer token'

a8_classify() {
  local rc="$1" out="$2" res is_error=0 auth=0
  # Останній JSON-об'єкт із полем is_error — результат прогону.
  # Порядково і толерантно: поруч із JSON-результатом бувають рядки stderr, а
  # звичайний `jq` на першому не-JSON рядку зупинився б і результату не знайшов.
  res="$(jq -cR 'fromjson? | select(type == "object" and has("is_error"))' "$out" 2>/dev/null | tail -n 1)"
  if [[ -n "$res" ]]; then
    [[ "$(jq -r '.is_error' <<<"$res")" == true ]] && is_error=1
    if ((is_error)) &&
      jq -e --arg s "$A8_SIG_401" '(.result // "" | tostring | contains($s)) and ((.num_turns // 0) <= 1)' \
        <<<"$res" >/dev/null; then
      auth=1
    fi
  elif [[ "$rc" != 0 ]] && grep -Fq "$A8_SIG_401" "$out" 2>/dev/null; then
    auth=1
  fi

  if ((auth)); then
    echo "auth_stop 401"
    return
  fi
  case "$rc" in
    10 | 11 | 12)
      echo "stopped $(a8_guard_state "$rc")"
      return
      ;;
  esac
  if [[ "$rc" == 0 ]] && ((!is_error)); then
    echo "ok -"
  elif [[ "$rc" == 124 ]]; then
    echo "failed timeout"
  elif [[ "$rc" == 0 ]]; then
    echo "failed is_error"
  else
    echo "failed rc=$rc"
  fi
}

# ─── Пауза після N падінь поспіль ───────────────────────────────────────────
# Та сама нормалізація, що в a8-guard (порожні рядки, \r, хвостові пробіли) —
# інакше демон і guard рахували б падіння по-різному, і пауза вмикалась би не
# на тому кроці, на якому її читає guard.
a8_should_pause() { # a8_should_pause <limit> <файл last-results>
  local limit="$1" file="$2" n
  [[ -r "$file" ]] || { echo continue; return 1; }
  n="$(tr -d '\r' <"$file" | sed 's/[[:space:]]*$//' | grep -v '^$' |
    tail -n "$limit" | grep -c '^failed$' || true)"
  if ((n >= limit)); then
    echo pause
    return 0
  fi
  echo continue
  return 1
}

# ─── CLI ────────────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  cmd="${1:-}"
  shift || true
  case "$cmd" in
    validate) a8_validate_task "$@" ;;
    guard-state) a8_guard_state "$@" ;;
    classify) a8_classify "$@" ;;
    should-pause) a8_should_pause "$@" ;;
    *)
      echo "використання: $0 {validate|guard-state|classify|should-pause} ..." >&2
      exit 1
      ;;
  esac
fi
