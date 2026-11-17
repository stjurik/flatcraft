#!/usr/bin/env bash
# a8-ctl.sh — forced-command ключа оркестратора на A8: лише транспорт до a8-queue.
#
# ЧОМУ. Оркестратор ставить, повертає й зупиняє задачі A8 сам (#231, #262), але
# оболонки на A8 не отримує: ключ у ~/.ssh/authorized_keys агента прописано з
# `restrict,command="/usr/local/bin/a8-ctl"`, і sshd виконує ЛИШЕ цей скрипт —
# що б клієнт не попросив. Запитана команда приходить у SSH_ORIGINAL_COMMAND.
#
# ЛОГІКИ ТУТ НЕМАЄ (рішення yurii 2026-10-20). Усі дієслова, перевірки й журнал —
# в a8-queue (tools/scripts/a8-queue.sh), який так само викликається локально на
# A8. Тут — лише три кроки транспорту:
#   1. відмова на порожню команду (інтерактивний вхід), перенос рядка і будь-який
#      символ поза [A-Za-z0-9._ -] — тож `;`, `|`, `$(…)`, лапки, `>` і glob не
#      можуть склеїти другу команду;
#   2. поділ на слова за пробілами, без інтерпретації оболонкою;
#   3. перше слово — одне з дієслів a8-queue; далі `exec` масиву аргументів з
#      A8_CTL_VIA=ssh. Оболонка в цьому шляху не бере участі взагалі.
# Відмову теж записано: a8-queue `_denied` додає рядок у ctl.log. Це дієслово
# недосяжне через ключ — п.3 його не пропускає.
#
# Задачу для enqueue sshd передає через stdin — він лишається в a8-queue.
# A8_QUEUE_BIN — точка підміни лише для тесту: з `restrict` sshd змінних
# середовища від клієнта не приймає.
set -uo pipefail

QUEUE="${A8_QUEUE_BIN:-/usr/local/bin/a8-queue}"

deny() {
  echo "a8-ctl: ВІДХИЛЕНО — $1" >&2
  A8_CTL_VIA=ssh "$QUEUE" _denied "$1" </dev/null >/dev/null 2>&1
  exit 126
}

cmd="${SSH_ORIGINAL_COMMAND:-}"
[[ -n "${cmd//[[:space:]]/}" ]] || deny "порожня команда (інтерактивний вхід заборонено)"
[[ "$cmd" == *$'\n'* || "$cmd" == *$'\r'* ]] && deny "перенос рядка"
[[ "$cmd" =~ ^[A-Za-z0-9._\ -]+$ ]] || deny "символ поза [A-Za-z0-9._ -]"

read -r -a argv <<<"$cmd"
case "${argv[0]}" in
  status | enqueue | requeue | pause | resume) ;;
  *) deny "невідоме дієслово '${argv[0]}' (status | enqueue | requeue | pause | resume)" ;;
esac

export A8_CTL_VIA=ssh
exec "$QUEUE" "${argv[@]}"
