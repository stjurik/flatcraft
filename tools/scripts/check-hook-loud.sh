#!/usr/bin/env bash
# check-hook-loud.sh — перетворює тихий no-op pre-commit на гучну відмову.
#
# ЩО ЛІКУЄ. Хук, який генерує lefthook, шукає бінарник по черзі (LEFTHOOK_BIN,
# PATH, node_modules кореня репо, пакетні менеджери) і, не знайшовши, друкує
# «Can't find lefthook in PATH» — та завершується з кодом 0. Коміт проходить.
# Виміряно двічі: у контейнері агента (вимір №7) і у worktree на T470 (коміт
# PR #116). Тобто ESLint, tsc, prettier і ruff локально не працюють, а
# виглядає це як робочий захист — той самий клас, що «код + тест, 0 викликів у
# пайплайні» з інспекції §A.
#
# ЩО РОБИТЬ. Перевіряє, що хук справді дійде до lefthook, і ЗАПУСКАЄ знайдений
# бінарник (`lefthook version`): файл, що лежить, але не виконується, — теж
# no-op. Будь-яка відмова — ненульовий код і рядок, як полагодити.
#
# ЧОГО НЕ РОБИТЬ. Не доводить, що хук блокує поганий коміт — лише що він не
# порожній. `LEFTHOOK=0` ловиться, бо згенерований хук перевіряє саме `= "0"`.
# Непрямі шляхи хука (`pnpm lefthook`, `uv run lefthook`, go, bundle…) свідомо
# НЕ зараховуються: у цьому репо lefthook ставиться через pnpm у
# node_modules, і якщо його там немає, покладатись на запасний шлях — це саме
# та тиша, яку скрипт прибирає.
#
# Використання: tools/scripts/check-hook-loud.sh   (з будь-якої теки репо/worktree)
# Коди: 0 — хук дійде до lefthook; 1 — ні (причина в stderr).
set -uo pipefail

die() {
  echo "✗ check-hook-loud: $1" >&2
  echo "  Як полагодити: $2" >&2
  exit 1
}

top="$(git rev-parse --show-toplevel 2>/dev/null)" ||
  die "не git-репозиторій" "запускай з теки клону або worktree"
hook="$(git rev-parse --path-format=absolute --git-path hooks/pre-commit 2>/dev/null)"

[[ -x "$hook" ]] ||
  die "pre-commit не встановлено ($hook) — коміти не перевіряються взагалі" \
    "pnpm install у $top (lefthook install виконується в prepare)"

# Хук не від lefthook у цьому репо означає, що його хтось підмінив: `exit 0` у
# pre-commit — той самий декоративний захист, від якого цей скрипт і існує.
# Раніше тут було «OK, не застосовно» — незалежне рев'ю №2 показало, що так
# проходить хук, який не робить нічого.
grep -q lefthook "$hook" ||
  die "pre-commit ($hook) не від lefthook — перевірки lefthook.yml не запускаються" \
    "pnpm install у $top (lefthook install перепише хук)"

[[ "${LEFTHOOK:-}" == 0 ]] &&
  die "LEFTHOOK=0 у середовищі — хук вийде з кодом 0, нічого не перевіривши" \
    "прибери LEFTHOOK=0 із середовища"

os="$(uname | tr '[:upper:]' '[:lower:]')"
arch="$(uname -m | sed 's/aarch64/arm64/;s/x86_64/x64/')"
bin=""
if [[ -n "${LEFTHOOK_BIN:-}" ]]; then
  bin="$LEFTHOOK_BIN"
elif command -v lefthook >/dev/null 2>&1; then
  bin="$(command -v lefthook)"
else
  # Корінь worktree, а не поточна тека: хук шукає саме від --show-toplevel.
  for cand in \
    "$top/node_modules/lefthook-$os-$arch/bin/lefthook" \
    "$top/node_modules/@evilmartians/lefthook/bin/lefthook-$os-$arch/lefthook" \
    "$top/node_modules/@evilmartians/lefthook-installer/bin/lefthook" \
    "$top/node_modules/lefthook/bin/index.js"; do
    [[ -f "$cand" ]] && {
      bin="$cand"
      break
    }
  done
fi

[[ -n "$bin" ]] ||
  die "lefthook не знайдено ні в PATH, ні в $top/node_modules — хук надрукує «Can't find lefthook in PATH» і пропустить коміт" \
    "pnpm install у $top, або PATH=<клон>/node_modules/.bin:\$PATH"

"$bin" version >/dev/null 2>&1 ||
  die "lefthook знайдено ($bin), але він не запускається" \
    "перевстанови залежності: pnpm install --force у $top"

echo "OK: pre-commit → $bin"
