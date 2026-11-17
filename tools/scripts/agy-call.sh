#!/usr/bin/env bash
# agy-call.sh — один виклик agy від початку до кінця, без ручних кроків
# (CLAUDE.md §0 п.5, спринт 02.11 «Цикл доби», задача 050 S4а).
#
# ЧОМУ СКРИПТ. Зараз кожен виклик agy оркестратор складає руками: /usage,
# baseline git status, agy з логом, перевірка меж, мітка моделі з лога,
# /usage, рядок журналу. Сім кроків, повторених десятки разів, — саме той
# «ручна дія, зроблена двічі» з §0 п.5. Цей скрипт — перша ланка циклу доби:
# на нього спиратимуться daily-digest.sh і оркестратор на A8.
#
# МЕЖІ СТРОГІШІ, НІЖ check-agy-scope.sh. check-agy-scope.sh дозволяє будь-що
# всередині docs/promts/inputs/ — це дозволена ЗОНА запису. Тут зона не має
# значення: agy відповідає лише у stdout, тож БУДЬ-ЯКА зміна дерева worktree,
# зокрема файл, який agy сам поклав у docs/promts/inputs/, — порушення меж
# для ЦЬОГО виклику. check-agy-scope.sh і agy-call.sh рахують різне: перший —
# «чи це доручена зона», другий — «чи дерево взагалі не торкнулось».
#
# ЧОМУ СНІМОК — СТАТУС + SHA256, А НЕ ЛИШЕ `git status`. Дописування в уже
# брудний (незакомічений) файл не міняє рядок `git status --porcelain` — він
# лишається тим самим ` M x`/`?? x`. Без хеша контенту це б пройшло як
# «межі чисті», хоча agy дописав байти в чужий незакомічений файл.
#
# ЧОМУ МІТКА МОДЕЛІ — З ЛОГА, А НЕ З АРГУМЕНТУ --model. Рядки на кшталт
# `model resolved via default: label="…"` з'являються рано і називають
# дефолтну модель акаунта, а не ту, що фактично обслуговує виклик; джерело
# правди — пізніший рядок `Propagating selected model override to backend:
# label="…"` (docs/promts/orchestrator-autonomy.md §3.3). Якщо такого рядка
# в лозі немає — довіряти аргументу небезпечно (agy міг узяти дефолт), тож
# колонка журналу пише «невідомо → <модель з аргументу>» (agy-stats-summary.sh
# саме так рахує сумнів проти моделі).
#
# Інтерфейс: tools/scripts/agy-call.sh <worktree> <файл-контексту> <модель> <мітка>
# Змінні: AGY (дефолт agy), AGY_CALL_LOGS (дефолт $HOME/hart-wt/tmp-agy-logs),
#   AGY_CALL_ROOTS (теки, які читає agy, через «:»; дефолт $HOME/hart:$HOME/hart-wt),
#   AGY_CALL_TIMEOUT (секунди на виклик роботи, дефолт 900),
#   AGY_CALL_KEEP_CONTEXT (1 — не прибирати файл контексту).
#
# Коди виходу, пріоритет у цьому порядку:
#   3 — межі порушено (дерево worktree змінилось під час виклику);
#   4 — збій agy (timeout, rc≠0, порожній вивід, RESOURCE_EXHAUSTED);
#   5 — мітка моделі в лозі не та, що для цієї моделі, або її немає;
#   0 — ok;
#   2 — відмова ДО виклику agy (поганий вхід) — agy не викликається взагалі.
set -uo pipefail

refuse() {
  echo "відмова: $*" >&2
  exit 2
}

(($# == 4)) || refuse "очікую рівно 4 аргументи: <worktree> <файл-контексту> <модель> <мітка>, отримав $#"

WORKTREE="$1"
CTX="$2"
MODEL="$3"
LABEL="$4"

declare -A MODEL_LABEL=(
  [gemini-3.8-flash-high]="Gemini 3.8 Flash (High)"
  [gemini-4-argon-medium]="Gemini 4 Argon (Medium)"
  [claude-sonnet-5-5-high]="Claude Sonnet 5.5 (High)"
)
declare -A MODEL_POOL=(
  [gemini-3.8-flash-high]="Gemini Models"
  [gemini-4-argon-medium]="Gemini 4 Argon"
  [claude-sonnet-5-5-high]="Claude and GPT models"
)

[[ -n "${MODEL_LABEL[$MODEL]+x}" ]] || refuse "модель «$MODEL» не в таблиці"
[[ "$LABEL" =~ ^[a-z0-9][a-z0-9.-]*$ ]] || refuse "мітка «$LABEL» не за форматом ^[a-z0-9][a-z0-9.-]*\$"

[[ "$CTX" == /* ]] || refuse "шлях контексту «$CTX» не абсолютний"
[[ -e "$CTX" ]] || refuse "файла контексту «$CTX» немає"
[[ -L "$CTX" ]] && refuse "файл контексту «$CTX» — симлінк"
[[ -f "$CTX" ]] || refuse "«$CTX» не є звичайним файлом"

WT_REAL="$(realpath -- "$WORKTREE" 2>/dev/null)" || refuse "worktree «$WORKTREE» не існує"
CTX_REAL="$(realpath -- "$CTX" 2>/dev/null)" || refuse "файл контексту «$CTX» не читається"
CTX_BASENAME="$(basename -- "$CTX_REAL")"
[[ "$CTX_BASENAME" == _agy-*.md ]] || refuse "файл контексту має бути _agy-*.md, отримав «$CTX_BASENAME»"
INPUTS_REAL="$WT_REAL/docs/promts/inputs"
[[ "$(dirname -- "$CTX_REAL")" == "$INPUTS_REAL" ]] ||
  refuse "файл контексту має лежати безпосередньо в <worktree>/docs/promts/inputs/, не в підтеці"

ROOTS="${AGY_CALL_ROOTS:-$HOME/hart:$HOME/hart-wt}"
root_ok=0
IFS=':' read -ra ROOT_ARR <<<"$ROOTS"
for r in "${ROOT_ARR[@]}"; do
  [[ -z "$r" ]] && continue
  r_real="$(realpath -- "$r" 2>/dev/null)" || continue
  if [[ "$WT_REAL" == "$r_real" || "$WT_REAL" == "$r_real"/* ]]; then
    root_ok=1
    break
  fi
done
((root_ok == 1)) || refuse "worktree «$WORKTREE» поза AGY_CALL_ROOTS ($ROOTS)"

LOGS="${AGY_CALL_LOGS:-$HOME/hart-wt/tmp-agy-logs}"
OUT_FILE="$LOGS/$LABEL.out"
LOG_FILE="$LOGS/$LABEL.log"
UB_FILE="$LOGS/$LABEL.usage-before"
UA_FILE="$LOGS/$LABEL.usage-after"
ROW_FILE="$LOGS/$LABEL.row.md"

for f in "$OUT_FILE" "$LOG_FILE" "$UB_FILE" "$UA_FILE" "$ROW_FILE"; do
  # -L: битий симлінк з цим іменем запис пішов би через нього (#307).
  [[ -e "$f" || -L "$f" ]] && refuse "у AGY_CALL_LOGS уже є «$f» — не перезаписую"
done

mkdir -p "$LOGS" || refuse "не вдалось створити AGY_CALL_LOGS «$LOGS»"

AGY_BIN="${AGY:-agy}"
TIMEOUT_S="${AGY_CALL_TIMEOUT:-900}"
LABEL_FOR_MODEL="${MODEL_LABEL[$MODEL]}"
POOL="${MODEL_POOL[$MODEL]}"

sha_of() {
  [[ -f "$1" && ! -L "$1" ]] || { echo MISSING; return; }
  sha256sum -- "$1" 2>/dev/null | awk '{print $1}'
}

# Повертає шлях із рядка `git status --porcelain --untracked-files=all`.
# R/C-рядки несуть ціль після « -> »; шляхи з пробілами git бере в лапки.
porcelain_path() {
  local line="$1" xy rest
  xy="${line:0:2}"
  rest="${line:3}"
  if [[ ("$xy" == R* || "$xy" == C*) && "$rest" == *" -> "* ]]; then
    rest="${rest##* -> }"
  fi
  if [[ "$rest" == \"*\" && "$rest" == *\" ]]; then
    rest="${rest:1:-1}"
  fi
  printf '%s' "$rest"
}

# snapshot <назва asssoc-масиву для хешів> <назва змінної для тексту статусу>
# Обидва — nameref: функція МАЄ виконуватись у поточній оболонці, не в
# підоболонці command substitution, інакше запис у масив загубиться разом з
# підоболонкою (так і стався перший червоний прогін цього скрипта).
snapshot() {
  local -n out_hashes="$1"
  local -n out_status="$2"
  # core.quotePath=false: інакше не-ASCII шлях іде у вісімкових лапках, sha_of
  # бачить MISSING до й після — дописування в уже брудний файл непомітне (#307).
  out_status="$(git -c core.quotePath=false -C "$WORKTREE" status --porcelain --untracked-files=all 2>/dev/null)"
  local line path
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    path="$(porcelain_path "$line")"
    out_hashes["$path"]="$(sha_of "$WORKTREE/$path")"
  done <<<"$out_status"
}

extract_quota() { # extract_quota <usage-файл> <пул> — тижневий % цього пулу
  awk -F'\t' -v pool="$2" '
    $1 == pool && $2 ~ /Weekly/ {
      v = $3
      gsub(/%/, "", v)
      print v
      exit
    }
  ' "$1" 2>/dev/null
}

# Крок 2: /usage ДО виклику. timeout: завислий /usage інакше тримав би скрипт без кінця (#307).
timeout 120 "$AGY_BIN" -p "/usage" >"$UB_FILE" 2>&1
QUOTA_BEFORE="$(extract_quota "$UB_FILE" "$POOL")"

# Крок 3: знімок дерева ДО виклику.
declare -A BEFORE_HASH=()
BEFORE_STATUS=""
snapshot BEFORE_HASH BEFORE_STATUS

# Крок 4: сам виклик. Промпт лише НАЗИВАЄ файл контексту (абсолютний шлях) —
# вміст файлу в командний рядок не потрапляє ніколи.
PROMPT="Контекст цієї задачі лежить у файлі $CTX_REAL. Прочитай його через read_file. Жодних команд не виконуй і нічого на диску не шукай — лише відповідь текстом."
TIMED_OUT=0
timeout "$TIMEOUT_S" "$AGY_BIN" -p "$PROMPT" --model "$MODEL" --log-file "$LOG_FILE" >"$OUT_FILE" 2>&1
RC=$?
[[ "$RC" -eq 124 ]] && TIMED_OUT=1

# Крок 5: знімок дерева ПІСЛЯ виклику — порівняння з ДО.
declare -A AFTER_HASH=()
AFTER_STATUS=""
snapshot AFTER_HASH AFTER_STATUS

BOUNDARY_BROKEN=0
if [[ "$BEFORE_STATUS" != "$AFTER_STATUS" ]]; then
  BOUNDARY_BROKEN=1
else
  for p in "${!BEFORE_HASH[@]}"; do
    if [[ "${BEFORE_HASH[$p]}" != "${AFTER_HASH[$p]:-}" ]]; then
      BOUNDARY_BROKEN=1
      break
    fi
  done
fi

# Крок 6: /usage ПІСЛЯ виклику.
timeout 120 "$AGY_BIN" -p "/usage" >"$UA_FILE" 2>&1
QUOTA_AFTER="$(extract_quota "$UA_FILE" "$POOL")"

# Крок 7: файл контексту — транзитний, прибираємо (якщо не попросили лишити).
if [[ "${AGY_CALL_KEEP_CONTEXT:-}" != 1 ]]; then
  rm -f -- "$CTX"
fi

SOFT_DENY_N="$(grep -c -F 'soft-deny' "$LOG_FILE" 2>/dev/null || true)"
SOFT_DENY_N="${SOFT_DENY_N:-0}"

# Мітка моделі — лише з рядка «Propagating selected model override to
# backend: label="…"»; ранні рядки «resolved via default» ігноруються.
DETECTED_LABEL=""
while IFS= read -r line; do
  if [[ "$line" == *"Propagating selected model override to backend:"* ]]; then
    if [[ "$line" =~ label=\"([^\"]*)\" ]]; then
      DETECTED_LABEL="${BASH_REMATCH[1]}"
    fi
  fi
done <"$LOG_FILE"

if [[ -n "$DETECTED_LABEL" ]]; then
  MODEL_COL="$DETECTED_LABEL"
  LABEL_MISMATCH=0
  [[ "$DETECTED_LABEL" == "$LABEL_FOR_MODEL" ]] || LABEL_MISMATCH=1
else
  MODEL_COL="невідомо → $MODEL"
  LABEL_MISMATCH=1
fi

OUT_CONTENT="$(cat "$OUT_FILE" 2>/dev/null)"
FAILED=0
FAIL_REASON=""
if [[ "$TIMED_OUT" -eq 1 ]]; then
  FAILED=1
  FAIL_REASON="timeout"
elif [[ "$OUT_CONTENT" == *"RESOURCE_EXHAUSTED"* ]]; then
  FAILED=1
  resets=""
  [[ "$OUT_CONTENT" =~ (Resets\ in\ [0-9A-Za-z]+) ]] && resets="${BASH_REMATCH[1]}"
  FAIL_REASON="RESOURCE_EXHAUSTED (code 429)${resets:+, $resets}"
elif [[ "$RC" -ne 0 || ! -s "$OUT_FILE" ]]; then
  FAILED=1
  FAIL_REASON="agy rc=$RC, вивід $(wc -c <"$OUT_FILE" 2>/dev/null | tr -d ' ') байт"
fi

# Пріоритет: межі (3) > збій (4) > мітка (5) > ok (0).
if [[ "$BOUNDARY_BROKEN" -eq 1 ]]; then
  EXIT_CODE=3
  BOUNDARY_TXT="ПОРУШЕНО"
elif [[ "$FAILED" -eq 1 ]]; then
  EXIT_CODE=4
  BOUNDARY_TXT="чисті"
elif [[ "$LABEL_MISMATCH" -eq 1 ]]; then
  EXIT_CODE=5
  BOUNDARY_TXT="чисті"
else
  EXIT_CODE=0
  BOUNDARY_TXT="чисті"
fi

# Крок 8: чернетка рядка журналу — 8 колонок, роздільник « | ».
DATE_UTC="$(date -u +%F)"
if [[ "$BOUNDARY_BROKEN" -eq 1 ]]; then
  RESULT="межі ПОРУШЕНО — soft-denying $SOFT_DENY_N; квота $POOL ${QUOTA_BEFORE}% → ${QUOTA_AFTER}%"
  FAB="ЗАПОВНИТИ"
elif [[ "$FAILED" -eq 1 ]]; then
  RESULT="збій — $FAIL_REASON"
  FAB='**0** — тверджень немає. **У вікно OQ-35 не зараховано**'
else
  RESULT="ok — межі чисті, soft-denying $SOFT_DENY_N; квота $POOL ${QUOTA_BEFORE}% → ${QUOTA_AFTER}%"
  FAB="ЗАПОВНИТИ"
fi

printf '| %s | ЗАПОВНИТИ | %s | %s | ЗАПОВНИТИ | ЗАПОВНИТИ | %s | ЗАПОВНИТИ |\n' \
  "$DATE_UTC" "$MODEL_COL" "$RESULT" "$FAB" >"$ROW_FILE"

# Крок 9: stdout — рівно 4 рядки.
echo "модель: $MODEL_COL"
echo "межі: $BOUNDARY_TXT"
echo "квота $POOL ${QUOTA_BEFORE}% → ${QUOTA_AFTER}%"
echo "рядок: $ROW_FILE"

exit "$EXIT_CODE"
