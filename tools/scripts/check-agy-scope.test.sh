#!/usr/bin/env bash
# check-agy-scope.test.sh — unit-прогін scope-guard'а `agy`-викликів.
# Запуск: tools/scripts/check-agy-scope.test.sh
set -euo pipefail

SCRIPT="$(dirname "$0")/check-agy-scope.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

# assert_exit <назва> <очікуваний-exit> <baseline> <current> [підрядок, який мусить бути у виводі]...
assert_exit() {
  local name="$1" expected="$2" baseline="$3" current="$4"
  shift 4
  local bfile="$TMP/baseline.txt" out="$TMP/out.txt" actual=0
  printf '%s' "$baseline" >"$bfile"
  "$SCRIPT" "$bfile" <<<"$current" >"$out" 2>&1 || actual=$?

  if [[ "$actual" -ne "$expected" ]]; then
    echo "✗ $name — очікував exit $expected, отримав $actual"
    cat "$out"
    fail=1
    return
  fi
  local needle
  for needle in "$@"; do
    if ! grep -qF -- "$needle" "$out"; then
      echo "✗ $name — у виводі немає «$needle»"
      cat "$out"
      fail=1
      return
    fi
  done
  echo "✓ $name"
}

# Брудне дерево, яке реально було у ~/hart на момент написання цього тесту:
# незакомічена робота yurii, що НЕ має вважатись scope-creep'ом `agy`.
DIRTY=$' M .claude/settings.json\n M CLAUDE.md\n M docs/parts/furniture_leg.md\n?? .github/workflows/ai-cloud-developer.yml\n'

# ── Базові гілки ────────────────────────────────────────────────────────────

# Тест 1: чисте дерево, `agy` нічого не змінив → 0.
assert_exit "чисто → 0" 0 "" ""

# Тест 2: запис у дозволену зону → 0.
assert_exit "запис у docs/promts/inputs/ → 0" 0 "" $'?? docs/promts/inputs/review-result.md\n'

# Тест 3: дослівний інцидент Master Run 8 — `agy` сам переписав docs/15 → 1.
assert_exit "docs/15_LLM_PROMPTS.md → 1" 1 "" $' M docs/15_LLM_PROMPTS.md\n' \
  "docs/15_LLM_PROMPTS.md" "git restore"

# Тест 4: кілька сторонніх файлів → 1, у виводі ВСІ до одного.
assert_exit "кілька сторонніх → 1 з повним списком" 1 "" \
  $' M docs/15_LLM_PROMPTS.md\n M docs/16_AUTONOMOUS_RUNS.md\n?? apps/web/src/rogue.tsx\n' \
  "docs/15_LLM_PROMPTS.md" "docs/16_AUTONOMOUS_RUNS.md" "apps/web/src/rogue.tsx"

# ── Брудне дерево: головна поправка (зонд працює саме в такому) ─────────────

# Тест 5: брудне дерево + чистий виклик `agy` → 0.
# Без baseline'у цей кейс давав би 3 фолси й робив guard непридатним у ~/hart.
assert_exit "брудне дерево + чистий виклик → 0" 0 "$DIRTY" "$DIRTY"

# Тест 6: брудне дерево + запис у дозволену зону → 0.
assert_exit "брудне дерево + запис у inputs/ → 0" 0 "$DIRTY" \
  "$DIRTY"$'?? docs/promts/inputs/_agy-probe-output.md\n'

# Тест 7: брудне дерево + НОВИЙ сторонній файл → 1, і у звіті ЛИШЕ новий.
assert_exit "брудне дерево + новий сторонній → 1 (baseline не згадується)" 1 "$DIRTY" \
  "$DIRTY"$' M docs/15_LLM_PROMPTS.md\n' \
  "docs/15_LLM_PROMPTS.md"
# Негативна перевірка має сенс лише разом із позитивною: інакше вона проходить
# і тоді, коли скрипта немає взагалі (вивід порожній → CLAUDE.md у ньому нема).
if grep -qF "docs/15_LLM_PROMPTS.md" "$TMP/out.txt" && ! grep -qF "CLAUDE.md" "$TMP/out.txt"; then
  echo "✓ baseline-файли не рахуються порушенням"
else
  echo "✗ брудне дерево: у звіті або немає нового порушення, або є baseline-файл CLAUDE.md"
  cat "$TMP/out.txt"
  fail=1
fi

# ── Формат porcelain ───────────────────────────────────────────────────────

# Тест 8: перейменування — судимо ПРИЗНАЧЕННЯ, не джерело.
assert_exit "rename у дозволену зону → 0" 0 "" \
  $'R  docs/promts/inputs/old.md -> docs/promts/inputs/new.md\n'
assert_exit "rename ПОЗА зону → 1" 1 "" \
  $'R  docs/promts/inputs/old.md -> docs/15_LLM_PROMPTS.md\n' \
  "docs/15_LLM_PROMPTS.md"

# Тест 9: шлях у лапках (porcelain квотує пробіли) → зона розпізнається.
assert_exit "квотований шлях у зоні → 0" 0 "" \
  $'?? "docs/promts/inputs/з пробілом.md"\n'

# Тест 10: сусідній каталог із тим самим префіксом — НЕ дозволена зона.
assert_exit "docs/promts/inputs-other/ → 1 (не фолс-дозвіл)" 1 "" \
  $'?? docs/promts/inputs-other/x.md\n' \
  "docs/promts/inputs-other/x.md"

# Тест 11: staged-стан у дозволеній зоні (XY = 'A ') → 0.
assert_exit "staged у зоні → 0" 0 "" $'A  docs/promts/inputs/new.md\n'

# Тест 11-bis: git схлопнув неторкану теку-предка зони → 2, а не тихий вердикт.
assert_exit "схлопнута тека-предок → 2 (невизначено)" 2 "" $'?? docs/\n' \
  "--untracked-files=all"

# Тест 11-ter: схлопнута тека, що НЕ предок зони — звичайне порушення.
assert_exit "схлопнута стороння тека → 1" 1 "" $'?? apps/\n' "apps/"

# ── Придатна команда відкату ───────────────────────────────────────────────

# Тест 12: untracked не відкочується `git restore` — мусить бути `rm`.
assert_exit "untracked → пропонує rm, не git restore" 1 "" \
  $'?? apps/web/src/rogue.tsx\n' \
  "rm -- " "apps/web/src/rogue.tsx"

# Тест 13: трекований → пропонує git restore.
assert_exit "трекований → пропонує git restore" 1 "" \
  $' M docs/16_AUTONOMOUS_RUNS.md\n' \
  "git restore -- "

# ── Виклик без baseline'у / з битим baseline'ом ────────────────────────────

# Тест 14: baseline не передано — сумісність із чистим деревом (exit 0).
out=0
"$SCRIPT" <<<"" >"$TMP/out.txt" 2>&1 || out=$?
if [[ "$out" -eq 0 ]]; then echo "✓ без baseline-аргументу → 0"; else
  echo "✗ без baseline-аргументу — очікував 0, отримав $out"
  cat "$TMP/out.txt"
  fail=1
fi

# Тест 15: baseline вказано, але файлу немає — це помилка ВИКЛИКУ, не «чисто».
# Тихо вважати таке чистим деревом означало б guard, який мовчки не працює.
out=0
"$SCRIPT" "$TMP/neisnuye.txt" <<<$' M CLAUDE.md\n' >"$TMP/out.txt" 2>&1 || out=$?
if [[ "$out" -eq 2 ]]; then echo "✓ відсутній baseline-файл → 2 (помилка виклику)"; else
  echo "✗ відсутній baseline-файл — очікував 2, отримав $out"
  cat "$TMP/out.txt"
  fail=1
fi

if [[ "$fail" -eq 1 ]]; then
  echo "FAIL"
  exit 1
fi
echo "Усі тести пройдено."
