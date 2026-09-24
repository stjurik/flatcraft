#!/usr/bin/env bash
# log-permission-request.test.sh — доказ, що лічильник натискань рахує і нічим
# не заважає діалогу дозволу.
#
# Що СПРАВЖНЄ: сам скрипт і вхід у форматі події `PermissionRequest`
# (code.claude.com/docs/en/hooks: tool_name, tool_input, …).
# Що ПІДМІНЕНО: журнал — тимчасовий файл через FLATCRAFT_CLICKS_LOG.
#
# Головний інваріант: скрипт НІЧОГО не друкує в stdout і завжди виходить з 0.
# Документація: «If your hook exits 0 with no JSON output, the permission dialog
# shows normally». Будь-який вивід — ризик, що Claude Code прочитає його як
# рішення allow/deny замість yurii.
#
# Запуск: tools/scripts/log-permission-request.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/log-permission-request.sh"
fail=0
ok() { echo "✓ $1"; }
bad() {
  echo "✗ $1"
  fail=1
}

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export FLATCRAFT_CLICKS_LOG="$T/clicks.log"

hook() { # hook <json> → stdout у $T/out, код у $rc
  printf '%s' "$1" | bash "$SCRIPT" >"$T/out" 2>"$T/err"
  rc=$?
}
silent() { [[ $rc == 0 && ! -s "$T/out" ]]; }

# ─── 1. Звичайний запит Bash → один рядок, мовчки, код 0 ───────────────────
hook '{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"git push -u origin feat/x"}}'
if silent && [[ "$(wc -l <"$FLATCRAFT_CLICKS_LOG")" == 1 ]] && grep -qP '\tBash\tgit push$' "$FLATCRAFT_CLICKS_LOG"; then
  ok "запит Bash → один рядок «Bash / git push», stdout порожній, код 0"
else
  bad "запит Bash записано неправильно (rc=$rc, stdout='$(cat "$T/out")'): $(cat "$FLATCRAFT_CLICKS_LOG")"
fi
if grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{4}	' "$FLATCRAFT_CLICKS_LOG"; then
  ok "рядок починається з місцевого часу з поясом — підрахунок за днем yurii"
else
  bad "формат часу неправильний: $(head -1 "$FLATCRAFT_CLICKS_LOG")"
fi

# ─── 2. Секрети не потрапляють у журнал ────────────────────────────────────
: >"$FLATCRAFT_CLICKS_LOG"
hook '{"tool_name":"Bash","tool_input":{"command":"GH_TOKEN=ghp_SECRET1 gh pr list"}}'
hook '{"tool_name":"Bash","tool_input":{"command":"curl https://user:SECRET2@example.com/x -H \"Authorization: Bearer SECRET3\""}}'
hook '{"tool_name":"Bash","tool_input":{"command":"DATABASE_URL=\"postgresql://u:SECRET4@localhost/db\" pnpm test"}}'
if ! grep -q 'SECRET' "$FLATCRAFT_CLICKS_LOG" && [[ "$(wc -l <"$FLATCRAFT_CLICKS_LOG")" == 3 ]]; then
  ok "значення після «=», облікові дані в URL і все після двох слів у журнал не йдуть"
else
  bad "секрет потрапив у журнал: $(cat "$FLATCRAFT_CLICKS_LOG")"
fi

# ─── 3. Вміст команди не ламає формат журналу ──────────────────────────────
: >"$FLATCRAFT_CLICKS_LOG"
hook '{"tool_name":"Bash","tool_input":{"command":"echo $(rm -rf x)\nfake\tline"}}'
if silent && [[ "$(wc -l <"$FLATCRAFT_CLICKS_LOG")" == 1 ]] && ! grep -qE '[$()`;|&]' "$FLATCRAFT_CLICKS_LOG"; then
  ok "перенос рядка, табуляція і \$( ) у команді — рівно один чистий рядок"
else
  bad "вміст команди зламав журнал: $(cat -A "$FLATCRAFT_CLICKS_LOG")"
fi

# ─── 4. Не Bash — рахується без подробиць ──────────────────────────────────
: >"$FLATCRAFT_CLICKS_LOG"
hook '{"tool_name":"Edit","tool_input":{"file_path":"/home/someone/secret-notes.md"}}'
if silent && grep -qP '\tEdit\t-$' "$FLATCRAFT_CLICKS_LOG" && ! grep -q 'secret-notes' "$FLATCRAFT_CLICKS_LOG"; then
  ok "запит Edit рахується без шляху до файла"
else
  bad "запит Edit записано неправильно: $(cat "$FLATCRAFT_CLICKS_LOG")"
fi

# ─── 5. Зламаний або порожній вхід — однаково рахується, мовчки ────────────
: >"$FLATCRAFT_CLICKS_LOG"
hook 'це не json {'
s1=$rc
hook ''
if [[ $s1 == 0 ]] && silent && [[ "$(grep -cP '\t\?\t-$' "$FLATCRAFT_CLICKS_LOG")" == 2 ]]; then
  ok "зламаний і порожній вхід → рядки «?», діалог показано, отже його рахуємо"
else
  bad "зламаний вхід оброблено неправильно (rc=$rc): $(cat "$FLATCRAFT_CLICKS_LOG")"
fi

# ─── 6. Журнал недоступний на запис — однаково мовчки і код 0 ──────────────
FLATCRAFT_CLICKS_LOG="$T/немає-такої-теки/clicks.log" hook '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
if silent; then
  ok "журнал недоступний → код 0, stdout порожній: діалог не страждає"
else
  bad "недоступний журнал зламав хук (rc=$rc, stdout='$(cat "$T/out")')"
fi

# ─── 7. Підрахунок за день ──────────────────────────────────────────────────
printf '%s\n' \
  $'2026-09-22T23:59:00+0300\tBash\tgit fetch' \
  $'2026-09-23T09:00:00+0300\tBash\tgit push' \
  $'2026-09-23T10:00:00+0300\tEdit\t-' \
  $'2026-09-23T11:00:00+0300\t?\t-' >"$FLATCRAFT_CLICKS_LOG"
c23="$(bash "$SCRIPT" --count 2026-09-23)"
c22="$(bash "$SCRIPT" --count 2026-09-22)"
c24="$(bash "$SCRIPT" --count 2026-09-24)"
cn="$(FLATCRAFT_CLICKS_LOG="$T/нема.log" bash "$SCRIPT" --count 2026-09-23)"
if [[ "$c23/$c22/$c24/$cn" == "3/1/0/0" ]]; then
  ok "--count: 3 за 23-тє, 1 за 22-ге, 0 за день без записів, 0 без журналу"
else
  bad "--count рахує неправильно: 23→$c23 22→$c22 24→$c24 без журналу→$cn"
fi

# ─── 8. --count приймає лише дату — нічого більше ──────────────────────────
for arg in '2026-09-23;id' '../../etc/passwd' '2026-09-23 -f /etc/passwd' '.*'; do
  out="$(bash "$SCRIPT" --count "$arg" 2>/dev/null)"
  r=$?
  if [[ $r == 2 && -z "$out" ]]; then
    ok "--count відхиляє не-дату: $arg"
  else
    bad "--count прийняв не-дату (rc=$r, out='$out'): $arg"
  fi
done

if ((fail)); then
  echo "Провалено."
  exit 1
fi
echo "Усі тести пройдено."
