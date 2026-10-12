#!/usr/bin/env bash
# dash-collect.sh — пульт розробки (ADR-042 §10, задача 7): запускає збирачі хвилі 1,
# вирізає секрети й пише знімок поза репо для сторінки tools/dashboard/index.html.
#
# ЧОМУ ЦЕ ОКРЕМО. Конвеєр (тайм-аут на збирач, вирізання, атомарний запис) спільний
# для кожного майбутнього збирача — дублювати його в кожному значить розійтись із ним
# в одному з них (CLAUDE.md §0 п.5). Новий збирач — один рядок у COLLECTORS нижче.
#
# ЧЕСНІСТЬ ДАНИХ (ADR-042 §3): збирач, що впав, завис чи надрукував невалідну
# обгортку (dash-schema.sh validate), не псує решту знімка — його розділ отримує
# обгортку status "error" з причиною, решта розділів лишаються свіжими.
#
# ПРИВАТНІСТЬ (ADR-042 §5). DIR — поза репо і поза ~/.flatcraft/ (там секрети
# оркестратора: ключ age, адреса staging, бекапи) — скрипт відмовляється писати
# в будь-яку теку всередині жодного з них. Увесь вивід (stdout і stderr) кожного
# збирача перевіряється на IPv4, IPv6 і шаблони секретів (ghp_, github_pat_,
# sk-ant-, AGE-SECRET-KEY, BEGIN … PRIVATE KEY) і на рядки файла DASH_LEAK_FILE
# (grep -cFf, той самий оракул витоку, що в Master Run 16) ПЕРЕД тим, як щось із
# цього виводу потрапить у знімок чи в повідомлення про помилку: знайдене значення
# не друкується ніде, навіть у stderr, — розділ просто стає error з назвою типу.
#
# Використання: dash-collect.sh [--out DIR] [--now T]
#   DASH_COLLECTORS_DIR    — каталог, де шукати файли збирачів (дефолт — поруч, як
#                             і цей скрипт); тести підміняють заглушками.
#   DASH_LEAK_FILE          — файл відомої адреси, жоден рядок якого не має
#                             потрапити в знімок (дефолт ~/.flatcraft/leak/origin-host).
#   DASH_COLLECT_TIMEOUT_S  — тайм-аут на один збирач, секунд (дефолт 10).
#
# Запис: DIR/snapshot.json, DIR/snapshot.js (window.SNAPSHOT = …;), копії
# tools/dashboard/index.html і render.js — кожен файл спершу в тимчасовий поруч,
# потім mv, щоб сторінка ніколи не прочитала напівзаписаний знімок.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA_SH="$HERE/dash-schema.sh"
DASHBOARD_DIR="$HERE/../dashboard"
REPO_DIR="$(cd "$HERE/../.." && pwd)"
COLLECTORS_DIR="${DASH_COLLECTORS_DIR:-$HERE}"
TIMEOUT_S="${DASH_COLLECT_TIMEOUT_S:-10}"
LEAK_FILE="${DASH_LEAK_FILE:-$HOME/.flatcraft/leak/origin-host}"
OUT="$HOME/hart-pult"
NOW_ARG=""

# section|script|title|source|interval_s — явний перелік хвилі 1 (ADR-042 §10).
# dash-schema.sh і dash-collect.sh самі збирачами не є — вони тут не перелічені.
# title/source/interval_s тут — також дефолт для обгортки error, коли збирач не
# встиг надрукувати власну (впав, завис, не знайдений).
COLLECTORS=(
  "t5|dash-t5.sh|Трек T5|tools/scripts/dash-t5.sh|3600"
  "trend|dash-trend.sh|Продукт і процес|tools/scripts/dash-trend.sh|3600"
)

# ─── шаблони витоку (ADR-042 §5) ────────────────────────────────────────────
# IPv4: лише дійсні октети 0–255 — без цього «3.8» (Gemini 3.8 Flash) чи номер
# PR уже був би IPv4-подібним збігом.
IPV4_OCTET='(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])'
IPV4_RE="\\b${IPV4_OCTET}(\\.${IPV4_OCTET}){3}\\b"
# IPv6: повна форма (7 двокрапок) або стиснута («::» десь у рядку) — обидві форми
# вимагають шістнадцяткових груп навколо двокрапок, тож час «14:05:12» (жодної
# «::», лише 2 двокрапки) і дата ISO з часом усередині під цей шаблон не підходять.
IPV6_RE='([0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}'
IPV6_RE="$IPV6_RE|([0-9A-Fa-f]{1,4}:){1,7}:"
IPV6_RE="$IPV6_RE|([0-9A-Fa-f]{1,4}:){1,6}:[0-9A-Fa-f]{1,4}"
IPV6_RE="$IPV6_RE|([0-9A-Fa-f]{1,4}:){1,5}(:[0-9A-Fa-f]{1,4}){1,2}"
IPV6_RE="$IPV6_RE|([0-9A-Fa-f]{1,4}:){1,4}(:[0-9A-Fa-f]{1,4}){1,3}"
IPV6_RE="$IPV6_RE|([0-9A-Fa-f]{1,4}:){1,3}(:[0-9A-Fa-f]{1,4}){1,4}"
IPV6_RE="$IPV6_RE|([0-9A-Fa-f]{1,4}:){1,2}(:[0-9A-Fa-f]{1,4}){1,5}"
IPV6_RE="$IPV6_RE|[0-9A-Fa-f]{1,4}:((:[0-9A-Fa-f]{1,4}){1,6})"
IPV6_RE="$IPV6_RE|:((:[0-9A-Fa-f]{1,4}){1,7}|:)"

LEAK_PATTERNS=(
  "IPv4|$IPV4_RE"
  "IPv6|$IPV6_RE"
  "токен GitHub (ghp_)|ghp_[A-Za-z0-9]+"
  "токен GitHub (github_pat_)|github_pat_[A-Za-z0-9_]+"
  "ключ Anthropic (sk-ant-)|sk-ant-[A-Za-z0-9_-]+"
  "приватний ключ age (AGE-SECRET-KEY)|AGE-SECRET-KEY"
  "приватний ключ (BEGIN … PRIVATE KEY)|BEGIN[A-Z ]*PRIVATE KEY"
)

while (($#)); do
  case "$1" in
    --out)
      [[ $# -ge 2 ]] || { echo "відмова: --out потребує значення" >&2; exit 2; }
      OUT="$2"
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

if [[ -n "$NOW_ARG" ]]; then
  date -u -d "$NOW_ARG" +%s >/dev/null 2>&1 || {
    echo "відмова: --now має бути UTC ISO 8601 (РРРР-ММ-ДДTГГ:ХХ:ССZ), отримано «$NOW_ARG»" >&2
    exit 2
  }
  NOW="$NOW_ARG"
else
  NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
fi

[[ -r "$SCHEMA_SH" ]] || { echo "відмова: немає $SCHEMA_SH" >&2; exit 2; }
[[ -r "$DASHBOARD_DIR/index.html" ]] || { echo "відмова: немає $DASHBOARD_DIR/index.html" >&2; exit 2; }
[[ -r "$DASHBOARD_DIR/render.js" ]] || { echo "відмова: немає $DASHBOARD_DIR/render.js" >&2; exit 2; }
[[ -d "$COLLECTORS_DIR" ]] || { echo "відмова: немає каталогу збирачів «$COLLECTORS_DIR»" >&2; exit 2; }

# ─── приватність (ADR-042 §5): DIR не всередині ~/.flatcraft/ і не всередині репо ──
OUT_ABS="$(readlink -m -- "$OUT")"
FLATCRAFT_ABS="$(readlink -m -- "$HOME/.flatcraft")"
case "$OUT_ABS/" in
  "$FLATCRAFT_ABS/"*)
    echo "відмова: --out усередині ~/.flatcraft/ — там секрети оркестратора (ADR-042 §5)" >&2
    exit 2
    ;;
esac
case "$OUT_ABS/" in
  "$REPO_DIR/"*)
    echo "відмова: --out усередині репозиторію (ADR-042 §5)" >&2
    exit 2
    ;;
esac

# ─── leak_scan <text> → друкує тип витоку в stdout, exit 0; нічого не знайдено — exit 1.
# Саме <text> у виводі не з'являється ніколи — лише назва типу з LEAK_PATTERNS чи
# фіксований підпис для DASH_LEAK_FILE.
leak_scan() {
  local text="$1" entry label pattern
  for entry in "${LEAK_PATTERNS[@]}"; do
    label="${entry%%|*}"
    pattern="${entry#*|}"
    if grep -Eq -- "$pattern" <<<"$text"; then
      printf '%s\n' "$label"
      return 0
    fi
  done
  if [[ -r "$LEAK_FILE" && -s "$LEAK_FILE" ]]; then
    local hits
    hits="$(grep -cFf "$LEAK_FILE" <<<"$text" 2>/dev/null || true)"
    if [[ "${hits:-0}" =~ ^[0-9]+$ ]] && ((hits > 0)); then
      printf '%s\n' "відома адреса (DASH_LEAK_FILE)"
      return 0
    fi
  fi
  return 1
}

error_envelope() { # error_envelope <section> <title> <source> <interval_s> <reason>
  local section="$1" title="$2" source="$3" interval_s="$4" reason="$5" data
  data="$(jq -nc --arg reason "$reason" '{error: $reason}')"
  bash "$SCHEMA_SH" envelope "$section" "$title" "$source" "$interval_s" measured error "$data" --now "$NOW"
}

# collect_one <section> <script> <title> <source> <interval_s> → одна обгортка JSON.
collect_one() {
  local section="$1" script="$2" title="$3" source="$4" interval_s="$5"
  local path="$COLLECTORS_DIR/$script"
  local out_f err_f rc combined leak vout
  out_f="$(mktemp)"
  err_f="$(mktemp)"
  trap 'rm -f "$out_f" "$err_f"' RETURN

  if [[ ! -r "$path" ]]; then
    error_envelope "$section" "$title" "$source" "$interval_s" "немає збирача «$script» у «$COLLECTORS_DIR»"
    return
  fi

  if timeout -k 2 "$TIMEOUT_S" bash "$path" --now "$NOW" >"$out_f" 2>"$err_f"; then
    rc=0
  else
    rc=$?
  fi

  combined="$(cat -- "$out_f" "$err_f" 2>/dev/null)"
  if leak="$(leak_scan "$combined")"; then
    error_envelope "$section" "$title" "$source" "$interval_s" "вирізано: $leak"
    return
  fi

  if ((rc == 124 || rc == 137)); then
    error_envelope "$section" "$title" "$source" "$interval_s" "тайм-аут понад ${TIMEOUT_S}s"
    return
  fi
  if ((rc != 0)); then
    error_envelope "$section" "$title" "$source" "$interval_s" "збирач вийшов з кодом $rc"
    return
  fi

  vout="$(bash "$SCHEMA_SH" validate "$out_f" 2>&1)"
  if [[ "$vout" != ok ]]; then
    error_envelope "$section" "$title" "$source" "$interval_s" "невалідна обгортка: $vout"
    return
  fi

  cat -- "$out_f"
}

# atomic_write <dest> <зміст> / atomic_copy <src> <dest> — спершу тимчасовий файл
# у тій самій теці (той самий файл-system — mv атомарний), потім mv.
atomic_write() {
  local dest="$1" content="$2" tmp
  tmp="$(mktemp "$(dirname -- "$dest")/.dash-collect.XXXXXX")"
  printf '%s' "$content" >"$tmp"
  mv -f -- "$tmp" "$dest"
}
atomic_copy() {
  local src="$1" dest="$2" tmp
  tmp="$(mktemp "$(dirname -- "$dest")/.dash-collect.XXXXXX")"
  cp -f -- "$src" "$tmp"
  mv -f -- "$tmp" "$dest"
}

mkdir -p -- "$OUT" || { echo "відмова: не вдалося створити «$OUT»" >&2; exit 2; }

SECTIONS_JSON="[]"
for entry in "${COLLECTORS[@]}"; do
  IFS='|' read -r section script title source interval_s <<<"$entry"
  env_json="$(collect_one "$section" "$script" "$title" "$source" "$interval_s")"
  SECTIONS_JSON="$(jq -c --argjson s "$env_json" '. + [$s]' <<<"$SECTIONS_JSON")"
done

SNAPSHOT_JSON="$(jq -nc --arg now "$NOW" --argjson sections "$SECTIONS_JSON" \
  '{collected_at: $now, sections: $sections}')"

atomic_write "$OUT/snapshot.json" "$SNAPSHOT_JSON"
atomic_write "$OUT/snapshot.js" "window.SNAPSHOT = $SNAPSHOT_JSON;"
atomic_copy "$DASHBOARD_DIR/index.html" "$OUT/index.html"
atomic_copy "$DASHBOARD_DIR/render.js" "$OUT/render.js"

echo "зібрано: $OUT/snapshot.json"
