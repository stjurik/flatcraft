#!/usr/bin/env bash
# a8-ro-shell.test.sh — доказ, що ssh-вхід a8-ro пропускає лише читання.
#
# Головне, що мусить доводити набір (промпт a8-daemon-and-guards §4): спроба
# запису відхиляється, і обхід через `;`, `&&`, `$(…)`, бектик і перенос рядка —
# теж. Кожна відмова звіряється і за кодом (126), і за текстом причини.
# Дозволені команди перевіряються в режимі DRYRUN (що саме буде виконано) і
# один раз — справжнім exec, щоб DRYRUN не ховав зламаний шлях виконання.
#
# Запуск: tools/scripts/a8-ro-shell.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${RO_SHELL_UNDER_TEST:-$HERE/a8-ro-shell.sh}"
fail=0
ok() { [[ -z "${QUIET:-}" ]] && echo "✓ $1"; return 0; }
bad() {
  echo "✗ $1"
  fail=1
}

deny() { # deny <назва> <команда> <фрагмент причини>
  local out rc=0
  out="$(SSH_ORIGINAL_COMMAND="$2" A8_RO_SHELL_DRYRUN=1 bash "$SCRIPT" 2>&1)" || rc=$?
  if [[ "$rc" == 126 && "$out" == *"ВІДХИЛЕНО"*"$3"* && "$out" != *EXEC:* ]]; then
    ok "відмова: $1"
  else
    bad "$1 — очікував 126 і '$3', отримав [$rc] '$out'"
  fi
}
allow() { # allow <команда> <очікуваний EXEC-рядок>
  local out rc=0
  out="$(SSH_ORIGINAL_COMMAND="$1" A8_RO_SHELL_DRYRUN=1 bash "$SCRIPT" 2>&1)" || rc=$?
  if [[ "$rc" == 0 && "$out" == "EXEC: $2" ]]; then
    ok "дозвіл: $1"
  else
    bad "дозвіл '$1' — очікував 'EXEC: $2', отримав [$rc] '$out'"
  fi
}

run_scenarios() {
  # ── Читання проходить, і виконується РІВНО те, що запитано ─────────────────
  allow "cat /etc/os-release" "cat /etc/os-release"
  allow "ls -la /home/agent" "ls -la /home/agent"
  allow "dpkg -l docker-ce" "dpkg -l docker-ce"
  allow "systemctl list-units --type=service" "systemctl list-units --type=service"
  allow "sudo -n docker ps -a" "sudo -n docker ps -a"
  allow "sudo -n iptables -L DOCKER-USER -n -v" "sudo -n iptables -L DOCKER-USER -n -v"
  allow "sudo -n -l" "sudo -n -l"
  allow "find /etc/a8 -maxdepth 1" "find /etc/a8 -maxdepth 1"

  # ── Запис — ні ─────────────────────────────────────────────────────────────
  deny "touch" "touch /tmp/x" "не в списку"
  deny "rm" "rm -rf /home/agent/hart" "не в списку"
  deny "apt" "apt install -y foo" "не в списку"
  deny "docker run" "docker run --rm alpine" "docker лише"
  deny "sudo docker run" "sudo -n docker run alpine" "docker лише"
  deny "systemctl restart" "systemctl restart docker" "systemctl лише"
  deny "iptables -A" "sudo -n iptables -A DOCKER-USER -j DROP" "не в списку читання"
  deny "iptables -L разом з -F" "sudo -n iptables -L -F" "не в списку читання"
  # Обходи списку заборонених (незалежне рев'ю №2): злиті й скорочені прапорці.
  deny "iptables -L -nZ (злитий -Z обнуляє лічильники)" "sudo -n iptables -L -nZ" "'-nZ' не в списку"
  deny "iptables -L --zer (скорочений --zero)" "sudo -n iptables -L --zer" "'--zer' не в списку"
  deny "iptables --modprobe= (виконання програми)" "sudo -n iptables -L --modprobe=/usr/bin/touch" "не в списку"
  deny "iptables без -L/-S" "sudo -n iptables -n -v" "лише -L або -S"
  deny "iptables з таблицею поза списком" "sudo -n iptables -t security -L" "таблиця"
  allow "sudo -n iptables -t nat -L -n --line-numbers" "sudo -n iptables -t nat -L -n --line-numbers"
  deny "systemctl -H (ssh з A8 назовні)" "systemctl status -H yurii@elsewhere docker" "віддаленою ціллю"
  deny "systemctl --host=" "systemctl status --host=x docker" "віддаленою ціллю"
  deny "find -fprint (запис файла)" "find / -maxdepth 0 -fprint /tmp/x" "find з дією"
  deny "find -execdir через +" "find /tmp -execdir ls +" "find з дією"
  deny "crontab -r" "sudo -n crontab -r -u agent" "crontab лише"
  deny "crontab -l -r" "crontab -l -r" "crontab лише"
  allow "sudo -n crontab -l -u agent" "sudo -n crontab -l -u agent"
  deny "ufw status з зайвим" "sudo -n ufw status verbose extra" "ufw лише"
  allow "sudo -n ufw status numbered" "sudo -n ufw status numbered"
  deny "dpkg -i" "dpkg -i foo.deb" "dpkg лише"
  deny "find -delete" "find /home/agent -delete" "find з дією"
  deny "find -exec" "find / -exec rm {} +" "метасимвол"
  deny "ufw allow" "ufw allow 22" "ufw лише"
  deny "sudo cat (читання токенів агента)" "sudo -n cat /home/agent/.claude-oauth-token" "sudo перед 'cat'"
  deny "sudo без -n" "sudo ls /root" "sudo лише як"
  deny "порожня команда" "" "порожня"

  # ── Обхід склеюванням — ні ─────────────────────────────────────────────────
  deny "обхід через ;" "cat /etc/hostname; rm -rf /tmp/x" "метасимвол"
  deny "обхід через &&" "ls && touch /tmp/x" "метасимвол"
  deny "обхід через ||" "ls /nope || touch /tmp/x" "метасимвол"
  deny "обхід через |" "cat /etc/passwd | tee /tmp/x" "метасимвол"
  deny "обхід через \$(…)" 'cat $(touch /tmp/x)' "метасимвол"
  deny "обхід через бектик" 'cat `touch /tmp/x`' "метасимвол"
  deny "обхід переносом рядка" $'ls\ntouch /tmp/x' "перенос рядка"
  deny "обхід через >" "cat /etc/hostname > /tmp/x" "метасимвол"
  deny "обхід через лапки" "cat '/etc/hostname'" "метасимвол"

  # ── Справжній exec, не лише DRYRUN ─────────────────────────────────────────
  local out rc=0
  out="$(SSH_ORIGINAL_COMMAND="uname -s" bash "$SCRIPT" 2>&1)" || rc=$?
  [[ "$rc" == 0 && "$out" == "$(uname -s)" ]] && ok "exec: uname -s справді виконано" ||
    bad "exec uname: [$rc] '$out'"
  rc=0
  local d
  d="$(mktemp -d)"
  out="$(cd "$d" && SSH_ORIGINAL_COMMAND="touch pwned" bash "$SCRIPT" 2>&1)" || rc=$?
  # Перевіряємо сам файл, а не англійський текст `ls` — у локалізованому
  # середовищі той зламав би набір на справному коді (незалежне рев'ю №2).
  [[ "$rc" == 126 && "$out" == *"ВІДХИЛЕНО"* && ! -e "$d/pwned" ]] && ok "exec: touch не виконано, файла немає" ||
    bad "exec touch: [$rc] '$out'"
  rm -rf "$d"
}

run_scenarios

if [[ -z "${RO_SHELL_UNDER_TEST:-}" ]]; then
  mutate() {
    local m
    m="$(mktemp)"
    sed "$2" "$HERE/a8-ro-shell.sh" >"$m"
    if cmp -s "$m" "$HERE/a8-ro-shell.sh"; then
      bad "мутація «$1» нічого не змінила"
    elif ! bash -n "$m" 2>/dev/null; then
      bad "мутація «$1» ламає синтаксис — некоректна, а не вбита"
    elif QUIET=1 RO_SHELL_UNDER_TEST="$m" bash "$0" >/dev/null 2>&1; then
      bad "мутація «$1» ВИЖИЛА"
    else
      ok "мутація «$1» убита"
    fi
    rm -f "$m"
  }
  mutate "без перевірки метасимволів" '/deny "метасимвол оболонки/d'
  mutate "без перевірки переносу рядка" '/deny "перенос рядка"/d'
  mutate "будь-яке дієслово" 's/  \*) deny "дієслово/  *) true "дієслово/'
  mutate "sudo перед будь-чим" 's/      \*) deny "sudo перед/      *) true "sudo перед/'
  mutate "iptables: будь-який прапорець" 's/        -\*) deny "iptables: прапорець/        -*) true "iptables: прапорець/'
  mutate "systemctl без перевірки цілі" 's/-H\* | --host\* | -M\* | --machine\*) deny/-H* | --host* | -M* | --machine*) true/'
  mutate "find без заборони дій" 's/      deny "find з дією запису\/виконання"/      true/'
  mutate "crontab без точної форми" 's/      deny "crontab лише/      true "crontab лише/'
  mutate "ufw без точної форми" 's/      deny "ufw лише/      true "ufw лише/'
fi

if [[ "$fail" -eq 1 ]]; then
  echo "FAIL"
  exit 1
fi
[[ -z "${QUIET:-}" ]] && echo "Усі тести пройдено."
exit 0
