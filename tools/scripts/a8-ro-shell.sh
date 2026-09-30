#!/usr/bin/env bash
# a8-ro-shell.sh — ssh-вхід на A8, через який можна ЛИШЕ читати стан.
#
# ЧОМУ. Правило дозволу `Bash(ssh a8-ts:*)` пропускає будь-яку віддалену
# команду: префікс обмежує те, що ДО неї, а не те, що ПІСЛЯ. Угода «ssh лише на
# читання» трималась на ручних підтвердженнях і нічому більше. Цей скрипт
# переносить межу на сам A8: ключ у ~/.ssh/authorized_keys з `command="…"`
# виконує лише його, а він виконує лише дієслова читання.
#
# ЯК. sshd кладе запитану команду в SSH_ORIGINAL_COMMAND. Скрипт:
#   1. відхиляє будь-який метасимвол оболонки, лапки і перенос рядка — тож
#      `;`, `&&`, `||`, `|`, `$(…)`, бектик, `>`, `<` не можуть склеїти другу
#      команду;
#   2. ділить рядок на слова за пробілами (без інтерпретації оболонкою);
#   3. пропускає лише дієслова зі списку, з обмеженням підкоманд;
#   4. виконує `exec` масиву аргументів — оболонка в цьому шляху не бере участі
#      взагалі, тож п.1 — друга лінія, а не єдина.
#
# `sudo -n` дозволено лише перед дієсловами, які без root не бачать стан
# (`docker`, `iptables`, `ufw`, `crontab -l -u`, `ls`, `stat`). `sudo cat`,
# `sudo find` — ні: це читання будь-якого файла, включно з токенами агента.
#
# МЕЖА. Скрипт обмежує ДІЄСЛОВА, а не права: `cat`, `date -f`, `find` читають
# усе, що може прочитати ssh-користувач, під яким прописано ключ. Якщо ключ
# лежить у authorized_keys користувача з безпарольним sudo, `sudo -n` перед
# дозволеними дієсловами виконується від root — саме тому список `sudo`-дієслів
# вузький, а прапорці iptables перевіряються списком дозволеного.
#
# Змінна A8_RO_SHELL_DRYRUN=1 друкує, що було б виконано, замість exec — для тесту.
set -uo pipefail

deny() {
  echo "a8-ro-shell: ВІДХИЛЕНО — $1" >&2
  exit 126
}

cmd="${SSH_ORIGINAL_COMMAND:-}"
[[ -n "${cmd//[[:space:]]/}" ]] || deny "порожня команда (інтерактивний вхід заборонено)"

# 1. Метасимволи. Перенос рядка — окремо: у класі [...] його не видно.
[[ "$cmd" == *$'\n'* || "$cmd" == *$'\r'* ]] && deny "перенос рядка"
[[ "$cmd" =~ [\;\&\|\`\$\<\>\(\)\{\}\\\'\"\!\*\?] ]] && deny "метасимвол оболонки у '$cmd'"

# 2. Слова.
read -r -a argv <<<"$cmd"

sudo_prefix=()
if [[ "${argv[0]}" == sudo ]]; then
  [[ "${argv[1]:-}" == -n ]] || deny "sudo лише як 'sudo -n'"
  # `sudo -n -l` — окремий дозволений випадок (див. нижче).
  if [[ "${argv[2]:-}" != -l ]]; then
    sudo_prefix=(sudo -n)
    argv=("${argv[@]:2}")
    case "${argv[0]:-}" in
      docker | iptables | ufw | crontab | ls | stat) ;;
      *) deny "sudo перед '${argv[0]:-}' не дозволено" ;;
    esac
  fi
fi

verb="${argv[0]:-}"
sub="${argv[1]:-}"
rest=("${argv[@]:1}")

has_any() { # has_any <слово...> — чи є серед аргументів хоч одне із заборонених
  local a w
  for a in "${rest[@]}"; do
    for w in "$@"; do [[ "$a" == "$w" ]] && return 0; done
  done
  return 1
}

# 3. Дієслова.
case "$verb" in
  cat | ls | stat | id | getent | uname | free | df | who | date) ;;
  find)
    has_any -exec -execdir -ok -okdir -delete -fprint -fprint0 -fprintf -fls &&
      deny "find з дією запису/виконання"
    ;;
  dpkg) [[ "$sub" == -l ]] || deny "dpkg лише '-l'" ;;
  systemctl)
    case "$sub" in
      status | list-units | list-timers | is-enabled | is-active) ;;
      *) deny "systemctl лише status|list-units|list-timers|is-enabled|is-active" ;;
    esac
    # -H/--host відкриває ssh з A8 на іншу машину; -M/--machine — в контейнер.
    for a in "${rest[@]}"; do
      case "$a" in
        -H* | --host* | -M* | --machine*) deny "systemctl з віддаленою ціллю ($a)" ;;
      esac
    done
    ;;
  docker)
    case "$sub" in
      images | ps) ;;
      *) deny "docker лише images|ps" ;;
    esac
    ;;
  iptables)
    # СПИСОК ДОЗВОЛЕНОГО, не заборонене: iptables приймає злиті короткі
    # прапорці (`-nZ`) і скорочені довгі (`--zer` = `--zero`), тож перелік
    # заборонених слів обходиться, а `-L -nZ` від root обнуляє лічильники
    # (перевірено на T470: розбір опцій приймає обидва; знайдено незалежним
    # рев'ю №2). `--modprobe=<cmd>` виконав би програму від root.
    want_table=0
    for a in "${rest[@]}"; do
      if ((want_table)); then
        case "$a" in filter | nat | mangle | raw) ;; *) deny "iptables: таблиця '$a'" ;; esac
        want_table=0
        continue
      fi
      case "$a" in
        -L | -S | --list | --list-rules | -n | --numeric | -v | --verbose | -x | --exact | --line-numbers) ;;
        -t | --table) want_table=1 ;;
        -*) deny "iptables: прапорець '$a' не в списку читання" ;;
        *) [[ "$a" =~ ^[A-Za-z0-9_-]+$ ]] || deny "iptables: ім'я ланцюга '$a'" ;;
      esac
    done
    has_any -L -S --list --list-rules || deny "iptables лише -L або -S"
    ;;
  ufw)
    [[ "$sub" == status ]] && { [[ "${#rest[@]}" == 1 ]] ||
      { [[ "${#rest[@]}" == 2 ]] && [[ "${rest[1]}" == verbose || "${rest[1]}" == numbered ]]; }; } ||
      deny "ufw лише 'status [verbose|numbered]'"
    ;;
  crontab)
    # Рівно `-l` або `-l -u <користувач>`: `-l -r` чи `-r` видаляють crontab.
    { [[ "${#rest[@]}" == 1 && "$sub" == -l ]] ||
      [[ "${#rest[@]}" == 3 && "$sub" == -l && "${rest[1]}" == -u && "${rest[2]}" =~ ^[a-z_][a-z0-9_-]*$ ]]; } ||
      deny "crontab лише '-l' або '-l -u <користувач>'"
    ;;
  sudo) [[ "${argv[1]:-}" == -n && "${argv[2]:-}" == -l ]] || deny "sudo лише -n -l" ;;
  *) deny "дієслово '$verb' не в списку читання" ;;
esac

final=("${sudo_prefix[@]}" "${argv[@]}")
if [[ -n "${A8_RO_SHELL_DRYRUN:-}" ]]; then
  printf 'EXEC:'
  printf ' %s' "${final[@]}"
  printf '\n'
  exit 0
fi
exec "${final[@]}"
