#!/usr/bin/env bash
# log-permission-request.sh — лічильник натискань yurii: хук на подію
# `PermissionRequest` Claude Code.
#
# ЧОМУ САМЕ ЦЯ ПОДІЯ. Документація (code.claude.com/docs/en/hooks, звірено
# 2026-09-23): «PermissionRequest fires when a tool call needs a permission
# decision. It doesn't fire for calls already allowed by permission rules or
# already denied by permission rules». Тобто рівно один рядок на кожен діалог,
# який бачить yurii, — і жодного на виклики, пропущені профілем.
#
# ЧОМУ МОВЧКИ І ЗАВЖДИ 0. «If your hook exits 0 with no JSON output, the
# permission dialog shows normally.» Будь-який вивід у stdout Claude Code міг би
# прочитати як рішення allow/deny — тоді лічильник вирішував би замість yurii.
# Тому весь запис загорнуто в `>/dev/null 2>&1`, а код виходу — завжди 0.
#
# ЧОМУ КОПІЯ ПОЗА РЕПО. Хук виконується без жодного кліку. Якби він запускав
# цей файл прямо з репозиторію, оркестратор, відредагувавши його, отримав би
# автоматичне виконання будь-чого в обхід заборон профілю. Тому інсталятор кладе
# копію в ~/.flatcraft/hooks/, профіль забороняє її правити, а --check звіряє її
# з версією в git (install-orchestrator-profile.sh).
#
# Що пишеться: `<місцевий час з поясом>\t<інструмент>\t<перші два слова команди>`.
# Для Bash — два слова, щоб бачити, що варто додати в профіль («git push»,
# «gh pr»). Значення після «=» і облікові дані в URL маскуються; інше — не пишеться.
#
# Використання:
#   (як хук)  stdin — JSON події PermissionRequest
#   log-permission-request.sh --count [РРРР-ММ-ДД]   # скільки діалогів за день
set -uo pipefail

LOG="${FLATCRAFT_CLICKS_LOG:-$HOME/.flatcraft-clicks.log}"

if [[ "${1:-}" == --count ]]; then
  d="${2:-$(date +%Y-%m-%d)}"
  # Лише дата: аргумент іде в grep, і будь-що інше перетворило б підрахунок на
  # читання довільних файлів.
  if [[ ! "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "відмова: дата має бути РРРР-ММ-ДД" >&2
    exit 2
  fi
  if [[ -f "$LOG" ]]; then
    grep -c "^$d" "$LOG" || true
  else
    echo 0
  fi
  exit 0
fi

{
  umask 077
  input="$(cat)"
  tool="$(jq -r '.tool_name // empty' <<<"$input")"
  tool="$(printf '%s' "$tool" | tr -cd 'A-Za-z0-9._:-' | cut -c1-40)"
  what="-"
  if [[ "$tool" == Bash ]]; then
    what="$(jq -r '.tool_input.command // empty' <<<"$input" |
      tr '\n\t' '  ' |
      awk '{
        out = ""
        for (i = 1; i <= 2 && i <= NF; i++) {
          w = $i
          sub(/:\/\/[^@\/]*@/, "://", w)   # облікові дані в URL
          sub(/=.*/, "=_", w)               # значення змінної чи параметра
          out = out (i > 1 ? " " : "") w
        }
        print out
      }' |
      tr -cd 'A-Za-z0-9._/:@=_ -' | cut -c1-40)"
    [[ -n "$what" ]] || what="-"
  fi
  printf '%s\t%s\t%s\n' "$(date +%Y-%m-%dT%H:%M:%S%z)" "${tool:-?}" "$what" >>"$LOG"
} >/dev/null 2>&1
exit 0
