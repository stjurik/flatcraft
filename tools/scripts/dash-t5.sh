#!/usr/bin/env bash
# dash-t5.sh — розділ "t5" пульту розробки (ADR-042 §6): стан восьми кроків треку T5
# з docs/02_ROADMAP.md.
#
# ЧОМУ ТАК. Критерії кроків T5, які рахує a8-metrics.sh, читаються через a8-ro-shell
# лише обмеженим набором дієслів (ADR-042 §4) — доступу до a8-metrics.sh --json
# немає до хвилі 4. Вигадувати ці числа заборонено (CLAUDE.md §0 п.3): замість нуля чи
# прочерку без пояснення data.a8 — явний статус "not_measured" з поясненням, де їх
# брати, аж до хвилі 4.
#
# ФОРМАТ КРОКУ. Нумерований список у розділі «### T5. …» (до наступного заголовка):
# «N. ✅ **Назва**» — крок закрито; «N. **Назва**» — відкрито. Рівно 8 кроків —
# інакше розділ відхилено як error, а не мовчки обрізаний чи дописаний порожніми.
#
# Використання: dash-t5.sh [--roadmap FILE] [--now T]
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA_SH="$HERE/dash-schema.sh"
ROADMAP="$HERE/../../docs/02_ROADMAP.md"
SOURCE_LABEL="docs/02_ROADMAP.md"
NOW_ARG=""

while (($#)); do
  case "$1" in
    --roadmap)
      [[ $# -ge 2 ]] || { echo "відмова: --roadmap потребує значення" >&2; exit 2; }
      ROADMAP="$2"
      SOURCE_LABEL="$2"
      shift 2
      ;;
    --now)
      [[ $# -ge 2 ]] || { echo "відмова: --now потребує значення" >&2; exit 2; }
      NOW_ARG="$2"
      shift 2
      ;;
    *)
      echo "відмова: невідомий прапорець «$1»" >&2
      exit 2
      ;;
  esac
done

[[ -r "$SCHEMA_SH" ]] || {
  echo "відмова: немає $SCHEMA_SH" >&2
  exit 2
}
[[ -r "$ROADMAP" ]] || {
  echo "відмова: немає файла «$ROADMAP»" >&2
  exit 2
}

# ─── розділ «### T5. …» до наступного заголовка (будь-якого рівня) ─────────
section="$(awk '
  /^### T5\./ { on=1; next }
  on && /^#/ { exit }
  on { print }
' "$ROADMAP")"

status=ok
reason=""
steps_json="[]"
first_open_json="null"

if [[ -z "$section" ]]; then
  status=error
  reason="розділ «### T5.» не знайдено в $ROADMAP"
else
  lines=()
  while IFS= read -r line; do
    # «N. ✅ **Назва**» — закрито; «N. **Назва**» — відкрито (друга група — лише маркер).
    if [[ "$line" =~ ^([0-9]+)\.[[:space:]]+(✅[[:space:]]+)?\*\*([^*]+)\*\* ]]; then
      n="${BASH_REMATCH[1]}"
      marker="${BASH_REMATCH[2]}"
      title="${BASH_REMATCH[3]}"
      closed=false
      [[ -n "$marker" ]] && closed=true
      lines+=("$n"$'\x1f'"$title"$'\x1f'"$closed")
    fi
  done <<<"$section"

  if ((${#lines[@]} != 8)); then
    status=error
    reason="очікував 8 кроків у «### T5.», отримано ${#lines[@]}"
  else
    steps_json="$(printf '%s\n' "${lines[@]}" | jq -R -s '
      split("\n") | map(select(length > 0)) | map(split("")) |
      map({n: (.[0] | tonumber), title: .[1], closed: (.[2] == "true")})
    ')"
    first_open_json="$(jq -c '(map(select(.closed == false)) | min_by(.n) | .n) // null' <<<"$steps_json")"
  fi
fi

data="$(jq -n \
  --argjson steps "$steps_json" \
  --argjson first_open "$first_open_json" \
  '{steps: $steps, first_open: $first_open,
    a8: {status: "not_measured", reason: "потрібен доступ до A8 — хвиля 4"}}')"

if [[ "$status" == error ]]; then
  data="$(jq --arg reason "$reason" '. + {error: $reason}' <<<"$data")"
fi

args=(envelope t5 "Трек T5" "$SOURCE_LABEL" 3600 measured "$status" "$data")
[[ -n "$NOW_ARG" ]] && args+=(--now "$NOW_ARG")
bash "$SCHEMA_SH" "${args[@]}"
