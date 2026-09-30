#!/usr/bin/env bash
# check-deny-parity.test.sh — прогін перевірки розходження deny-списків
# на синтетичних парах файлів + на СПРАВЖНІХ файлах репозиторію.
#
# Запуск: tools/scripts/check-deny-parity.test.sh
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-deny-parity.sh"
REPO_ROOT="$(git rev-parse --show-toplevel)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

# Синтетичний workflow з блоком `settings: |` на тому ж відступі, що в ai-fix.yml.
make_workflow() {
  local out="$1"; shift
  {
    printf 'jobs:\n  fix:\n    steps:\n      - uses: x\n        with:\n          settings: |\n'
    printf '            {\n              "permissions": {\n                "deny": [\n'
    local first=1 rule
    for rule in "$@"; do
      [[ $first -eq 0 ]] && printf ',\n'
      printf '                  "%s"' "$rule"
      first=0
    done
    printf '\n                ]\n              }\n            }\n'
    printf '          prompt: |\n            текст після блоку\n'
  } >"$out"
}

make_settings() {
  local out="$1"; shift
  python3 -c '
import json, sys
json.dump({"permissions": {"deny": sys.argv[2:]}}, open(sys.argv[1], "w"))
' "$out" "$@"
}

assert_case() {
  local name="$1" expected="$2" wf="$3" st="$4"
  local actual=0 out
  out="$("$SCRIPT" "$wf" "$st" 2>&1)" || actual=$?
  if [[ "$actual" -eq "$expected" ]]; then
    echo "✓ $name"
  else
    echo "✗ $name — очікував exit $expected, отримав $actual"
    printf '%s\n' "$out" | sed 's/^/    /'
    fail=1
  fi
}

# Тест 1: списки збігаються → 0.
make_workflow "$TMP/a.yml" "Edit(infra/**)" "Bash(docker:*)"
make_settings "$TMP/a.json" "Edit(infra/**)" "Bash(docker:*)"
assert_case "однакові списки → 0" 0 "$TMP/a.yml" "$TMP/a.json"

# Тест 2: трекований файл СУВОРІШИЙ (надмножина) → 0, це дозволено.
make_workflow "$TMP/b.yml" "Edit(infra/**)"
make_settings "$TMP/b.json" "Edit(infra/**)" "Edit(packages/cad-engine/data/bend-machine-esi.yaml)"
assert_case "трекований суворіший → 0" 0 "$TMP/b.yml" "$TMP/b.json"

# Тест 3: правило є в ai-fix.yml, але зникло з трекованого → 1 (головний інваріант).
make_workflow "$TMP/c.yml" "Edit(infra/**)" "Edit(CLAUDE.md)"
make_settings "$TMP/c.json" "Edit(infra/**)"
assert_case "правило загубилось → 1" 1 "$TMP/c.yml" "$TMP/c.json"

# Тест 4: у workflow взагалі немає блоку settings → 1 (захист зник непомітно).
printf 'jobs:\n  fix:\n    steps:\n      - run: echo hi\n' >"$TMP/d.yml"
make_settings "$TMP/d.json" "Edit(infra/**)"
assert_case "немає блоку settings → 1" 1 "$TMP/d.yml" "$TMP/d.json"

# Тест 5: СПРАВЖНІ файли репозиторію — інваріант тримається просто зараз.
assert_case "реальні файли репо → 0" 0 \
  "$REPO_ROOT/.github/workflows/ai-fix.yml" \
  "$REPO_ROOT/.claude/settings.autonomous.json"

if [[ "$fail" -eq 1 ]]; then
  echo "FAIL"
  exit 1
fi
echo "Усі тести пройдено."
