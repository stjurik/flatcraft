#!/usr/bin/env bash
# a8-report.sh — один знімок стану A8 у файл, щоб не збирати його руками.
#
# ЧОМУ ЦЕЙ СКРИПТ ІСНУЄ. Вечірня і ранкова перевірка A8 — це шість-вісім
# ssh-команд, вивід яких треба скопіювати з термінала й кудись подіти. Зроблено
# двічі — значить має стати скриптом (CLAUDE.md §0 п.5). Заразом зникає клас
# помилок «скопіював не весь вивід» і «забув одну команду».
#
# ЩО ЦЕЙ СКРИПТ НЕ РОБИТЬ: він нічого не вмикає, не застосовує роль і не
# чіпає чергу. Єдиний запис, на який він здатен, — тимчасовий kill switch у
# режимі --killswitch-test, і той знімається `trap`'ом навіть при падінні.
#
# СЕКРЕТИ. У звіт не потрапляє ВМІСТ жодного креденшала — лише наявність,
# права і власник. Файл звіту призначений для пересилання, тож це не
# педантизм: один `cat` токена перетворив би звіт на витік.
#
# Використання:
#   tools/scripts/a8-report.sh                      # знімок → ~/a8-reports/…
#   tools/scripts/a8-report.sh -o шлях.txt          # знімок у вказаний файл
#   tools/scripts/a8-report.sh --killswitch-test    # + довести, що стоп-кран діє
#   A8_HOST=інший-хост tools/scripts/a8-report.sh   # інша машина
set -uo pipefail

HOST="${A8_HOST:-a8-ts}"
SINCE="${A8_REPORT_SINCE:--12h}"
KILLSWITCH=0
OUT=""

while (($# > 0)); do
  case "$1" in
    -o | --out)
      OUT="${2:?потрібен шлях після $1}"
      shift 2
      ;;
    --killswitch-test)
      KILLSWITCH=1
      shift
      ;;
    -h | --help)
      sed -n '2,/^set -/p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      echo "a8-report: невідомий аргумент '$1'" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$OUT" ]]; then
  mkdir -p "$HOME/a8-reports"
  OUT="$HOME/a8-reports/a8-$(date -u +%Y%m%d-%H%M%SZ).txt"
fi

# `cd /tmp` перед кожною віддаленою командою — не прикраса. Вхід на A8
# відбувається в домашню теку yurii, а `sudo -u agent` лишає той самий cwd,
# якого agent читати не може: `find` тоді друкує «Failed to restore initial
# working directory», і це вже одного разу прочиталось як «тік завис».
remote() { ssh "$HOST" "cd /tmp && $*" 2>&1; }

section() {
  {
    echo
    echo "── $1 ──────────────────────────────────────────"
  } >>"$OUT"
}

emit() { printf '%s\n' "$*" >>"$OUT"; }

: >"$OUT"
emit "# Звіт про стан A8"
emit "# зібрано: $(date -u +%Y-%m-%dT%H:%M:%SZ) (UTC), хост: $HOST"
emit "# джерело: tools/scripts/a8-report.sh"

section "Час на самій машині"
emit "$(remote 'date -u +%Y-%m-%dT%H:%M:%SZ; uptime')"

section "Залізо і памʼять"
# Доданий після 2026-09-21: yurii встановив планку памʼяті, а звіт не мав
# жодного рядка, яким це можна підтвердити. Звіт, що не бачить зміни заліза,
# не годиться для машини, яку обслуговують руками.
emit "$(remote 'free -h; echo; nproc --all | sed "s/^/ядер: /"')"
emit ""
emit "помилки памʼяті в dmesg (порожньо = добре):"
emit "$(remote 'sudo dmesg -T 2>/dev/null | grep -iE "edac|machine check|memory error|Corrected error" | tail -5 || true')"

section "Таймери"
emit "$(remote 'systemctl list-timers a8-tick.timer a8-egress-refresh.timer --all --no-pager')"

section "Чи запускався тік (journalctl $SINCE)"
# Кількість запусків важить більше за їхній текст: при порожній черзі тік
# нічого не пише в runs.log, і ТІЛЬКИ цей розділ доводить, що таймер живий.
emit "$(remote "sudo journalctl -u a8-tick.service --since '$SINCE' --no-pager | tail -40")"
emit ""
emit "стартів a8-tick.service за період:"
emit "$(remote "sudo journalctl -u a8-tick.service --since '$SINCE' --no-pager | grep -c 'Starting\\|Started' || true")"

section "Журнал прогонів (runs.log, весь)"
emit "$(remote 'sudo -u agent cat /home/agent/agent-logs/runs.log 2>/dev/null || echo "(порожній або відсутній)"')"
emit ""
emit "ротовані файли:"
emit "$(remote 'sudo -u agent ls -la /home/agent/agent-logs/ | grep runs.log || true')"

section "Запобіжники"
emit "a8-guard check:"
emit "$(remote 'sudo -u agent /usr/local/bin/a8-guard check; echo "rc=$?"')"
emit ""
emit "kill switch (порожньо = немає, і це норма):"
emit "$(remote 'sudo -u agent ls -la /home/agent/STOP 2>/dev/null || echo "(немає)"')"
emit ""
emit "хвіст last-results:"
emit "$(remote 'sudo -u agent tail -6 /home/agent/agent-logs/last-results 2>/dev/null || echo "(немає)"')"

section "Черга"
emit "$(remote 'sudo -u agent ls -la /home/agent/agent-queue/ /home/agent/agent-queue/running/ /home/agent/agent-queue/done/ /home/agent/agent-queue/failed/ /home/agent/agent-queue/rejected/ 2>&1')"

section "Worktree і диск"
# Worktree після успішної задачі НЕ прибираються — кожен несе node_modules і
# .venv. Цей розділ існує, щоб витік було видно числом, а не здогадом.
emit "$(remote 'sudo -u agent du -sh /home/agent/hart-wt/* 2>/dev/null || echo "(жодного worktree)"')"
emit ""
emit "$(remote 'df -h /home | tail -1')"
emit ""
emit "гілки ai/*:"
emit "$(remote "sudo -u agent git -C /home/agent/hart branch --list 'ai/*'" )"

section "Egress"
emit "$(remote 'sudo a8-egress-rules status')"
emit ""
emit "адрес у наборі:"
emit "$(remote 'sudo ipset list a8_egress | sed -n "s/^Number of entries: //p"')"
emit ""
emit "drop-in для docker:"
emit "$(remote 'ls -la /etc/systemd/system/docker.service.d/ 2>/dev/null || echo "(теки немає)"')"

section "Креденшал на push — лише наявність, без вмісту"
emit "$(remote 'sudo grep A8_PUSH_CREDENTIAL_KIND /etc/a8/a8.env')"
emit "$(remote 'sudo -u agent stat -c "%n власник=%U права=%a розмір=%s" /home/agent/.ssh/id_push 2>/dev/null || echo "(ключа немає)"')"
emit "$(remote 'sudo -u agent stat -c "%n власник=%U права=%a" /home/agent/.ssh/known_hosts 2>/dev/null || echo "(known_hosts немає)"')"

section "Потрібне перезавантаження?"
emit "$(remote 'cat /var/run/reboot-required 2>/dev/null || echo "(ні)"')"

if ((KILLSWITCH)); then
  section "Перевірка стоп-крана (єдиний запис, який робить цей скрипт)"

  pre="$(remote 'test -e /home/agent/STOP && echo ON || echo OFF')"
  if [[ "$pre" != OFF ]]; then
    emit "ПРОПУЩЕНО: kill switch уже стоїть ($pre) — не чіпаю чужий стоп."
    emit "Зніміть його свідомо і повторіть, інакше перевірка нічого не доведе."
  else
    # Trap до першого запису: якщо скрипт помре посеред перевірки, черга
    # лишилася б на паузі всю ніч, і вранці порожній журнал прочитався б як
    # «таймер не працював». Знімаємо стоп у будь-якому разі.
    #
    # ЧОМУ ЛИШЕ EXIT, без окремих TERM/HUP. Виміряно 2026-09-21, не взято з
    # пам'яті: bash виконує EXIT-trap і коли гине від сигналу —
    #   SIGTERM → «EXIT-trap спрацював», rc=143
    #   SIGHUP  → «EXIT-trap спрацював», rc=129
    # Окремі trap'и на сигнали міняли б лише код виходу, тож їх тут немає.
    # Контроль: сценарій 6 у a8-report.test.sh падає, якщо trap прибрати
    # зовсім, — отже він міряє наявність прибирання, а не власну присутність.
    #
    # Чого EXIT НЕ покриває: SIGKILL і зникнення живлення. На цей випадок
    # команда зняття друкується у звіт одразу нижче — файл уже на диску,
    # навіть якщо процес не дожив до вердикту.
    cleanup_stop() {
      ssh "$HOST" "cd /tmp && sudo -u agent rm -f /home/agent/STOP" >/dev/null 2>&1 || true
    }
    trap cleanup_stop EXIT

    remote 'sudo -u agent touch /home/agent/STOP' >/dev/null
    emit "kill switch виставлено, запускаю тік…"
    emit "якщо нижче немає ВЕРДИКТУ — скрипт не дожив; зніміть стоп руками:"
    emit "  ssh $HOST \"cd /tmp && sudo -u agent rm /home/agent/STOP\""
    remote 'sudo -u agent /usr/local/bin/a8-tick' >/dev/null
    verdict="$(remote 'sudo -u agent tail -1 /home/agent/agent-logs/runs.log')"
    emit "останній запис журналу:"
    emit "$verdict"

    remote 'sudo -u agent rm -f /home/agent/STOP' >/dev/null
    trap - EXIT
    post="$(remote 'test -e /home/agent/STOP && echo ON || echo OFF')"

    emit ""
    if [[ "$verdict" == *kill_switch* && "$post" == OFF ]]; then
      emit "ВЕРДИКТ: стоп-кран діє (event kill_switch), і його знято — черга вільна."
    else
      emit "ВЕРДИКТ: НЕ ПІДТВЕРДЖЕНО. kill switch після перевірки: $post."
      emit "Якщо там ON — зніміть руками, інакше черга стоятиме:"
      emit "  ssh $HOST \"cd /tmp && sudo -u agent rm /home/agent/STOP\""
    fi
  fi
fi

echo "$OUT"
