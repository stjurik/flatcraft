#!/usr/bin/env bash
# dash-schema.sh — основа пульту розробки (ADR-042 §2): обгортка розділу знімка,
# перевірка «застарів?» і валідація проти tools/dashboard/snapshot.schema.json.
#
# ЧОМУ ЦЕ ОКРЕМО. Кожен майбутній збирач (dash-a8.sh, dash-inbox.sh, …) друкує один
# розділ у тій самій обгортці й має проходити ту саму перевірку застарілості —
# дублювати цю логіку в кожному збирачі значить розійтись із нею в одному з них
# (той самий урок, що journal-rules.sh, issue #169). Дозволені значення status і
# origin беруться зі схеми через jq, а не дублюються тут другий раз (ADR-042 §2).
#
# ЧЕСНІСТЬ ДАНИХ (ADR-042 §3) — головний інваріант: розділ, старший за
# 3 × interval_s, — stale; час «у майбутньому» на знімку — несправний годинник,
# а не свіжі дані, тож це окремий вихід, не «свіже».
#
# Використання (CLI):
#   dash-schema.sh envelope <section> <title> <source> <interval_s> <origin> <status> \
#                   <data.json | JSON-об'єкт> [--now 'РРРР-ММ-ДДTГГ:ХХ:ССZ']
#       → друкує обгортку розділу (compact JSON) в stdout.
#   dash-schema.sh stale <collected_at> <interval_s> [--now 'РРРР-ММ-ДДTГГ:ХХ:ССZ']
#       → друкує "stale" (exit 0), "fresh" (exit 1) або "clock" (exit 2) —
#         collected_at у майбутньому більш ніж на interval_s.
#   dash-schema.sh validate <файл>
#       → друкує "ok" (exit 0) або "reject <поле>[,<поле>…]" (exit 3, усі причини;
#         зайве поле, якого немає в схемі, — його назвою; не один JSON-документ — json).
#
# Час — лише UTC. `--now` замінює системний час; тести завжди його задають, щоб не
# залежати від моменту запуску.
#
# Або `source tools/scripts/dash-schema.sh` і виклик функцій dash_* напряму —
# саме так це робитимуть майбутні збирачі dash-<розділ>.sh.
#
# DASH_SCHEMA_FILE — шлях до snapshot.schema.json (дефолт — поруч, tools/dashboard/).
set -uo pipefail

DASH_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASH_SCHEMA_FILE="${DASH_SCHEMA_FILE:-$DASH_HERE/../dashboard/snapshot.schema.json}"

DASH_TS_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'

# dash_epoch <РРРР-ММ-ДДTГГ:ХХ:ССZ> — секунди з епохи (UTC) або помилка (exit 1).
# Дата мусить існувати в календарі: 2026-02-30 чи 25:70 відхиляються, а не
# нормалізуються (рецензія Gemini 3.8 Flash, #197; правка оркестратора).
dash_epoch() {
  local ts="$1" s
  [[ "$ts" =~ $DASH_TS_RE ]] || return 1
  s="$(date -u -d "$ts" +%s 2>/dev/null)" || return 1
  [[ "$(date -u -d "@$s" +%Y-%m-%dT%H:%M:%SZ)" == "$ts" ]] || return 1
  printf '%s\n' "$s"
}

# dash_now <--now T> — час «зараз»: аргумент, якщо заданий, інакше системний UTC.
dash_now() {
  local now="$1"
  [[ -n "$now" ]] && { printf '%s\n' "$now"; return 0; }
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# ─── envelope ───────────────────────────────────────────────────────────────
dash_envelope() {
  if (($# < 7)); then
    echo "використання: dash-schema.sh envelope <section> <title> <source> <interval_s> <origin> <status> <data.json | JSON-об'єкт> [--now T]" >&2
    return 2
  fi
  local section="$1" title="$2" source="$3" interval_s="$4" origin="$5" status="$6" data="$7"
  shift 7
  local now_arg=""
  while (($#)); do
    case "$1" in
      --now)
        [[ $# -ge 2 ]] || { echo "відмова: --now потребує значення" >&2; return 2; }
        now_arg="$2"
        shift 2
        ;;
      *)
        echo "відмова: невідомий прапорець «$1»" >&2
        return 2
        ;;
    esac
  done
  [[ "$interval_s" =~ ^[1-9][0-9]*$ ]] || {
    echo "відмова: interval_s має бути додатним цілим, отримано «$interval_s»" >&2
    return 2
  }
  # data — файл (#161: <data.json>, зокрема <(…)) або сам JSON-об'єкт рядком.
  if [[ ! "$data" =~ ^[[:space:]]*[\{\[] ]]; then
    [[ -r "$data" ]] || {
      echo "відмова: data — не JSON і не файл, що читається: $data" >&2
      return 2
    }
    data="$(<"$data")"
  fi
  jq -e . >/dev/null 2>&1 <<<"$data" || {
    echo "відмова: data не є JSON: $data" >&2
    return 2
  }
  [[ "$(jq -r 'type' <<<"$data")" == object ]] || {
    echo "відмова: data має бути JSON-об'єктом, отримано: $data" >&2
    return 2
  }
  local ts
  ts="$(dash_now "$now_arg")"
  dash_epoch "$ts" >/dev/null || {
    echo "відмова: час має бути UTC ISO 8601 (РРРР-ММ-ДДTГГ:ХХ:ССZ), отримано «$ts»" >&2
    return 2
  }
  jq -nc \
    --arg section "$section" \
    --arg title "$title" \
    --arg source "$source" \
    --argjson interval_s "$interval_s" \
    --arg origin "$origin" \
    --arg status "$status" \
    --arg collected_at "$ts" \
    --argjson data "$data" \
    '{schema_version: 1, section: $section, title: $title, source: $source,
      collected_at: $collected_at, interval_s: $interval_s, status: $status,
      origin: $origin, data: $data}'
}

# ─── stale ──────────────────────────────────────────────────────────────────
dash_stale() {
  if (($# < 2)); then
    echo "використання: dash-schema.sh stale <collected_at> <interval_s> [--now T]" >&2
    return 2
  fi
  local collected_at="$1" interval_s="$2"
  shift 2
  local now_arg=""
  while (($#)); do
    case "$1" in
      --now)
        [[ $# -ge 2 ]] || { echo "відмова: --now потребує значення" >&2; return 2; }
        now_arg="$2"
        shift 2
        ;;
      *)
        echo "відмова: невідомий прапорець «$1»" >&2
        return 2
        ;;
    esac
  done
  [[ "$interval_s" =~ ^[1-9][0-9]*$ ]] || {
    echo "відмова: interval_s має бути додатним цілим, отримано «$interval_s»" >&2
    return 2
  }
  local now_ts now_s col_s
  now_ts="$(dash_now "$now_arg")"
  now_s="$(dash_epoch "$now_ts")" || {
    echo "відмова: --now має бути UTC ISO 8601 (РРРР-ММ-ДДTГГ:ХХ:ССZ), отримано «$now_ts»" >&2
    return 2
  }
  col_s="$(dash_epoch "$collected_at")" || {
    echo "відмова: collected_at має бути UTC ISO 8601 (РРРР-ММ-ДДTГГ:ХХ:ССZ), отримано «$collected_at»" >&2
    return 2
  }
  local future=$((col_s - now_s))
  local age=$((now_s - col_s))
  # Майбутнє більш ніж на interval_s — несправний годинник, не «свіже» (ADR-042 §3).
  if ((future > interval_s)); then
    echo clock
    return 2
  fi
  # Старший за 3 × interval_s — stale; рівно на межі лишається свіжим (ADR-042 §3 п.1).
  if ((age > 3 * interval_s)); then
    echo stale
    return 0
  fi
  echo fresh
  return 1
}

# ─── validate ───────────────────────────────────────────────────────────────
dash_validate() {
  if (($# != 1)); then
    echo "використання: dash-schema.sh validate <файл>" >&2
    return 2
  fi
  local file="$1"
  [[ -r "$DASH_SCHEMA_FILE" ]] || {
    echo "відмова: немає схеми $DASH_SCHEMA_FILE" >&2
    return 2
  }
  [[ -f "$file" ]] || {
    echo "відмова: немає файла «$file»" >&2
    return 2
  }
  # Рівно один JSON-документ: `{…}{…}` інакше пройшов би за першим (рецензія Flash, #197).
  [[ "$(jq -s 'length' "$file" 2>/dev/null)" == 1 ]] || {
    echo "reject json"
    return 3
  }
  local out
  out="$(jq -nr --slurpfile schema "$DASH_SCHEMA_FILE" --slurpfile d "$file" '
    ($schema[0]) as $s
    | ($d[0]) as $data
    | ($s.properties.status.enum) as $status_enum
    | ($s.properties.origin.enum) as $origin_enum
    | ($s.properties.collected_at.pattern) as $ts_pattern
    | (if ($data | type) != "object"
       then ["schema_version", "section", "title", "source", "collected_at",
             "interval_s", "status", "origin", "data"]
       else [
          (if ($data.schema_version? == 1) then empty else "schema_version" end),
          (if ($data.section? | type == "string" and length > 0) then empty else "section" end),
          (if ($data.title? | type == "string" and length > 0) then empty else "title" end),
          (if ($data.source? | type == "string" and length > 0) then empty else "source" end),
          (if ($data.collected_at? | (type == "string") and test($ts_pattern)
               and (try (strptime("%Y-%m-%dT%H:%M:%SZ") | mktime | todate) catch null) == .)
           then empty else "collected_at" end),
          (if ($data.interval_s? | type == "number" and . > 0 and (. | floor) == .) then empty else "interval_s" end),
          (if (($data.status? // null) as $v | $v != null and ($status_enum | index($v)) != null) then empty else "status" end),
          (if (($data.origin? // null) as $v | $v != null and ($origin_enum | index($v)) != null) then empty else "origin" end),
          (if ($data.data? | type == "object") then empty else "data" end),
          # additionalProperties: false — перелік полів теж зі схеми (рецензія Flash, #197).
          (($data | keys) - ($s.properties | keys) | .[])
        ]
       end) as $bad
    | if ($bad | length) == 0 then "ok" else "reject " + ($bad | join(",")) end
  ')" || {
    echo "відмова: схема чи файл не прочитались" >&2
    return 2
  }
  echo "$out"
  [[ "$out" == ok ]] && return 0
  return 3
}

# ─── CLI ────────────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  cmd="${1:-}"
  shift || true
  case "$cmd" in
    envelope) dash_envelope "$@" ;;
    stale) dash_stale "$@" ;;
    validate) dash_validate "$@" ;;
    *)
      echo "використання: $0 {envelope|stale|validate} ..." >&2
      exit 2
      ;;
  esac
fi
