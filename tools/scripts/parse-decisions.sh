#!/usr/bin/env bash
# parse-decisions.sh — розбір відповіді yurii на зведення доби у файл рішень.
#
# ЧОМУ ЦЕЙ СКРИПТ ІСНУЄ. З 02.11 yurii відповідає на зведення доби одним
# коментарем виду «1★ 2б merge: 293 295 прийнято: 286 — вільний текст».
# Оркестратор має виконувати РІВНО те, що yurii вирішив, а не те, що
# «схоже на те, що він мав на увазі» (CLAUDE.md §0 п.3, п.4): здогад, поданий
# як факт, — найдорожча помилка в цьому проєкті. Тому граматика розбору
# навмисно вузька: усе, що не відповідає їй однозначно, стає питанням (код 4),
# а не найкращим припущенням.
#
# ЩО РОБИТЬ. Читає зведення (файл 2) і знаходить пункти та їхні варіанти лише
# в розділі «## Чекає на вас» (до наступного «## »). Читає відповідь (файл 1),
# розбиває на токени пробілами (переводи рядків — теж пробіли) і розбирає її
# за фіксованою граматикою (докладно — у промпті задачі A8 052). Результат —
# один JSON-об'єкт у stdout.
#
# Вихід:
#   0 — розібрано без питань;
#   4 — є хоча б одне питання (decisions/merge/accepted тоді порожні: часткове
#       застосування означало б угадати решту);
#   2 — аргументів не 2, або якийсь із файлів не існує.
#
# Використання: tools/scripts/parse-decisions.sh <файл-відповіді> <файл-зведення>
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "використання: parse-decisions.sh <файл-відповіді> <файл-зведення>" >&2
  exit 2
fi
REPLY_FILE="$1"
DIGEST_FILE="$2"
[[ -f "$REPLY_FILE" ]] || { echo "немає файла відповіді: $REPLY_FILE" >&2; exit 2; }
[[ -f "$DIGEST_FILE" ]] || { echo "немає файла зведення: $DIGEST_FILE" >&2; exit 2; }

# --- Нормалізація однієї кириличної літери з великої на малу (лише набір а б в г ґ д е). ---
normalize_letter() {
  case "$1" in
  А) echo "а" ;;
  Б) echo "б" ;;
  В) echo "в" ;;
  Г) echo "г" ;;
  Ґ) echo "ґ" ;;
  Д) echo "д" ;;
  Е) echo "е" ;;
  *) echo "$1" ;;
  esac
}
is_letter() {
  case "$1" in
  а | б | в | г | ґ | д | е) return 0 ;;
  *) return 1 ;;
  esac
}
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# --- 1. Розбір зведення: пункти й варіанти лише в "## Чекає на вас". ---
declare -A item_exists
declare -A item_letters   # " а б в" — список нормалізованих літер варіантів пункту, у порядку
declare -A item_opt_count # скільки варіантів у пункта
declare -A item_star_count
declare -A item_star_letter

in_section=0
cur_item=""
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" =~ ^##[[:space:]]+(.*)$ ]]; then
    heading="$(trim "${BASH_REMATCH[1]}")"
    if [[ "$heading" == "Чекає на вас" ]]; then
      in_section=1
    else
      in_section=0
    fi
    cur_item=""
    continue
  fi
  if [[ "$in_section" -eq 1 && "$line" =~ ^[[:space:]]*([0-9]+)\.[[:space:]] ]]; then
    cur_item="${BASH_REMATCH[1]}"
    item_exists["$cur_item"]=1
    item_letters["$cur_item"]=""
    item_opt_count["$cur_item"]=0
    item_star_count["$cur_item"]=0
    continue
  fi
  if [[ "$in_section" -eq 1 && -n "$cur_item" &&
    "$line" =~ ^[[:space:]]*-[[:space:]]+(★[[:space:]]+)?(а|б|в|г|ґ|д|е|А|Б|В|Г|Ґ|Д|Е)\) ]]; then
    starmark="${BASH_REMATCH[1]}"
    letter="$(normalize_letter "${BASH_REMATCH[2]}")"
    item_letters["$cur_item"]="${item_letters["$cur_item"]} $letter"
    item_opt_count["$cur_item"]=$((item_opt_count["$cur_item"] + 1))
    if [[ -n "$starmark" ]]; then
      item_star_count["$cur_item"]=$((item_star_count["$cur_item"] + 1))
      item_star_letter["$cur_item"]="$letter"
    fi
    continue
  fi
done <"$DIGEST_FILE"

# --- 2. Токенізація відповіді: пробіли й переводи рядків — роздільники, без glob. ---
content="$(cat "$REPLY_FILE")"
tokens=()
if [[ -n "$(trim "$content")" ]]; then
  IFS=$' \t\n' read -r -d '' -a tokens <<<"$content" || true
fi

# --- 3. Вільний текст: перший токен-роздільник «—»/«–»/«-» і все після нього. ---
sep_idx=-1
for i in "${!tokens[@]}"; do
  case "${tokens[$i]%,}" in
  "—" | "–" | "-")
    sep_idx=$i
    break
    ;;
  esac
done
text=""
cmd_tokens=()
if [[ "$sep_idx" -ge 0 ]]; then
  rest=("${tokens[@]:$((sep_idx + 1))}")
  text="$(
    IFS=' '
    echo "${rest[*]}"
  )"
  text="$(trim "$text")"
  if [[ "$sep_idx" -gt 0 ]]; then
    cmd_tokens=("${tokens[@]:0:$sep_idx}")
  fi
else
  cmd_tokens=("${tokens[@]}")
fi

# --- 4. Розбір командних токенів за граматикою. ---
decisions_json=()
merge_list=()
accepted_list=()
questions=()
declare -A seen_items
error=0
mode="normal" # normal | merge | accepted
have_num=0

question() {
  questions+=("$1")
  error=1
}

add_decision() {
  local item="$1" choice="$2" star="$3"
  if [[ "$choice" == "" ]]; then
    decisions_json+=("$(jq -nc --argjson item "$item" --argjson star "$star" '{item:$item, choice:null, star:$star}')")
  else
    decisions_json+=("$(jq -nc --argjson item "$item" --arg choice "$choice" --argjson star "$star" '{item:$item, choice:$choice, star:$star}')")
  fi
}

for rawTok in "${cmd_tokens[@]}"; do
  [[ "$error" -eq 1 ]] && break
  workTok="${rawTok%,}"

  is_kw_merge=0
  is_kw_accept=0
  case "$workTok" in
  "merge:" | "Merge:" | "MERGE:") is_kw_merge=1 ;;
  "прийнято:" | "Прийнято:") is_kw_accept=1 ;;
  esac

  if [[ "$is_kw_merge" -eq 1 || "$is_kw_accept" -eq 1 ]]; then
    if [[ "$mode" != "normal" && "$have_num" -eq 0 ]]; then
      question "«$rawTok» одразу після попереднього ключового слова без жодного номера"
      break
    fi
    if [[ "$is_kw_merge" -eq 1 ]]; then mode="merge"; else mode="accepted"; fi
    have_num=0
    continue
  fi

  if [[ "$mode" != "normal" ]]; then
    if [[ "$workTok" =~ ^#?([0-9]+)$ ]]; then
      num="${BASH_REMATCH[1]}"
      if [[ "$mode" == "merge" ]]; then merge_list+=("$num"); else accepted_list+=("$num"); fi
      have_num=1
      continue
    else
      question "«$rawTok» — очікував номер PR після ключового слова"
      break
    fi
  fi

  # normal: рішення по пункту.
  if [[ "$workTok" =~ ^([0-9]+)(.*)$ ]]; then
    n="${BASH_REMATCH[1]}"
    rest="${BASH_REMATCH[2]}"
    if [[ "$rest" == "*" ]]; then rest="★"; fi
    if [[ "$rest" != "★" ]]; then
      rest="$(normalize_letter "$rest")"
    fi

    if [[ -z "${item_exists[$n]:-}" ]]; then
      question "«$rawTok» — пункту $n немає в «Чекає на вас»"
      break
    fi
    if [[ -n "${seen_items[$n]:-}" ]]; then
      question "«$rawTok» — пункт $n уже названо в цій відповіді"
      break
    fi

    if [[ "$rest" == "" ]]; then
      if [[ "${item_opt_count[$n]}" -ne 0 ]]; then
        question "«$rawTok» — пункт $n має варіанти, голий номер не вибирає жодного"
        break
      fi
      seen_items[$n]=1
      add_decision "$n" "" false
    elif [[ "$rest" == "★" ]]; then
      sc="${item_star_count[$n]}"
      if [[ "$sc" -ne 1 ]]; then
        question "«$rawTok» — у пункті $n немає варіанта зі ★ або їх кілька"
        break
      fi
      seen_items[$n]=1
      add_decision "$n" "${item_star_letter[$n]}" true
    elif is_letter "$rest"; then
      if [[ " ${item_letters[$n]} " != *" $rest "* ]]; then
        question "«$rawTok» — у пункті $n немає варіанта «$rest»"
        break
      fi
      seen_items[$n]=1
      add_decision "$n" "$rest" false
    else
      question "«$rawTok» — незрозумілий варіант пункту $n"
      break
    fi
    continue
  fi

  question "«$rawTok» — незрозумілий токен"
  break
done

if [[ "$error" -eq 0 && "$mode" != "normal" && "$have_num" -eq 0 ]]; then
  if [[ "$mode" == "merge" ]]; then kw="merge:"; else kw="прийнято:"; fi
  question "«$kw» без жодного номера"
fi

if [[ "$error" -eq 1 ]]; then
  decisions_json=()
  merge_list=()
  accepted_list=()
fi

json_slurp() { # json_slurp <вже-валідний-JSON-рядок-на-елемент...> — [] якщо нема жодного
  if [[ $# -eq 0 ]]; then
    echo "[]"
  else
    printf '%s\n' "$@" | jq -cs '.'
  fi
}

decisions_combined="$(json_slurp "${decisions_json[@]}")"
merge_combined="$(json_slurp "${merge_list[@]}")"
accepted_combined="$(json_slurp "${accepted_list[@]}")"
questions_json=()
for q in "${questions[@]}"; do
  questions_json+=("$(jq -nc --arg q "$q" '$q')")
done
questions_combined="$(json_slurp "${questions_json[@]}")"

jq -n \
  --argjson decisions "$decisions_combined" \
  --argjson merge "$merge_combined" \
  --argjson accepted "$accepted_combined" \
  --arg text "$text" \
  --argjson questions "$questions_combined" \
  '{decisions: $decisions, merge: $merge, accepted: $accepted, text: $text, questions: $questions}'

if [[ "$error" -eq 1 ]]; then
  exit 4
fi
exit 0
