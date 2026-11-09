#!/usr/bin/env bash
# daily-digest.sh — зведення доби з фактів (CLAUDE.md §0 п.5, спринт 02.11 «Цикл доби»,
# задача A8 051). Оркестратор збирав цей знімок руками з чотирьох джерел (PR flatcraft,
# черга A8, квоти agy, hart-inbox) — ручна дія, зроблена двічі, стає скриптом.
#
# ФАКТИ VS СУДЖЕННЯ. «Стан», «Готово до merge», «Квоти» й «Ризики / STOP» — завжди
# з тулів (gh, agy, a8-ctl), ніколи з пам'яті (CLAUDE.md §0 п.3). «Критичний шлях»,
# «Чекає на вас», «Що йде» й «Архітектору» — судження, яких жоден тул не дає; вони
# підставляються з `--notes` (той самий формат `## Розділ`, що й сам файл зведення).
# Розділу немає в нотатках чи нотаток немає взагалі — «ЗАПОВНИТИ»: цей рядок одразу
# видно оком і він же блокує публікацію (п. 6 нижче).
#
# ЗБІЙ ДЖЕРЕЛА — НЕ ПАДІННЯ. gh/agy/a8-ctl можуть бути недоступні (мережі немає,
# токен застарів); тоді відповідний факт замінюється рядком
# «… НЕ ПЕРЕВІРЕНО — <причина з виводу команди>», а скрипт завершується з rc=0.
# Збій одного джерела не ховає факти інших джерел.
#
# ЧОРНОВИК VS ЗАВЕРШЕНЕ ЗВЕДЕННЯ. Файл дня, у якому лишилось «ЗАПОВНИТИ» хоч в
# одному розділі, — чорновик: повторний запуск його перезаписує (щоб --notes можна
# було дописати пізніше тим самим днем). Файл без «ЗАПОВНИТИ» — завершений: повторний
# запуск відмовляє (rc=2), щоб уже надіслане зведення не підмінилось тихо іншим
# змістом.
#
# ПУБЛІКАЦІЯ — ЛИШЕ ЧЕРЕЗ SAFE_PUBLISH. Прямого gh issue comment тут немає: перевірка
# витоку (check-leak.sh) — усередині safe-publish, іншого шляху публікації немає.
# Зведення з «ЗАПОВНИТИ» публікувати відмовляємось (rc=3) — yurii не має читати
# недороблений чорновик як готовий дайджест.
#
# Використання:
#   daily-digest.sh [--notes <файл>] [--publish <номер issue hart-inbox>]
# Змінні середовища (усі джерела підмінні — для тестів і мутантів):
#   GH (gh), AGY (agy), A8_STATUS_CMD ("ssh a8-ctl status"), SAFE_PUBLISH
#   (safe-publish.sh поруч), DIGEST_OUT ($HOME/a8-outbox), HEARTBEAT_FILE
#   ($DIGEST_OUT/heartbeat), DIGEST_NOW (зараз, UTC ISO — від нього дата файла,
#   вік записів і тижневі зони квот).
# Вихід: 0 — зведення написано (можливо, з «НЕ ПЕРЕВІРЕНО» у частині розділів);
# 2 — помилка аргументів АБО файл дня вже завершений (без «ЗАПОВНИТИ») — не
# перезаписано; 3 — публікація відмовлена: у зведенні лишилось «ЗАПОВНИТИ».
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
GH="${GH:-gh}"
AGY="${AGY:-agy}"
A8_STATUS_CMD="${A8_STATUS_CMD:-ssh a8-ctl status}"
SAFE_PUBLISH="${SAFE_PUBLISH:-$HERE/safe-publish.sh}"
DIGEST_OUT="${DIGEST_OUT:-$HOME/a8-outbox}"
HEARTBEAT_FILE="${HEARTBEAT_FILE:-$DIGEST_OUT/heartbeat}"
DIGEST_NOW="${DIGEST_NOW:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

FLATCRAFT="stjurik/flatcraft"
HART_INBOX="stjurik/hart-inbox"
PLACEHOLDER="ЗАПОВНИТИ"
MARK='<!-- inbox-bot -->'

die() {
  echo "daily-digest: $1" >&2
  exit "${2:-2}"
}

NOTES_FILE=""
PUBLISH_N=""
while (($# > 0)); do
  case "$1" in
    --notes)
      [[ $# -ge 2 ]] || die "--notes потребує шлях до файла"
      NOTES_FILE="$2"
      shift 2
      ;;
    --publish)
      [[ $# -ge 2 ]] || die "--publish потребує номер issue"
      PUBLISH_N="$2"
      shift 2
      ;;
    *) die "невідомий аргумент «$1» (--notes <файл> | --publish <N>)" ;;
  esac
done
[[ -z "$NOTES_FILE" || -f "$NOTES_FILE" ]] || die "немає файла нотаток «$NOTES_FILE»"
[[ -z "$PUBLISH_N" || "$PUBLISH_N" =~ ^[1-9][0-9]*$ ]] || die "--publish «$PUBLISH_N» — не номер issue"

now_epoch="$(date -u -d "$DIGEST_NOW" +%s 2>/dev/null)" || die "DIGEST_NOW «$DIGEST_NOW» — не дата"
digest_date="$(date -u -d "$DIGEST_NOW" +%F)"

mkdir -p "$DIGEST_OUT" || die "не створено $DIGEST_OUT"
FILE="$DIGEST_OUT/digest-$digest_date.md"

# Чорновик (лишилось ЗАПОВНИТИ) можна перезаписати; завершений — ні. -x: заповнювач —
# окремий рядок (нижче), тож слово в назві PR чи issue чорновика не робить (рецензія #308).
if [[ -f "$FILE" ]] && ! grep -qx "$PLACEHOLDER" "$FILE"; then
  die "$FILE вже завершено (без «$PLACEHOLDER») — не перезаписую" 2
fi

# ─── Стан черги / Ризики / STOP — a8-ctl status ──────────────────────────────
a8_out="$(bash -c "$A8_STATUS_CMD" 2>&1)"
a8_rc=$?
if ((a8_rc == 0)); then
  queue_line="$(grep '^черга:' <<<"$a8_out" || true)"
  stop_line="$(grep '^STOP:' <<<"$a8_out" || true)"
  guard_line="$(grep '^запобіжники:' <<<"$a8_out" || true)"
  flow_line="$(grep '^плановий потік:' <<<"$a8_out" || true)"
else
  a8_note="черга: НЕ ПЕРЕВІРЕНО — a8-ctl status упав (код $a8_rc): $a8_out"
  queue_line="$a8_note"
  stop_line="STOP: НЕ ПЕРЕВІРЕНО — a8-ctl status упав (код $a8_rc): $a8_out"
  guard_line=""
  flow_line=""
fi

# ─── PR flatcraft — gh pr list ────────────────────────────────────────────────
pr_out="$("$GH" pr list -R "$FLATCRAFT" --state open --limit 500 \
  --json number,title,isDraft,mergeable,mergeStateStatus,statusCheckRollup 2>&1)"
pr_rc=$?

ready_lines=()
notready_note=""
if ((pr_rc != 0)); then
  pr_fail="НЕ ПЕРЕВІРЕНО — gh pr list упав (код $pr_rc): $pr_out"
  ready_lines=("$pr_fail")
  notready_note="PR не готові до merge: $pr_fail"
else
  pr_tsv="$(jq -r '.[] | [
      (.number|tostring), (.isDraft|tostring), .mergeable, .mergeStateStatus,
      # length > 0: порожній список перевірок (CI ще не стартував) — не «зелений»;
      # без цього all([]) дає true (рецензія #308).
      (([.statusCheckRollup[]?.conclusion]
        | length > 0 and all(. as $c | ["SUCCESS","SKIPPED","NEUTRAL"] | index($c) != null))
       | tostring),
      .title
    ] | @tsv' <<<"$pr_out")" || die "gh pr list — не JSON"
  notready=()
  while IFS=$'\t' read -r num isdraft mergeable mss checks_ok title; do
    [[ -z "$num" ]] && continue
    ready=0
    if [[ "$mergeable" == MERGEABLE && "$checks_ok" == true ]]; then
      if [[ "$mss" == CLEAN ]] || { [[ "$isdraft" == true ]] && [[ "$mss" == DRAFT ]]; }; then
        ready=1
      fi
    fi
    if ((ready)); then
      line="- #$num $title"
      [[ "$isdraft" == true ]] && line="$line — draft"
      ready_lines+=("$line")
    else
      reason="mergeStateStatus=$mss"
      [[ "$mergeable" != MERGEABLE ]] && reason="конфлікт"
      [[ "$checks_ok" != true ]] && reason="CI не зелений"
      notready+=("#$num ($reason)")
    fi
  done <<<"$pr_tsv"
  if ((${#notready[@]} > 0)); then
    joined="$(printf '%s, ' "${notready[@]}")"
    notready_note="PR не готові до merge: ${joined%, }"
  else
    notready_note="PR не готові до merge: немає"
  fi
fi
((${#ready_lines[@]} == 0)) && ready_lines=("(немає)")

# ─── hart-inbox — gh issue list ───────────────────────────────────────────────
issue_out="$("$GH" issue list -R "$HART_INBOX" --state open --limit 500 \
  --json number,title,createdAt,labels 2>&1)"
issue_rc=$?

if ((issue_rc != 0)); then
  issue_fail="НЕ ПЕРЕВІРЕНО — gh issue list упав (код $issue_rc): $issue_out"
  new_line="найстаріший нерозібраний запис hart-inbox: $issue_fail"
  waiting_line="чекає відповіді yurii: $issue_fail"
else
  new_pick="$(jq -r '
    [.[] | select((.labels | map(.name)) as $l |
      ($l | index("нове")) and (($l | index("оброблено")) | not))]
    | sort_by(.createdAt) | .[0]
    | if . == null then "" else "\(.number)\t\(.createdAt)" end
  ' <<<"$issue_out")" || die "gh issue list — не JSON"
  waiting_pick="$(jq -r '
    [.[] | select((.labels | map(.name)) as $l | $l | index("потрібна відповідь"))]
    | sort_by(.createdAt) | .[0]
    | if . == null then "" else "\(.number)\t\(.createdAt)" end
  ' <<<"$issue_out")" || die "gh issue list — не JSON"

  if [[ -n "$new_pick" ]]; then
    IFS=$'\t' read -r n created <<<"$new_pick"
    created_epoch="$(date -u -d "$created" +%s)"
    days=$(((now_epoch - created_epoch) / 86400))
    new_line="найстаріший нерозібраний запис hart-inbox: #$n — $days доб"
  else
    new_line="найстаріший нерозібраний запис hart-inbox: немає"
  fi
  if [[ -n "$waiting_pick" ]]; then
    IFS=$'\t' read -r n created <<<"$waiting_pick"
    created_epoch="$(date -u -d "$created" +%s)"
    days=$(((now_epoch - created_epoch) / 86400))
    waiting_line="чекає відповіді yurii: #$n — $days доб"
  else
    waiting_line="чекає відповіді yurii: немає"
  fi
fi

# ─── серцебиття ────────────────────────────────────────────────────────────
if [[ -f "$HEARTBEAT_FILE" ]]; then
  hb_raw="$(tr -d '[:space:]' <"$HEARTBEAT_FILE")"
  if [[ "$hb_raw" =~ ^[0-9]+$ ]]; then
    hb_hours=$(((now_epoch - hb_raw) / 3600))
    heartbeat_line="серцебиття: $hb_hours год тому"
  else
    heartbeat_line="серцебиття: НЕ ПЕРЕВІРЕНО — файл «$HEARTBEAT_FILE» не схожий на unix-час"
  fi
else
  heartbeat_line="серцебиття: немає (файл «$HEARTBEAT_FILE» не знайдено)"
fi

# ─── Квоти — agy -p /usage ────────────────────────────────────────────────────
agy_out="$("$AGY" -p /usage 2>&1)"
agy_rc=$?
if ((agy_rc != 0)); then
  quota_lines=("НЕ ПЕРЕВІРЕНО — agy -p /usage упав (код $agy_rc): $agy_out")
else
  declare -A wk_pct wk_reset five_pct
  order=()
  while IFS=$'\t' read -r pool label pct reset; do
    [[ -z "$pool" ]] && continue
    if [[ -z "${wk_pct[$pool]+x}${five_pct[$pool]+x}" ]]; then
      order+=("$pool")
    fi
    if [[ "$label" == *Weekly* ]]; then
      wk_pct[$pool]="${pct%\%}"
      wk_reset[$pool]="$reset"
    elif [[ "$label" == *"Five Hour"* ]]; then
      five_pct[$pool]="${pct%\%}"
    fi
  done <<<"$agy_out"

  quota_lines=()
  for pool in "${order[@]}"; do
    w="${wk_pct[$pool]:-}"
    reset="${wk_reset[$pool]:-}"
    [[ -z "$w" || -z "$reset" ]] && continue
    reset_epoch="$(date -u -d "$reset" +%s)" || continue
    hours=$(((reset_epoch - now_epoch) / 3600))
    share="$(awk -v h="$hours" 'BEGIN{printf "%.0f", h/168*100}')"
    five="${five_pct[$pool]:-}"
    if [[ -n "$five" ]] && awk -v a="$five" 'BEGIN{exit !(a<20)}'; then
      zone="П'ять годин"
    elif awk -v a="$w" 'BEGIN{exit !(a<15)}'; then
      zone="Резерв"
    elif awk -v a="$w" -v b="$share" 'BEGIN{exit !(a<b)}'; then
      zone="Економія"
    else
      zone="Вільно"
    fi
    quota_lines+=("- $pool: ${w}%, до оновлення $hours год (частка тижня ${share}%) — $zone")
  done
  ((${#quota_lines[@]} == 0)) && quota_lines=("(немає)")
fi

# ─── судження — з --notes, інакше ЗАПОВНИТИ ───────────────────────────────────
notes_get() {
  local heading="$1" out=""
  if [[ -n "$NOTES_FILE" ]]; then
    out="$(awk -v h="## $heading" '$0 == h { f = 1; next } /^## / { f = 0 } f' "$NOTES_FILE")"
  fi
  if [[ -z "$out" ]]; then
    echo "$PLACEHOLDER"
  else
    printf '%s\n' "$out"
  fi
}

critical="$(notes_get "Критичний шлях")"
waiting_you="$(notes_get "Чекає на вас")"
in_progress="$(notes_get "Що йде")"
architect="$(notes_get "Архітектору")"

# ─── збірка файла ──────────────────────────────────────────────────────────
TMP="$(mktemp "$DIGEST_OUT/.digest.XXXXXX")" || die "не створено тимчасовий файл"
trap 'rm -f "$TMP"' EXIT

{
  echo "## Стан"
  echo "$queue_line"
  echo "$heartbeat_line"
  echo "$new_line"
  echo "$waiting_line"
  echo "$notready_note"
  echo
  echo "## Критичний шлях"
  printf '%s\n' "$critical"
  echo
  echo "## Готово до merge"
  printf '%s\n' "${ready_lines[@]}"
  echo
  echo "## Чекає на вас"
  printf '%s\n' "$waiting_you"
  echo
  echo "## Що йде"
  printf '%s\n' "$in_progress"
  echo
  echo "## Квоти"
  printf '%s\n' "${quota_lines[@]}"
  echo
  echo "## Ризики / STOP"
  echo "$stop_line"
  [[ -n "$guard_line" ]] && echo "$guard_line"
  [[ -n "$flow_line" ]] && echo "$flow_line"
  echo
  echo "## Архітектору"
  printf '%s\n' "$architect"
  echo
  echo "$MARK"
} >"$TMP"

mv "$TMP" "$FILE"
trap - EXIT
echo "$FILE"

if [[ -n "$PUBLISH_N" ]]; then
  if grep -qx "$PLACEHOLDER" "$FILE"; then
    die "у зведенні лишилось «$PLACEHOLDER» — публікація відмовлена" 3
  fi
  "$SAFE_PUBLISH" gh "$FILE" issue comment "$PUBLISH_N" --repo "$HART_INBOX"
  exit $?
fi
