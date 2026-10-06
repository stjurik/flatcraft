#!/usr/bin/env bash
# dash-trend.sh — розділ "trend" пульту розробки (ADR-042 §6): коміти в main по
# тижнях, продукт/процес.
#
# Продукт — коміт, що зачіпає хоч один файл у apps/, workers/ або packages/; решта —
# процес (docs/, tools/, infra/, .github/, корінь репо). Тиждень — від понеділка
# 00:00:00 UTC (ISO-календар), межа — рівно північ UTC, не локальний час машини.
#
# collected_at/час — лише UTC, --now підмінює системний (тести завжди його задають).
#
# Використання: dash-trend.sh [--repo DIR] [--ref origin/main] [--weeks N] [--now T]
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA_SH="$HERE/dash-schema.sh"
REPO="$HERE/../.."
REF="origin/main"
WEEKS=13
NOW_ARG=""

while (($#)); do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || { echo "відмова: --repo потребує значення" >&2; exit 2; }
      REPO="$2"
      shift 2
      ;;
    --ref)
      [[ $# -ge 2 ]] || { echo "відмова: --ref потребує значення" >&2; exit 2; }
      REF="$2"
      shift 2
      ;;
    --weeks)
      [[ $# -ge 2 ]] || { echo "відмова: --weeks потребує значення" >&2; exit 2; }
      WEEKS="$2"
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
[[ "$WEEKS" =~ ^[1-9][0-9]*$ ]] || {
  echo "відмова: --weeks має бути додатним цілим, отримано «$WEEKS»" >&2
  exit 2
}
git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "відмова: «$REPO» не git-репозиторій" >&2
  exit 2
}
git -C "$REPO" rev-parse --verify -q "$REF" >/dev/null || {
  echo "відмова: немає ref «$REF» у «$REPO»" >&2
  exit 2
}

if [[ -n "$NOW_ARG" ]]; then
  now_epoch="$(date -u -d "$NOW_ARG" +%s 2>/dev/null)" || {
    echo "відмова: --now має бути UTC ISO 8601 (РРРР-ММ-ДДTГГ:ХХ:ССZ), отримано «$NOW_ARG»" >&2
    exit 2
  }
else
  now_epoch="$(date -u +%s)"
fi

# monday_epoch_of <epoch> — епоха понеділка 00:00:00 UTC тижня, що містить <epoch>.
# Unix-епоха — завжди UTC і без високосних секунд, тож день завжди 86400 с; 1970-01-01
# (epoch=0) — четвер (ISO 4), звідси зсув +3 у формулі ISO-дня тижня.
monday_epoch_of() {
  local e="$1" day_start day_index iso_wd
  day_start=$((e - ((e % 86400 + 86400) % 86400)))
  day_index=$((day_start / 86400))
  iso_wd=$(((day_index + 3) % 7))
  ((iso_wd < 0)) && iso_wd=$((iso_wd + 7))
  iso_wd=$((iso_wd + 1))
  echo $((day_start - (iso_wd - 1) * 86400))
}

current_week_start="$(monday_epoch_of "$now_epoch")"
first_week_start=$((current_week_start - (WEEKS - 1) * 7 * 86400))

# ─── усі коміти ref: epoch\x1fsha\x1fsubject, далі файли до наступного маркера ──
# --first-parent --diff-merges=first-parent: один запис на коміт, що ліг у ref; merge —
# з файлами, які він приніс (без цього merge без файлів ішов у «процес», а коміти
# гілки рахувались ще й окремо). core.quotePath=false: інакше «apps/документ.txt»
# друкується в лапках і не впізнається як продукт. Правка оркестратора за рецензією
# Gemini 3.8 Flash (#204).
log_out="$(git -C "$REPO" -c core.quotePath=false log "$REF" --first-parent --diff-merges=first-parent \
  --format=$'\x01%ct\x1f%H\x1f%s' --name-only 2>/dev/null)" || {
  echo "відмова: git log по «$REF» не вдався" >&2
  exit 2
}

declare -A week_product week_process
w=$first_week_start
while ((w <= current_week_start)); do
  week_product["$w"]=0
  week_process["$w"]=0
  w=$((w + 7 * 86400))
done

commit_epoch="" commit_sha="" commit_subject="" is_product=0 have_commit=0
last_product_epoch=-1 last_product_sha="" last_product_subject=""

flush_commit() {
  ((have_commit)) || return 0
  local wk
  wk="$(monday_epoch_of "$commit_epoch")"
  if ((is_product)); then
    if ((commit_epoch > last_product_epoch)); then
      last_product_epoch="$commit_epoch"
      last_product_sha="$commit_sha"
      last_product_subject="$commit_subject"
    fi
    if ((wk >= first_week_start && wk <= current_week_start)); then
      week_product["$wk"]=$((week_product["$wk"] + 1))
    fi
  else
    if ((wk >= first_week_start && wk <= current_week_start)); then
      week_process["$wk"]=$((week_process["$wk"] + 1))
    fi
  fi
}

while IFS= read -r line; do
  if [[ "$line" == $'\x01'* ]]; then
    flush_commit
    rest="${line#$'\x01'}"
    commit_epoch="${rest%%$'\x1f'*}"
    rest="${rest#*$'\x1f'}"
    commit_sha="${rest%%$'\x1f'*}"
    commit_subject="${rest#*$'\x1f'}"
    is_product=0
    have_commit=1
  elif [[ -n "$line" && $have_commit == 1 ]]; then
    case "$line" in
      apps/* | workers/* | packages/*) is_product=1 ;;
    esac
  fi
done <<<"$log_out"
flush_commit

weeks_json="[]"
w=$first_week_start
while ((w <= current_week_start)); do
  ws="$(date -u -d "@$w" +%Y-%m-%dT%H:%M:%SZ)"
  weeks_json="$(jq -c --arg ws "$ws" --argjson p "${week_product[$w]}" --argjson pr "${week_process[$w]}" \
    '. + [{week_start: $ws, product: $p, process: $pr}]' <<<"$weeks_json")"
  w=$((w + 7 * 86400))
done

# weeks_without_product — поспіль від поточного тижня назад, серед зібраних тижнів.
weeks_without_product=0
w=$current_week_start
while ((w >= first_week_start)); do
  ((week_product[$w] > 0)) && break
  weeks_without_product=$((weeks_without_product + 1))
  w=$((w - 7 * 86400))
done

if ((last_product_epoch >= 0)); then
  last_product_date="$(date -u -d "@$last_product_epoch" +%Y-%m-%dT%H:%M:%SZ)"
  last_product_json="$(jq -nc --arg sha "$last_product_sha" --arg subject "$last_product_subject" --arg date "$last_product_date" \
    '{sha: $sha, subject: $subject, date: $date}')"
else
  last_product_json="null"
fi

data="$(jq -nc --argjson weeks "$weeks_json" --argjson wwp "$weeks_without_product" --argjson lpc "$last_product_json" \
  '{weeks: $weeks, weeks_without_product: $wwp, last_product_commit: $lpc}')"

args=(envelope trend "Продукт і процес" "git log $REF" 3600 measured ok "$data")
[[ -n "$NOW_ARG" ]] && args+=(--now "$NOW_ARG")
bash "$SCHEMA_SH" "${args[@]}"
