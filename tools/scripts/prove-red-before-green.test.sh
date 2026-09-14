#!/usr/bin/env bash
# prove-red-before-green.test.sh — прогін доказу red-before-green на СПРАВЖНЬОМУ
# git-репозиторії-фікстурі (а не на моках): кожен сценарій створює базовий коміт,
# гілку з фіксом і тестом, і перевіряє вердикт скрипта.
#
# Фейковий раннер тестів навмисно дивиться, чи є маркер фікса у вихідному файлі.
# Це робить тест доказовим і для головної механіки скрипта — відкату робочого
# дерева до бази: якщо відкат не спрацює, маркер лишиться, раннер поверне 0,
# і сценарій «red» впаде.
#
# Запуск: tools/scripts/prove-red-before-green.test.sh
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/prove-red-before-green.sh"
fail=0

# Раннер, що імітує тест «фікс присутній?»: 0 (green) якщо маркер є, 1 (red) якщо нема.
RUNNER_MARKER='bash -c '\''grep -q FIXED src/app.js && exit 0 || exit 1'\'' _'
# Раннер, що завжди зелений — імітує тест, який нічого не ловить.
RUNNER_ALWAYS_GREEN='bash -c '\''exit 0'\'' _'

make_fixture() {
  local dir; dir="$(mktemp -d)"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email t@t.t
  git -C "$dir" config user.name t
  mkdir -p "$dir/src"
  printf '{"name":"fixture-pkg"}\n' >"$dir/package.json"
  printf 'export const app = "broken";\n' >"$dir/src/app.js"
  git -C "$dir" add -A
  git -C "$dir" commit -qm base
  echo "$dir"
}

# expect_msg — обов'язковий: інакше сценарій може «пройти» з правильним кодом виходу,
# але з зовсім іншої причини (напр. жоден тест не запустився). Саме так тест 3
# фолсово проходив, поки workspace_of не бачив кореневий package.json.
# ЧОМУ ТУТ ЗАДАЄТЬСЯ GITHUB_STEP_SUMMARY. `summary()` у скрипті пише підсумок у
# $GITHUB_STEP_SUMMARY, коли змінна є (CI), і в stdout, коли її немає (локально).
# Поки набір її не задавав, він перевіряв ЛИШЕ локальний шлях: зеленів на машині
# й червонів у CI, бо очікуваний рядок ішов у файл, а не в stdout (виявлено на
# PR #108 — перший прогін ci.yml на цій гілці). Задаємо власний тимчасовий файл і
# звіряємо stdout РАЗОМ із ним: один набір покриває обидві поведінки й не залежить
# від того, де його запустили.
run_case() {
  local name="$1" expected="$2" runner="$3" files="$4" dir="$5" expect_msg="$6"
  local actual=0 out summary
  summary="$(mktemp)"
  out="$(cd "$dir" && printf '%s\n' "$files" \
    | GITHUB_STEP_SUMMARY="$summary" PRVG_BASE_REF=main PRVG_TS_CMD="$runner" PRVG_PY_CMD="$runner" \
      bash "$SCRIPT" 2>&1)" || actual=$?
  out="$(printf '%s\n%s' "$out" "$(cat "$summary")")"
  rm -f "$summary"
  if [[ "$actual" -eq "$expected" ]] && printf '%s' "$out" | grep -qF "$expect_msg"; then
    echo "✓ $name"
  else
    echo "✗ $name — очікував exit $expected + «$expect_msg», отримав exit $actual"
    printf '%s\n' "$out" | sed 's/^/    /'
    fail=1
  fi
  rm -rf "$dir"
}

# ── Тест 1: у diff немає жодного тесту → фікс без тесту не зараховується (exit 1).
d="$(make_fixture)"
git -C "$d" checkout -qb fix
printf 'export const app = "FIXED";\n' >"$d/src/app.js"
git -C "$d" commit -qam fix
run_case "немає тесту → 1" 1 "$RUNNER_MARKER" "src/app.js" "$d" "Регресійного тесту немає"

# ── Тест 2: тест червоний на базі (бо фікс відкочено) → доказ є (exit 0).
d="$(make_fixture)"
git -C "$d" checkout -qb fix
printf 'export const app = "FIXED";\n' >"$d/src/app.js"
printf '// regression\n' >"$d/src/app.test.ts"
git -C "$d" add -A && git -C "$d" commit -qm fix
run_case "червоний на базі → 0" 0 "$RUNNER_MARKER" "$(printf 'src/app.js\nsrc/app.test.ts')" "$d" "Red-before-green доведено"

# ── Тест 3: тест зелений на базі → нічого не ловить, як регресійний порожній (exit 1).
d="$(make_fixture)"
git -C "$d" checkout -qb fix
printf 'export const app = "FIXED";\n' >"$d/src/app.js"
printf '// empty regression\n' >"$d/src/app.test.ts"
git -C "$d" add -A && git -C "$d" commit -qm fix
run_case "зелений на базі → 1" 1 "$RUNNER_ALWAYS_GREEN" "$(printf 'src/app.js\nsrc/app.test.ts')" "$d" "не ловить баг"

# ── Тест 4: лише e2e-специфікація → машинно не доводимо, але не блокуємо (exit 0).
d="$(make_fixture)"
git -C "$d" checkout -qb fix
mkdir -p "$d/apps/web/tests/e2e"
printf '// e2e\n' >"$d/apps/web/tests/e2e/thing.spec.ts"
git -C "$d" add -A && git -C "$d" commit -qm e2e
run_case "лише e2e → 0 (з попередженням)" 0 "$RUNNER_MARKER" "apps/web/tests/e2e/thing.spec.ts" "$d" "машинно НЕ доведено"

# ── Тест 5: лише інтеграційний тест (потребує Postgres) → те саме (exit 0).
d="$(make_fixture)"
git -C "$d" checkout -qb fix
printf '// int\n' >"$d/src/api.int.test.ts"
git -C "$d" add -A && git -C "$d" commit -qm int
run_case "лише int → 0 (з попередженням)" 0 "$RUNNER_MARKER" "src/api.int.test.ts" "$d" "машинно НЕ доведено"

# ── Тест 6: робоче дерево відновлене після прогону (trap restore спрацював).
d="$(make_fixture)"
git -C "$d" checkout -qb fix
printf 'export const app = "FIXED";\n' >"$d/src/app.js"
printf '// regression\n' >"$d/src/app.test.ts"
git -C "$d" add -A && git -C "$d" commit -qm fix
before="$(git -C "$d" rev-parse HEAD)"
(cd "$d" && printf 'src/app.js\nsrc/app.test.ts\n' \
  | PRVG_BASE_REF=main PRVG_TS_CMD="$RUNNER_MARKER" bash "$SCRIPT" >/dev/null 2>&1) || true
after="$(git -C "$d" rev-parse HEAD)"
dirty="$(git -C "$d" status --porcelain)"
marker="$(grep -c FIXED "$d/src/app.js" || true)"
if [[ "$before" == "$after" && -z "$dirty" && "$marker" == "1" ]]; then
  echo "✓ робоче дерево відновлене після прогону"
else
  echo "✗ робоче дерево НЕ відновлене — HEAD $before→$after, dirty='$dirty', marker=$marker"
  fail=1
fi
rm -rf "$d"

# ── Тест 7: шлях до тесту передається ВІДНОСНО теки workspace, не кореня репо.
# `pnpm --filter X exec` виконує команду в теці X — root-relative шлях там не існує.
# Раннер червоний (exit 1) ЛИШЕ якщо отримав правильний, package-relative шлях.
d="$(make_fixture)"
mkdir -p "$d/apps/api/src"
printf '{"name":"@fx/api"}\n' >"$d/apps/api/package.json"
git -C "$d" add -A && git -C "$d" commit -qm workspace
git -C "$d" checkout -qb fix
printf 'export const app = "FIXED";\n' >"$d/src/app.js"
printf '// regression\n' >"$d/apps/api/src/thing.test.ts"
git -C "$d" add -A && git -C "$d" commit -qm fix
RUNNER_PATH_ASSERT='bash -c '"'"'[ "$1" = "src/thing.test.ts" ] && exit 1 || exit 0'"'"' _ {file}'
run_case "шлях відносний до workspace → 0" 0 "$RUNNER_PATH_ASSERT" \
  "$(printf 'src/app.js\napps/api/src/thing.test.ts')" "$d" "Red-before-green доведено"

# ── Тест 8: гілка без змін (агент заблокувався) → доводити нічого, не блокуємо.
d="$(make_fixture)"
git -C "$d" checkout -qb fix
run_case "порожній diff → 0 (не застосовно)" 0 "$RUNNER_MARKER" "" "$d" "доводити нічого"

# ── Тест 9: фікс лише в документації → тест не застосовний, не блокуємо.
d="$(make_fixture)"
git -C "$d" checkout -qb fix
printf '# doc\n' >"$d/README.md"
mkdir -p "$d/docs" && printf 'текст\n' >"$d/docs/13_PROGRESS_LOG.md"
git -C "$d" add -A && git -C "$d" commit -qm docs
run_case "лише документація → 0 (не застосовно)" 0 "$RUNNER_MARKER" \
  "$(printf 'README.md\ndocs/13_PROGRESS_LOG.md')" "$d" "лише документацію"

# ── Тест 10: код змінено, тесту немає → провал (виняток для доків не протікає).
d="$(make_fixture)"
git -C "$d" checkout -qb fix
printf '# doc\n' >"$d/README.md"
printf 'export const app = "FIXED";\n' >"$d/src/app.js"
git -C "$d" add -A && git -C "$d" commit -qm mixed
run_case "код без тесту (поряд з доками) → 1" 1 "$RUNNER_MARKER" \
  "$(printf 'README.md\nsrc/app.js')" "$d" "Регресійного тесту немає"

if [[ "$fail" -eq 1 ]]; then
  echo "FAIL"
  exit 1
fi
echo "Усі тести пройдено."
