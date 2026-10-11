#!/usr/bin/env bash
# agy-opus-budget.test.sh — лічильник ліміту «Claude and GPT» в agy: вікно 7 днів,
# які моделі рахуються, поріг, відмови; покази екрана yurii (до скидання, після, застарілий);
# мутації — кожне правило тримається тестом.
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
[[ "$out" == *": 12, бюджет 13"* && "$out" == *"→ контрприклади ризикового PR: Claude Sonnet 5.5 — спершу agy; не відповів — окрема сесія (bash tools/scripts/claude-review-session.sh), CLAUDE.md §0 п.2" && "$out" != *"витрачено не менше"* ]] &&
  ok "12 з 13 — ще agy Opus" || bad "12 з 13: $out"
journal "$T/j" "${rows[@]}" "$(row 2026-09-27 'Claude Opus 4.6 (Thinking)')"
out="$(run --today 2026-09-27 "$T/j")"
[[ "$out" == *": 13, бюджет 13"* && "$out" == *"витрачено не менше бюджету"* ]] &&
  ok "13 з 13 — окрема сесія Claude Code" || bad "13 з 13: $out"
out="$(AGY_OPUS_BUDGET=20 run --today 2026-09-27 "$T/j")"
[[ "$out" == *"бюджет 20"* && "$out" == *"→ контрприклади ризикового PR: Claude Sonnet 5.5 — спершу agy; не відповів — окрема сесія (bash tools/scripts/claude-review-session.sh), CLAUDE.md §0 п.2" && "$out" != *"витрачено не менше"* ]] &&
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
for args in "--today" "--today 27.09.2026" "--today 2026-13-45" "--now" "--now 2026-09-27" "--force" "$T/немає.md"; do
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

# ─── 7b. Архів і тека agy-stats/ — файл на PR (рішення yurii 2026-10-11, #228) ─
# Окремий каталог: тека — це agy-stats/ поруч з архівом. Каталог поза git, а файлів
# теки два: порядок іспиту лічильнику не потрібен (unordered), тож і історія git — теж
# (тест на справжньому журналі йде в мілкому клоні job «Guard-скрипти»).
mkdir -p "$T/s/agy-stats"
journal "$T/s/agy-stats.md" "$(row 2026-09-27 'Claude Opus 4.6 (Thinking)')"
{ echo "$HEAD"; row 2026-09-27 'Claude Sonnet 5.5 (High)'; row 2026-09-26 'Gemini 3.8 Flash (High)'; } >"$T/s/agy-stats/feat-a.md"
{ echo "$HEAD"; row 2026-09-25 'Claude Opus 5.5 (High)'; row 2026-09-25 'claude-sonnet-5-5 (окрема сесія)'; } >"$T/s/agy-stats/feat-b.md"
out="$(run --today 2026-09-27 "$T/s/agy-stats.md")"
[[ $? == 0 && "$out" == *": 3, бюджет"* ]] &&
  ok "архів + два файли теки: рахуються виклики з усіх (3: Opus 4.6, Sonnet 5.5, Opus 5.5)" || bad "тека не врахована: $out"
{ echo "$HEAD"; echo '| 2026-09-27 | grep a | b | Claude Opus 4.6 (Thinking) | ok | так | n-a | **0** | **0** |'; } >"$T/s/agy-stats/feat-c.md"
out="$(run --today 2026-09-27 "$T/s/agy-stats.md")"
[[ $? == 2 && "$out" == *"feat-c.md"* && "$out" != *"→"* ]] && ok "зсунутий рядок у файлі теки — відмова з іменем файла (exit 2)" ||
  bad "зсунутий рядок у теці дав рішення: $out"
rm -f "$T/s/agy-stats/feat-c.md"
X="$(mktemp -d)"
cp "$SCRIPT" "$X/agy-opus-budget.sh"
out="$(bash "$X/agy-opus-budget.sh" --today 2026-09-27 "$T/s/agy-stats.md" 2>&1)"
[[ $? == 2 && "$out" == *"journal-rules.sh"* && "$out" != *"→"* ]] && ok "без journal-rules.sh — відмова, exit 2" ||
  bad "без journal-rules.sh рішення дано: $out"
rm -rf "$X"

# ─── 9. Покази екрана yurii (agy-quota.md) ─────────────────────────────────
QH='| Показ, UTC | Група | Залишок, % | Скидання, UTC | Джерело |
| --- | --- | --- | --- | --- |'
quota() { { echo "$QH"; printf '%s\n' "$@"; } >"$T/agy-quota.md"; }
# Рядок називає Sonnet 5.5 (рішення yurii 2026-10-09: контрприклади — Sonnet 5.5 незалежно
# від автора; agy не відповів — окрема сесія), і без примітки «витрачено не менше бюджету».
opus() { [[ "$1" == *"→ контрприклади ризикового PR: Claude Sonnet 5.5 — спершу agy; не відповів — окрема сесія (bash tools/scripts/claude-review-session.sh), CLAUDE.md §0 п.2"* && "$1" != *"витрачено не менше"* ]]; }
solo() { [[ "$1" == *"→ контрприклади ризикового PR: Claude Sonnet 5.5 — спершу agy; не відповів — окрема сесія (bash tools/scripts/claude-review-session.sh), CLAUDE.md §0 п.2"* && "$1" == *"витрачено не менше бюджету"* && "$1" != *"не буде"* ]]; }
# 18 викликів Opus за 23…29.09 — як у справжньому журналі 29.09.
rows=()
for d in 23 24 25 26 27 28; do for _ in 1 2 3; do rows+=("$(row 2026-09-$d 'Claude Opus 4.6 (Thinking)')"); done; done
journal "$T/j" "${rows[@]}"
quota '| 2026-09-29 07:09 | Claude and GPT | 0.00 | 2026-09-30 19:21 | скріншот |'
out="$(run --now '2026-09-30 19:00' "$T/j")"
solo "$out" && [[ "$out" == *"0.00%, скидання 2026-09-30 19:21"* ]] &&
  ok "показ 0% — до скидання окрема сесія" || bad "показ 0% до скидання: $out"
out="$(run --now '2026-09-30 19:30' "$T/j")"
opus "$out" && [[ "$out" == *"минуло — нове тижневе вікно"* && "$out" == *"(2026-09-30 … 2026-09-30): 0, бюджет 13"* ]] &&
  ok "після скидання — знову Opus, хоча за 7 днів 18 викликів (рішення yurii: спершу Opus)" || bad "після скидання не Opus: $out"
rm -f "$T/agy-quota.md"
out="$(run --now '2026-09-30 19:30' "$T/j")"
solo "$out" && ok "без показу — стара оцінка за 7 днів (18 з 13 → окрема сесія)" || bad "без показу: $out"

# Виклики в день скидання рахуються (часу в журналі немає — сумнів проти ліміту).
rows=()
for _ in $(seq 13); do rows+=("$(row 2026-09-30 'Claude Opus 4.6 (Thinking)')"); done
journal "$T/j" "${rows[@]}"
quota '| 2026-09-29 07:09 | Claude and GPT | 0.00 | 2026-09-30 19:21 | скріншот |'
out="$(run --now '2026-10-02 10:00' "$T/j")"
solo "$out" && [[ "$out" == *": 13, бюджет 13"* ]] && ok "13 викликів з дня скидання — окрема сесія" || bad "день скидання: $out"

# До скидання — від залишку: ⌈(R − 20) × 13 / 80⌉ викликів (поки залишок перед викликом > 20%).
for c in "15.53|0|0|solo" "20|0|0|solo" "25|1|0|opus" "25|1|1|solo" "60|7|6|opus" "60|7|7|solo" "100|13|12|opus" "100|13|13|solo"; do
  IFS='|' read -r left lim calls want <<<"$c"
  rows=()
  for _ in $(seq "$calls"); do rows+=("$(row 2026-10-01 'Claude Opus 4.6 (Thinking)')"); done
  journal "$T/j" "${rows[@]}"
  quota "| 2026-10-01 09:00 | Claude and GPT | $left | 2026-10-05 12:00 | скріншот |"
  out="$(run --now '2026-10-01 18:00' "$T/j")"
  if [[ "$out" == *"(2026-10-01 … 2026-10-01): $calls, можна ще, поки залишок вищий за 20%: $lim"* ]] && "$want" "$out"; then
    ok "показ $left%, викликів $calls — можна $lim → $want"
  else
    bad "показ $left%, викликів $calls: $out"
  fi
done

# Який показ береться: останній не пізніше «зараз», лише група «Claude and GPT».
journal "$T/j"
quota '| 2026-10-01 09:00 | Claude and GPT | 0.00 | 2026-10-05 12:00 | старий |' \
  '| 2026-10-02 09:00 | Claude and GPT | 100 | 2026-10-05 12:00 | новіший |' \
  '| 2026-10-02 10:00 | Gemini | 0.00 | 2026-10-05 12:00 | інша група |' \
  '| 2026-10-03 09:00 | Claude and GPT | 0.00 | 2026-10-05 12:00 | ще не настав |'
out="$(run --now '2026-10-02 18:00' "$T/j")"
opus "$out" && [[ "$out" == *"2026-10-02 09:00 UTC"* ]] &&
  ok "береться останній показ «Claude and GPT» не пізніше «зараз»; Gemini і майбутній — ні" || bad "не той показ: $out"

# Показ застарів: скидання минуло понад 7 днів тому — оцінка і прохання глянути екран.
journal "$T/j" "${rows[@]}"
quota '| 2026-09-29 07:09 | Claude and GPT | 0.00 | 2026-09-30 19:21 | скріншот |'
out="$(run --now '2026-10-07 19:30' "$T/j")"
[[ "$out" == *"застарів"* && "$out" == *"глянути екран"* && "$out" == *"викликів за 7 днів (2026-10-01 … 2026-10-07)"* ]] &&
  ok "показ старший за скидання + 7 днів — оцінка за журналом і прохання до yurii" || bad "застарілий показ: $out"

# Відмова agy 429 як показ: «Resets in» ≤ 5 год може бути п'ятигодинним лімітом — відмова
# скрипта, а не «новий тиждень → Opus» після його скидання (повторна рецензія #145).
journal "$T/j"
quota '| 2026-10-01 10:00 | Claude and GPT | 0 | 2026-10-01 13:30 | лог agy: 429, Resets in 3h30m |'
out="$(run --now '2026-10-01 14:00' "$T/j")"
[[ $? == 2 && "$out" == *"п'ятигодинний"* && "$out" != *"→"* ]] &&
  ok "429 з «Resets in» 3h30m — відмова, не показ" || bad "429 п'ятигодинного ліміту прийнято як показ: $out"
quota '| 2026-10-01 10:00 | Claude and GPT | 0 | 2026-10-03 12:05 | лог agy: 429, Resets in 50h5m |'
out="$(run --now '2026-10-01 14:00' "$T/j")"
solo "$out" && ok "429 з «Resets in» 50h5m — тижневий показ, окрема сесія до скидання" || bad "тижневий 429: $out"
quota '| 2026-10-01 10:00 | Claude and GPT | 0 | 2026-10-01 13:00 | скріншот: Refreshes in 3h |'
out="$(run --now '2026-10-01 14:00' "$T/j")"
opus "$out" && ok "скріншот тижневого ліміту зі скиданням за 3 год — показ, після скидання Opus" || bad "короткий скріншот: $out"

# Зіпсований показ — відмова, а не рішення.
for bad_row in '| 2026-09-29 7:09 | Claude and GPT | 0 | 2026-09-30 19:21 | x |' \
  '| 2026-09-29 07:09 | Claude and GPT | 0,5 | 2026-09-30 19:21 | x |' \
  '| 2026-09-29 07:09 | Claude and GPT | 120 | 2026-09-30 19:21 | x |' \
  '| 2026-09-29 07:09 | Claude and GPT | 0 | через 36 год | x |'; do
  quota "$bad_row"
  out="$(run --now '2026-09-30 10:00' "$T/j")"
  [[ $? == 2 && "$out" == *"відмова"* && "$out" != *"→"* ]] && ok "зіпсований показ — exit 2: $bad_row" ||
    bad "зіпсований показ дав рішення: $bad_row → $out"
done

# Справжні покази: до скидання 30.09 19:21 — окрема сесія, після — Opus.
cp "$HERE/../../docs/promts/inputs/agy-quota.md" "$T/agy-quota.md"
journal "$T/j"
out="$(run --now '2026-09-30 19:00' "$T/j")"
solo "$out" && ok "справжній agy-quota.md: 30.09 19:00 UTC — окрема сесія" || bad "справжні покази до скидання: $out"
out="$(run --now '2026-09-30 19:30' "$T/j")"
opus "$out" && ok "справжній agy-quota.md: 30.09 19:30 UTC — Opus" || bad "справжні покази після скидання: $out"
rm -f "$T/agy-quota.md"

# ─── 8. Мутації ─────────────────────────────────────────────────────────────
if [[ -z "${OPUS_BUDGET_UNDER_TEST:-}" && $fail == 0 ]]; then
  src="$(<"$SCRIPT")"
  # Розбір рядків журналу живе в journal-rules.sh (спільний з agy-stats-summary.sh), який
  # скрипт підключає поруч із собою: мутант — тека з копією обох, де змінено ОДИН.
  lib="$HERE/journal-rules.sh"
  libsrc="$(<"$lib")"
  n=0
  mutate() { # mutate <назва> <було> <стало> [lib] — «було» мусить стояти рівно раз
    local name="$1" from="$2" to="$3" which="${4:-script}" body rest d="$T/mut$((++n))" m
    body="$src"
    [[ "$which" == lib ]] && body="$libsrc"
    rest="${body#*"$from"}"
    if [[ "$rest" == "$body" || "$rest" == *"$from"* ]]; then
      bad "мутант «$name»: текст не знайдено рівно один раз — мутація застаріла"
      return
    fi
    mkdir -p "$d"
    m="$d/agy-opus-budget.sh"
    cp "$SCRIPT" "$m"
    cp "$lib" "$d/journal-rules.sh"
    if [[ "$which" == lib ]]; then
      printf '%s\n' "${body/"$from"/"$to"}" >"$d/journal-rules.sh"
    else
      printf '%s\n' "${body/"$from"/"$to"}" >"$m"
    fi
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
    mutate "поріг «більше», а не «не менше»" '((n >= limit))' '((n > limit))'
    mutate "зсунутий рядок рахується" 'END { if (bad) exit 3 }' 'END { }' lib
    mutate "тека не читається" '[[ -d "$dir" ]] || return 0' 'return 0' lib
    mutate "порядок іспиту — з git (тека поза git чи мілкий клон — відмова)" 'journal_rows "$FILE" unordered | awk' 'journal_rows "$FILE" | awk'
    mutate "лише архів, без journal_rows" 'journal_rows "$FILE" unordered | awk' "sed 's/\\\\|/\\x1f/g' \"\$FILE\" | awk"
    mutate "покази екрана не читаються" 'if [[ -f "$QUOTA" ]]; then' 'if false; then'
    mutate "після скидання — все ще 7 днів поспіль" 'n="$(calls_since "${reset%% *}")"' 'n="$(calls_since "$from")"'
    mutate "залишок без запасу 20%" 'a = (r - 20) * b / 80;' 'a = r * b / 80;'
    mutate "округлення вниз (при 25% — 0 викликів)" 'if (c < a) c++;' ''
    mutate "429 п'ятигодинного ліміту — показ" '((reset_s - $(epoch "$shown") <= 5 * 3600))' '((0))'
    mutate "показ не старіє" '((NOW_S < reset_s + 7 * 86400))' '((1))'
    mutate "будь-яка група" 'g == "Claude and GPT" &&' ''
    mutate "майбутній показ береться" 't <= now &&' ''
    mutate "зіпсований показ береться" 'END { if (bad) exit 3; print out }' 'END { print out }'
    mutate "старий рядок 165 (окрема сесія замість контрприкладів, #198)" ' · за журналом витрачено не менше бюджету — лише інформація, контрприклади все одно спершу в agy"' '"; echo "→ контрприклади ризикового PR: окрема сесія Claude Code — bash tools/scripts/claude-review-session.sh"'
    mutate "\\| не екранується" '{ gsub(/\\\|/, "\037") }' '{ }' lib
  }
fi

if [[ $fail == 1 ]]; then
  echo "FAIL"
  exit 1
fi
echo "Усі тести пройдено."
