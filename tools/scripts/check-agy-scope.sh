#!/usr/bin/env bash
# check-agy-scope.sh — механізує правило «після КОЖНОГО виклику `agy` звір
# `git status`: змінитись мав лише доручений файл».
#
# ЧОМУ ЦЕ ІСНУЄ. `write_file(*)` у `~/.gemini/antigravity-cli/settings.json`
# ширший за задум (вужчий glob на практиці не спрацював), і `agy` ДВІЧІ сам
# переписував документ, якого йому не доручали: Master Run 8 Стадія 1 —
# `docs/15_LLM_PROMPTS.md`, Стадія 3 — `agy-orchestration-recommendations.md`.
# Обидва рази це побачили руками, через `git status` ПІСЛЯ виклику. Ручний
# ритуал, який двічі коштував відкату, має бути командою.
#
# BASELINE — не опція, а умова придатності. Дерево під час виклику `agy`
# майже завжди брудне (незакомічена робота, транзитні файли зонда). Без
# baseline'у guard репортував би цю роботу як scope-creep, його б вимикали, і
# він став би тією самою декорацією, проти якої написаний `docs/16` §1. Тому
# порівнюється РІЗНИЦЯ до/після, а не абсолютний список.
#
# ЧОГО ЦЕЙ СКРИПТ НЕ ДОВОДИТЬ: якщо файл був брудним ДО виклику, дальша його
# правка `agy` не видна — porcelain-рядок не змінюється (` M x` лишається
# ` M x`). Ця сліпа зона лежить у самому форматі; закрити її можна лише
# baseline'ом із хешами вмісту. Тому «зелений» тут означає «нових сторонніх
# шляхів не з'явилось», а не «agy не торкався нічого чужого».
#
# НЕ ВІДКОЧУЄ САМ — свідомо: автовідкат знищив би незбережену роботу, якщо
# запустити його не в той момент. Скрипт дає факт і точну команду; рішення —
# за людиною (verify-then-revert, `agy-orchestration-recommendations.md` §4).
#
# Використання:
#   git status --porcelain > /tmp/agy-baseline.txt     # ДО виклику
#   agy -p "..."                                       # виклик
#   git status --porcelain | tools/scripts/check-agy-scope.sh /tmp/agy-baseline.txt
#
# exit 0 — нових шляхів поза дозволеною зоною немає;
# exit 1 — scope-creep (список + готова команда відкату);
# exit 2 — помилка виклику (baseline вказано, але не читається).
set -euo pipefail

ALLOWED_ZONE='^docs/promts/inputs/'
ALLOWED_ZONE_PATH='docs/promts/inputs/'

BASELINE="${1:-}"
if [[ -n "$BASELINE" && ! -r "$BASELINE" ]]; then
  echo "::error::baseline-файл «$BASELINE» не читається — зніміть його ДО виклику agy: git status --porcelain > $BASELINE" >&2
  exit 2
fi

# porcelain-рядок → шлях. Формат: XY<space>path, де XY — двобуквенний статус.
# Для R/C (rename/copy) значення має ПРИЗНАЧЕННЯ: `R  old -> new`.
# Шляхи з пробілами/не-ASCII porcelain віддає в лапках.
porcelain_path() {
  local line="$1" xy rest
  xy="${line:0:2}"
  rest="${line:3}"
  if [[ "$xy" == [RC]* && "$rest" == *" -> "* ]]; then
    rest="${rest##* -> }"
  fi
  if [[ "$rest" == \"*\" ]]; then
    rest="${rest:1:-1}"
  fi
  printf '%s' "$rest"
}

declare -A baseline_paths=()
if [[ -n "$BASELINE" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    baseline_paths["$(porcelain_path "$line")"]=1
  done <"$BASELINE"
fi

tracked_violations=()
untracked_violations=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  path="$(porcelain_path "$line")"
  # Уже було брудним до виклику — не наша справа (див. «сліпа зона» вище).
  [[ -n "${baseline_paths["$path"]:-}" ]] && continue
  [[ "$path" =~ $ALLOWED_ZONE ]] && continue
  # git схлопує повністю неторкану теку в ОДИН рядок (`?? docs/`). Якщо така
  # тека — предок дозволеної зони, вміст невідомий: усередині може бути і
  # законний файл зонда, і самовільний запис. Мовчки пропустити = дірка,
  # мовчки звалити = фолс. Тому кажемо прямо, що статус треба гранульований.
  if [[ "${line:0:2}" == '??' && "$path" == */ && "$ALLOWED_ZONE_PATH" == "$path"* ]]; then
    echo "::error::git віддав схлопнуту неторкану теку «$path» — вміст невідомий, класифікувати неможливо." >&2
    echo "Передайте гранульований статус: git status --porcelain --untracked-files=all" >&2
    exit 2
  fi
  if [[ "${line:0:2}" == '??' ]]; then
    untracked_violations+=("$path")
  else
    tracked_violations+=("$path")
  fi
done

violations=("${tracked_violations[@]}" "${untracked_violations[@]}")
if [[ ${#violations[@]} -eq 0 ]]; then
  echo "OK: поза docs/promts/inputs/ нових змін немає."
  exit 0
fi

echo "::error::agy вийшов за межі docs/promts/inputs/ (${#violations[@]} шлях(и)): ${violations[*]}" >&2
printf '  ✗ %s\n' "${violations[@]}" >&2
echo >&2
echo "Звірте вміст ПЕРЕД тим, як довіряти будь-якому виводу цього запуску, і відкотіть стороннє:" >&2
if [[ ${#tracked_violations[@]} -gt 0 ]]; then
  printf '  git restore -- %s\n' "$(printf '%q ' "${tracked_violations[@]}")" >&2
fi
if [[ ${#untracked_violations[@]} -gt 0 ]]; then
  printf '  rm -- %s\n' "$(printf '%q ' "${untracked_violations[@]}")" >&2
fi
exit 1
