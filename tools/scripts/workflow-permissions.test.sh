#!/usr/bin/env bash
# workflow-permissions.test.sh — кожен workflow має блок `permissions:` верхнього рівня.
#
# ЧОМУ. Без нього job отримує права токена за замовчуванням для репозиторію, а CI
# проганяє код гілки PR (незалежне ревю 2026-11, №8). У ci.yml блоку не було до #318;
# рецензія #318 (Flash №2): наявність блоку нічим не охоронена — видалили б мовчки.
#
# ЧОГО НЕ ДОВОДИТЬ. Що права в блоці мінімальні: це рішення кожного workflow, і його
# видно в diff. Тест ловить лише «блоку немає зовсім».
# Запуск: tools/scripts/workflow-permissions.test.sh [тека з workflow]
set -uo pipefail

DIR="${1:-$(cd "$(dirname "$0")/../.." && pwd)/.github/workflows}"
fail=0
n=0
for f in "$DIR"/*.yml "$DIR"/*.yaml; do
  [[ -e "$f" ]] || continue
  n=$((n + 1))
  if grep -q '^permissions:' "$f"; then
    echo "✓ $(basename "$f") — є permissions верхнього рівня"
  else
    echo "✗ $(basename "$f") — немає блоку permissions верхнього рівня"
    fail=1
  fi
done
((n > 0)) || { echo "✗ у $DIR немає жодного workflow — тест нічого не перевірив"; fail=1; }

# Самоперевірка: тест мусить червоніти на workflow без блоку.
if [[ $# -eq 0 ]]; then
  t="$(mktemp -d)"
  printf 'name: x\non: push\njobs: {}\n' >"$t/x.yml"
  if bash "$0" "$t" >/dev/null 2>&1; then
    echo "✗ тест зелений на workflow без permissions — перевірка не діє"
    fail=1
  else
    echo "✓ самоперевірка: workflow без permissions — червоний"
  fi
  rm -rf "$t"
fi

((fail == 0)) && echo "Усі тести пройдено." || echo "FAIL"
exit "$fail"
