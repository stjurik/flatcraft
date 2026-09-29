#!/usr/bin/env bash
# agy-opus-budget.test.sh — лічильник ліміту «Claude and GPT» в agy: вікно 7 днів,
# які моделі рахуються, поріг, відмови; мутації — кожне правило тримається тестом.
# Запуск: tools/scripts/agy-opus-budget.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${OPUS_BUDGET_UNDER_TEST:-$HERE/agy-opus-budget.sh}"
REAL="$HERE/../../docs/promts/inputs/agy-stats.md"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail=0
ok() { echo "✓ $1"; }
bad() {
  echo "✗ $1"
  fail=1
  [[ -z "${OPUS_BUDGET_UNDER_TEST:-}" ]] || exit 1
}

HEAD='| Дата | Задача | Модель agy | Результат | Вердикт | Кейсів | Вигаданих фактів | Справжніх знахідок |
| ---- | ------ | ---------- | --------- | ------- | ------ | ---------------- | ------------------ |'
row() { echo "| $1 | задача | $2 | ok | так | n-a | **0** | **0** |"; }
journal() { # journal <файл> <рядок>... — журнал із шапкою
  local f="$1"
  shift
  { echo "# журнал"; echo; echo "$HEAD"; printf '%s\n' "$@"; } >"$f"
}
run() { bash "$SCRIPT" "$@" 2>&1; }

# ─── 1. Вікно — рівно 7 днів, включно з сьогодні ───────────────────────────
journal "$T/j" \
  "$(row 2026-09-20 'Claude Opus 4.6 (Thinking)')" \
  "$(row 2026-09-21 'Claude Opus 4.6 (Thinking)')" \
  "$(row 2026-09-27 'Claude Opus 4.6 (Thinking)')" \
  "$(row 2026-09-28 'Claude Opus 4.6 (Thinking)')"
out="$(run --today 2026-09-27 "$T/j")"
[[ "$out" == *"(2026-09-21 … 2026-09-27): 2,"* ]] &&
  ok "вікно 21…27: день -6 і сьогодні рахуються, день -7 і завтра — ні (2)" || bad "вікно рахує не те: $out"

# ─── 2. Яка модель рахується ───────────────────────────────────────────────
journal "$T/j" \
  "$(row 2026-09-27 'Claude Opus 4.6 (Thinking)')" \
  "$(row 2026-09-27 'Claude Sonnet 4.6 (Thinking)')" \
  "$(row 2026-09-27 'GPT-OSS 120B (Medium)')" \
  "$(row 2026-09-27 'невідомо → Claude Opus 4.6 (Thinking)')" \
  "$(row 2026-09-27 'Gemini 3.8 Flash (High)')" \
  "$(row 2026-09-27 'Gemini 3.1 Pro (High)')" \
  "$(row 2026-09-27 'невідомо → Gemini 3.1 Pro (High)')"
out="$(run --today 2026-09-27 "$T/j")"
[[ "$out" == *": 4, бюджет"* ]] &&
  ok "рахуються Opus, Sonnet, GPT і «невідомо → Claude»; Gemini — ні (4)" || bad "модель рахується не так: $out"

# ─── 2b. Окрема сесія Claude — не з ліміту agy ─────────────────────────────
journal "$T/j" \
  "$(row 2026-09-27 'Claude Opus 4.6 (Thinking)')" \
  "$(row 2026-09-27 'claude-sonnet-5-5 (окрема сесія)')" \
  "$(row 2026-09-27 'Claude Sonnet 5.5 (окрема сесія)')" \
  "$(row 2026-09-27 'claude-opus-4-6 (окрема сесія)')"
out="$(run --today 2026-09-27 "$T/j")"
[[ "$out" == *": 1, бюджет"* ]] &&
  ok "рядки «(окрема сесія)» не рахуються в ліміт agy, як би їх не написали (1)" || bad "окрема сесія з'їдає ліміт agy: $out"

# ─── 3. Поріг: бюджет-1 → agy, бюджет → окрема сесія ───────────────────────
rows=()
for _ in $(seq 12); do rows+=("$(row 2026-09-27 'Claude Opus 4.6 (Thinking)')"); done
journal "$T/j" "${rows[@]}"
out="$(run --today 2026-09-27 "$T/j")"
[[ "$out" == *": 12, бюджет 13"* && "$out" == *"→ контрприклади ризикового PR: agy, Claude Opus 4.6"* ]] &&
  ok "12 з 13 — ще agy Opus" || bad "12 з 13: $out"
journal "$T/j" "${rows[@]}" "$(row 2026-09-27 'Claude Opus 4.6 (Thinking)')"
out="$(run --today 2026-09-27 "$T/j")"
[[ "$out" == *": 13, бюджет 13"* && "$out" == *"окрема сесія Claude Code"* ]] &&
  ok "13 з 13 — окрема сесія Claude Code" || bad "13 з 13: $out"
out="$(AGY_OPUS_BUDGET=20 run --today 2026-09-27 "$T/j")"
[[ "$out" == *"бюджет 20"* && "$out" == *"agy, Claude Opus"* ]] &&
  ok "AGY_OPUS_BUDGET змінює поріг (перекалібрування)" || bad "AGY_OPUS_BUDGET не діє: $out"

# ─── 4. `\|` у клітинці не зсуває колонки ──────────────────────────────────
journal "$T/j" '| 2026-09-27 | grep a \| b | Claude Opus 4.6 (Thinking) | ok | так | n-a | **0** | **0** |'
out="$(run --today 2026-09-27 "$T/j")"
[[ $? == 0 && "$out" == *": 1, бюджет"* ]] && ok "екранований \\| у задачі — модель читається правильно" ||
  bad "екранований \\| зламав розбір: $out"

# ─── 5. Неекранований «|» — відмова, а не число ────────────────────────────
journal "$T/j" '| 2026-09-27 | grep a | b | Claude Opus 4.6 (Thinking) | ok | так | n-a | **0** | **0** |'
out="$(run --today 2026-09-27 "$T/j")"
[[ $? == 2 && "$out" == *"відмова"* && "$out" != *"→"* ]] && ok "зсунутий рядок — відмова (exit 2), без рішення" ||
  bad "зсунутий рядок дав рішення: $out"

# ─── 6. Погані аргументи й журнал — exit 2 ─────────────────────────────────
for args in "--today" "--today 27.09.2026" "--today 2026-13-45" "--force" "$T/немає.md"; do
  # shellcheck disable=SC2086 # аргументи навмисно розбиваються
  out="$(run $args)"
  [[ $? == 2 && "$out" != *"→"* ]] && ok "аргументи «$args» — exit 2" || bad "аргументи «$args» прийнято: $out"
done
out="$(AGY_OPUS_BUDGET=0 run --today 2026-09-27 "$T/j")"
[[ $? == 2 ]] && ok "AGY_OPUS_BUDGET=0 — відмова" || bad "AGY_OPUS_BUDGET=0 прийнято: $out"

# ─── 7. Справжній журнал читається без відмови ─────────────────────────────
out="$(run --today 2026-09-27 "$REAL")"
[[ $? == 0 && "$out" == *"→ контрприклади"* ]] && ok "справжній agy-stats.md розбирається: ${out%%$'\n'*}" ||
  bad "справжній журнал не розібрано: $out"

# ─── 8. Мутації ─────────────────────────────────────────────────────────────
if [[ -z "${OPUS_BUDGET_UNDER_TEST:-}" && $fail == 0 ]]; then
  src="$(<"$SCRIPT")"
  n=0
  mutate() { # mutate <назва> <було> <стало> — «було» мусить стояти в скрипті рівно раз
    local name="$1" from="$2" to="$3" rest m="$T/mut$((++n)).sh"
    rest="${src#*"$from"}"
    if [[ "$rest" == "$src" || "$rest" == *"$from"* ]]; then
      bad "мутант «$name»: текст не знайдено рівно один раз — мутація застаріла"
      return
    fi
    printf '%s\n' "${src/"$from"/"$to"}" >"$m"
    if OPUS_BUDGET_UNDER_TEST="$m" bash "$HERE/$(basename "$0")" >"$m.out" 2>&1; then
      bad "мутант ВИЖИВ: $name"
    else
      ok "мутанта вбито: $name"
    fi
  }
  # shellcheck disable=SC2016 # дослівний текст скрипта
  {
    mutate "вікно 8 днів" '"$TODAY -6 days"' '"$TODAY -7 days"'
    mutate "рахується лише Opus" 'm ~ /Claude|GPT/ &&' 'm ~ /^Claude Opus/ &&'
    mutate "окрема сесія їсть ліміт agy" ' && m !~ /окрема сесія/' ''
    mutate "поріг «більше», а не «не менше»" '((n >= BUDGET))' '((n > BUDGET))'
    mutate "зсунутий рядок рахується" 'END { if (bad) exit 3;' 'END {'
    mutate "\\| не екранується" "sed 's/\\\\|/\\x1f/g'" "sed 's/x/x/'"
  }
fi

if [[ $fail == 1 ]]; then
  echo "FAIL"
  exit 1
fi
echo "Усі тести пройдено."
