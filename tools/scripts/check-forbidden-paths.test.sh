#!/usr/bin/env bash
# check-forbidden-paths.test.sh — unit-прогін ADR-035 verification-step
# з тестовим diff'ом (синтетичний список файлів, формат `git diff --name-only`).
# Запуск: tools/scripts/check-forbidden-paths.test.sh
set -euo pipefail

SCRIPT="$(dirname "$0")/check-forbidden-paths.sh"
fail=0

assert_exit() {
  local name="$1" expected="$2"
  shift 2
  local actual=0
  "$SCRIPT" <<<"$*" >/tmp/check-forbidden-paths.test.out 2>&1 || actual=$?
  if [[ "$actual" -eq "$expected" ]]; then
    echo "✓ $name"
  else
    echo "✗ $name — очікував exit $expected, отримав $actual"
    cat /tmp/check-forbidden-paths.test.out
    fail=1
  fi
}

# Тест 1: тестовий diff БЕЗ заборонених шляхів → exit 0.
assert_exit "allowed-only diff → 0" 0 "$(printf 'apps/web/src/components/foo.tsx\ndocs/13_PROGRESS_LOG.md\nworkers/cad/flatcraft_cad/templates/l_bracket.py\n')"

# Тест 2: тестовий diff з drizzle-міграцією → exit 1.
assert_exit "migration → 1" 1 "$(printf 'apps/web/src/components/foo.tsx\npackages/db/src/migrations/0004_new.sql\n')"

# Тест 3: тестовий diff з .github/workflows → exit 1.
assert_exit ".github → 1" 1 "$(printf '.github/workflows/ci.yml\n')"

# Тест 4: тестовий diff з CLAUDE.md → exit 1.
assert_exit "CLAUDE.md → 1" 1 "$(printf 'CLAUDE.md\n')"

# Тест 5: тестовий diff з DXF-снапшотом → exit 1.
assert_exit "dxf snapshot → 1" 1 "$(printf 'workers/cad/tests/snapshots/l_bracket.dxf\n')"

# Тест 6: файл з ІМ'ЯМ, що лише ЧАСТКОВО збігається з забороненим (напр.
# CLAUDE.md.bak) — НЕ має фолсово спрацювати (якірні $ у regex).
assert_exit "CLAUDE.md.bak → 0 (no false positive)" 0 "$(printf 'CLAUDE.md.bak\ndocs/03_DECISIONS.md.draft\n')"

# Тест 7: порожній diff → exit 0.
assert_exit "empty diff → 0" 0 ""

if [[ "$fail" -eq 1 ]]; then
  echo "FAIL"
  exit 1
fi
echo "Усі тести пройдено."
