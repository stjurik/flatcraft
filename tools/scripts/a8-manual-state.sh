#!/usr/bin/env bash
# a8-manual-state.sh — ручні правки A8, яких роль не робить, проти їхнього опису (#306).
#
# ЧОМУ. 2026-11-07 двері a8-ctl виявились зачиненими через `AllowUsers yurii`,
# дописаний на A8 руками: рядка не було ні в ролі, ні в docs/19, і зелений verify
# про нього не знав. CLAUDE.md §0 п.5: «конфігурація, якої немає в git, не існує».
# Частину стану A8 роль свідомо не чіпає (sshd, ufw — помилка там коштує доступу
# до машини без консолі), тож для неї лишається одне: описати в git і перевіряти
# ЧИТАННЯМ, що машина відповідає опису.
#
# Два режими, обидва лише читають (від root — ufw і sshd -T без root не відповідають):
#   check      — описане проти фактичного; 0 — збігається, 1 — ні (рядок «✗» на
#                кожну розбіжність). Його кличе verify (V25).
#   inventory  — дамп усього, що відомо як ручне, для звірки людиною (#306 крок 1):
#                що стоїть насправді, щоб дописати в опис або прибрати з машини.
#
# ЩО ПЕРЕВІРЯЄ check — і звідки опис:
#   1. ufw (docs/19 §B.3 «нічого вхідного з інтернету»): ufw увімкнено; Default —
#      deny (incoming), allow (outgoing); жодного правила ALLOW IN / LIMIT IN з
#      джерелом Anywhere без прив'язки до інтерфейсу («… on <інтерфейс>»). Адреси
#      LAN і tailnet у репозиторії не пишемо: дозволене з конкретної адреси чи
#      інтерфейсу проходить і друкується в рядку ✓ — його видно у verify.
#   2. docker.service.d/ufw-reload.conf (README ролі, знайдено read-only
#      2026-09-18): є і робить `ufw reload` у ExecStartPost. На ньому стоїть
#      порядок drop-in'а zz-a8-egress.conf (a8-egress-dropin.conf.j2).
#   3. /etc/ufw/after.rules (README ролі): блок `# BEGIN A8 DOCKER-USER` з рядком
#      `:DOCKER-USER - [0:0]` — звідси ланцюг DOCKER-USER, у який роль вставляє
#      egress-правила.
# sshd перевіряє a8-ssh-doors.sh (V22j–k, PR #305), тут — лише в inventory.
#
# ЧОГО НЕ ПЕРЕВІРЯЄ. `99-a8.conf` (sysctl чи journald — опису ніде немає, #284):
# лише inventory, доки людина не опише вміст. Правила ip6tables/nft поза ufw.
# Чи справжні правила ufw у ядрі збігаються з `ufw status` (ufw друкує свої
# файли правил, а не iptables -S).
#
# Шви для тесту: A8_UFW (ufw), A8_ETC (/etc), A8_SSHD (sshd).
set -uo pipefail

UFW="${A8_UFW:-ufw}"
ETC="${A8_ETC:-/etc}"
SSHD="${A8_SSHD:-/usr/sbin/sshd}"
DROPIN="$ETC/systemd/system/docker.service.d/ufw-reload.conf"
AFTER="$ETC/ufw/after.rules"

mode="${1:-}"
case "$mode" in
  check | inventory) ;;
  *)
    echo "використання: a8-manual-state.sh check|inventory" >&2
    exit 2
    ;;
esac

bad=()
ok=()

check_ufw() {
  local st line to action from n=0 allowed=""
  if ! st="$("$UFW" status verbose 2>&1)"; then
    bad+=("ufw status verbose не відпрацював: $(head -n 1 <<<"$st")")
    return
  fi
  grep -qx 'Status: active' <<<"$st" || bad+=("ufw не увімкнено ($(head -n 1 <<<"$st")) — docs/19 §B.3: ufw enable")
  grep -qE '^Default: deny \(incoming\), allow \(outgoing\)' <<<"$st" ||
    bad+=("ufw: $(grep '^Default:' <<<"$st" || echo 'Default: —') — docs/19 §B.3: deny incoming, allow outgoing")
  # Таблиця правил — після рядка «--  ------  ----». Колонки розділяє дія:
  # «To  ALLOW IN  From» (виміряно на ufw 0.36.2, Ubuntu 24.04).
  while IFS= read -r line; do
    # Коментар правила ufw друкує в кінці: «Anywhere   # http» (виміряно на ufw
    # 0.36.2). Без зрізання from було б «Anywhere … # http» і правило з
    # інтернету проходило б як безпечне (рецензія #315, Argon №5А). У колонках
    # To/From «#» не буває.
    line="${line%%[[:space:]]#*}"
    [[ "$line" =~ ^(.*[^[:space:]])[[:space:]]{2,}(ALLOW|LIMIT)\ IN[[:space:]]{2,}(.*[^[:space:]])[[:space:]]*$ ]] || continue
    to="${BASH_REMATCH[1]}" action="${BASH_REMATCH[2]}" from="${BASH_REMATCH[3]}"
    n=$((n + 1))
    if [[ "$from" == Anywhere || "$from" == "Anywhere (v6)" ]] && [[ "$to" != *" on "* ]]; then
      bad+=("ufw: «$to $action IN $from» — вхідне з інтернету (docs/19 §B.3: лише з LAN/інтерфейсу)")
    else
      allowed+="${allowed:+; }$to ← $from"
    fi
  done < <(sed -n '/^--/,$p' <<<"$st")
  ok+=("ufw: увімкнено, deny incoming / allow outgoing; вхідних дозволів $n${allowed:+: $allowed}")
}

check_dropin() {
  if [[ ! -f "$DROPIN" ]]; then
    bad+=("$DROPIN немає — опис (README ролі) каже, що він є і робить ufw reload після старту docker; оновіть опис або поверніть файл")
    return
  fi
  if grep -qE '^[[:space:]]*ExecStartPost=.*ufw[[:space:]]+reload' "$DROPIN"; then
    ok+=("$DROPIN: ExecStartPost з ufw reload — як в описі")
  else
    bad+=("$DROPIN без ExecStartPost=… ufw reload — розходиться з описом (README ролі, a8-egress-dropin.conf.j2)")
  fi
}

check_after_rules() {
  if [[ ! -f "$AFTER" ]]; then
    bad+=("$AFTER немає — ланцюг DOCKER-USER для egress-правил ніхто не оголошує")
    return
  fi
  if grep -qxF '# BEGIN A8 DOCKER-USER' "$AFTER" && grep -qxF ':DOCKER-USER - [0:0]' "$AFTER"; then
    ok+=("$AFTER: блок «# BEGIN A8 DOCKER-USER» з «:DOCKER-USER - [0:0]» — як в описі")
  else
    bad+=("$AFTER без блоку «# BEGIN A8 DOCKER-USER» і рядка «:DOCKER-USER - [0:0]» — розходиться з описом (README ролі)")
  fi
}

inventory() {
  local f
  echo "# a8-manual-state inventory — $(date -u +%FT%TZ) — лише читання (#306)"
  echo
  echo "## ufw status verbose"
  "$UFW" status verbose 2>&1
  echo
  echo "## $AFTER — блок A8"
  [[ -f "$AFTER" ]] && sed -n '/^# BEGIN A8/,/^# END A8/p' "$AFTER" || echo "(файла немає)"
  echo
  echo "## docker.service.d"
  for f in "$ETC"/systemd/system/docker.service.d/*; do
    [[ -f "$f" ]] || continue
    echo "### $f"
    cat "$f"
  done
  echo
  echo "## sshd: файли конфігурації (ручні — усе, крім пакетного sshd_config)"
  for f in "$ETC"/ssh/sshd_config.d/*; do
    [[ -f "$f" ]] || continue
    echo "### $f"
    cat "$f"
  done
  echo "### sshd -T (рядки, які стосуються входу)"
  "$SSHD" -T 2>&1 | grep -E '^(allowusers|denyusers|allowgroups|denygroups|passwordauthentication|kbdinteractiveauthentication|permitrootlogin|pubkeyauthentication|authenticationmethods|authorizedkeysfile|authorizedkeyscommand|trustedusercakeys|port|listenaddress) '
  echo
  echo "## 99-a8.conf (#284 — опису немає; де лежить і що всередині)"
  local found=0
  while IFS= read -r -d '' f; do
    found=1
    echo "### $f"
    cat "$f"
  done < <(find "$ETC" -name '99-a8.conf' -type f -print0 2>/dev/null)
  ((found)) || echo "(у $ETC немає жодного 99-a8.conf)"
  echo
  echo "## sysctl.d і journald.conf.d (docs/19 §B.5 описує лише 99-swap.conf)"
  for f in "$ETC"/sysctl.d/*.conf "$ETC"/systemd/journald.conf.d/*.conf; do
    [[ -f "$f" ]] || continue
    echo "### $f"
    cat "$f"
  done
}

if [[ "$mode" == inventory ]]; then
  inventory
  exit 0
fi

check_ufw
check_dropin
check_after_rules
if ((${#bad[@]} > 0)); then
  echo "a8-manual-state: розбіжностей з описом ${#bad[@]}:"
  printf '  ✗ %s\n' "${bad[@]}"
  exit 1
fi
printf '✓ %s\n' "${ok[@]}"
exit 0
