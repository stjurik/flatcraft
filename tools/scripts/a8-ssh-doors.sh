#!/usr/bin/env bash
# a8-ssh-doors.sh — хто входить на A8 через ssh і чим (#305, #301). Лише читання.
#
# ЧОМУ. 2026-11-07 двері a8-ctl виявились зачиненими при зеленому verify: ручний
# `AllowUsers yurii` відкидав agent ще до перевірки ключа, а V22i дивився лише на
# authorized_keys. Дописати agent в AllowUsers — означає інше: ВІДТЕПЕР діє кожен
# ключ у файлах ключів agent, а agent у групі docker = root на хості. Тож межу
# треба доводити з обох боків одним прогоном:
#   1. sshd пускає тих, кого треба: адміністратора — завжди, agent — коли йому
#      задано ключ a8-ctl. Паролів і keyboard-interactive немає, root не входить.
#   2. файли ключів agent містять РІВНО рядки a8-ctl для поточних ключів:
#      `restrict,command="/usr/local/bin/a8-ctl" <тип> <base64>[ коментар]` —
#      поле опцій точно таке, а не «restrict десь у рядку». Будь-який інший рядок
#      (чужий ключ, pty, forwarding, відкликаний ключ) — порушення. Заданий
#      ключ, рядка якого немає, — теж (двері зачинені, так було 07.11 вранці).
#
# ЯК sshd. `sshd -T -C user=…,host=localhost,addr=127.0.0.1` друкує ефективну
# конфігурацію для користувача; AllowUsers/DenyUsers/AllowGroups/DenyGroups —
# рядок на кожен запис (виміряно на OpenSSH 9.6p1, Ubuntu 24.04). Їх sshd -T НЕ
# оцінює — оцінює цей скрипт, з шаблонами `*` і `?`, як sshd.
#
# МЕЖА (чого не доводить):
#   - Адреса клієнта. -T рахує Match для 127.0.0.1, а T470 приходить з іншої
#     адреси. Тому `Match` з Address/Host/LocalAddress/LocalPort/RDomain у
#     sshd_config чи sshd_config.d/*.conf — порушення: оцінити його тут нічим. З
#     тієї ж причини запис `user@адреса` в AllowUsers не зараховується як «пускає».
#   - Живий процес. -T читає конфіг з диска; якщо після правки не було reload,
#     живий sshd поводиться ще по-старому (docs/19 §B.2: `sshd -t && reload`).
#   - Що T470 справді входить: це доводить лише `ssh a8-ctl status` з T470.
#
# Використання (від root — sshd -T читає ключі хоста):
#   a8-ssh-doors.sh --agent agent --admin yurii [--key "ssh-ed25519 AAAA… коментар"]…
#   (--key=<рядок> теж можна; ключів може бути кілька або жодного)
# Вихід: 0 — двері такі, як описано; 1 — порушення (кожне рядком «✗»); 2 — виклик.
#
# Шви для тесту: A8_SSHD (sshd), A8_SSH_ETC (/etc/ssh), A8_GETENT (getent), A8_ID (id).
set -uo pipefail

SSHD="${A8_SSHD:-/usr/sbin/sshd}"
SSH_ETC="${A8_SSH_ETC:-/etc/ssh}"
GETENT="${A8_GETENT:-getent}"
ID="${A8_ID:-id}"
CTL_OPTS='restrict,command="/usr/local/bin/a8-ctl"'

agent="" admin=""
keys=()
while (($#)); do
  case "$1" in
    --agent) agent="${2:-}"; shift 2 || exit 2 ;;
    --admin) admin="${2:-}"; shift 2 || exit 2 ;;
    --key) keys+=("${2:-}"); shift 2 || exit 2 ;;
    --key=*) keys+=("${1#--key=}"); shift ;;
    *) echo "a8-ssh-doors: невідомий аргумент: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$agent" ]] || { echo "a8-ssh-doors: потрібен --agent" >&2; exit 2; }

bad=()
ok=()
# Ключ = «тип base64» (перші два поля рядка .pub); коментар не важить.
wanted=()
for k in "${keys[@]}"; do
  read -r t b _ <<<"$k"
  [[ -n "$t" && -n "$b" ]] || { bad+=("--key «$k» — не рядок .pub (тип, base64)"); continue; }
  wanted+=("$t $b")
done

# Шаблон sshd: лише `*` і `?`. Решту символів (зокрема [ ] \) беремо буквально,
# бо в bash вони теж були б шаблоном, а в sshd — ні.
glob_match() { # glob_match <рядок> <шаблон>
  local p="$2" q="" c i
  for ((i = 0; i < ${#p}; i++)); do
    c="${p:i:1}"
    case "$c" in
      '*' | '?') q+="$c" ;;
      *) q+="\\$c" ;;
    esac
  done
  # shellcheck disable=SC2053 # $q — навмисно шаблон
  [[ "$1" == $q ]]
}

# Записи ключа з ефективної конфігурації: усі значення рядків «<ключ> …».
cfg_values() { sed -n "s/^$1 //p" <<<"$2"; }

# Відмова sshd у доступі — порушення лише тоді, коли доступ мусить бути (need=1).
# agent без заданого ключа a8-ctl не мусить проходити AllowUsers — так навіть краще.
deny_access() { ((need)) && bad+=("$1"); }

root_checked=0
check_user() { # check_user <користувач> <роль: агент|адмін> <need: 1 — мусить входити>
  local u="$1" role="$2" need="$3" cfg rc e upart groups g allowed maybe v
  cfg="$("$SSHD" -T -C "user=$u,host=localhost,addr=127.0.0.1" 2>&1)"
  rc=$?
  if ((rc != 0)); then
    bad+=("sshd -T для $u: rc=$rc — $(head -n 1 <<<"$cfg")")
    return 1
  fi
  [[ "$(cfg_values passwordauthentication "$cfg")" == no ]] ||
    bad+=("$u ($role): PasswordAuthentication не no — паролі увімкнено (docs/19 §B.2)")
  [[ "$(cfg_values kbdinteractiveauthentication "$cfg")" == no ]] ||
    bad+=("$u ($role): KbdInteractiveAuthentication не no — через PAM це той самий пароль (docs/19 §B.2)")
  [[ "$(cfg_values pubkeyauthentication "$cfg")" == yes ]] ||
    bad+=("$u ($role): PubkeyAuthentication не yes — ключем не ввійти")
  if ((root_checked == 0)); then
    root_checked=1
    [[ "$(cfg_values permitrootlogin "$cfg")" == no ]] ||
      bad+=("PermitRootLogin не no — root входить через ssh (docs/19 §B.2)")
  fi
  v="$(cfg_values authenticationmethods "$cfg")"
  if [[ "$v" != any ]] && ! tr ' ' '\n' <<<"$v" | grep -qx publickey; then
    bad+=("$u ($role): AuthenticationMethods «$v» — немає методу «лише publickey»")
  fi

  # DenyUsers — відмова, якщо збігається частина до @ (адресу не знаємо — гірший випадок).
  while IFS= read -r e; do
    [[ -z "$e" ]] && continue
    upart="${e%%@*}"
    if [[ "$e" == '!'* ]] || glob_match "$u" "$upart"; then
      deny_access "$u ($role): DenyUsers «$e» — sshd відкине"
    fi
  done < <(cfg_values denyusers "$cfg")

  # AllowUsers — порожньо: пускає всіх; інакше потрібен запис без адреси, що збігається.
  allowed=0 maybe=""
  mapfile -t v_allow < <(cfg_values allowusers "$cfg")
  if ((${#v_allow[@]} == 0)); then
    allowed=1
  else
    for e in "${v_allow[@]}"; do
      [[ "$e" == '!'* ]] && continue
      upart="${e%%@*}"
      if [[ "$e" == *@* ]]; then
        glob_match "$u" "$upart" && maybe+=" $e"
      elif glob_match "$u" "$e"; then
        allowed=1
      fi
    done
  fi
  if ((allowed == 0)); then
    if [[ -n "$maybe" ]]; then
      deny_access "$u ($role): AllowUsers пускає лише з адреси (${maybe# }) — verify адреси клієнта не знає; потрібен запис «$u» без @ (docs/19 §B.2)"
    else
      deny_access "$u ($role): не проходить AllowUsers (${v_allow[*]}) — sshd відкине ще до ключа (docs/19 §B.2: AllowUsers <адмін> $agent)"
    fi
  fi

  # AllowGroups / DenyGroups — за групами з самої машини.
  groups="$("$ID" -Gn "$u" 2>/dev/null)"
  mapfile -t v_allow < <(cfg_values allowgroups "$cfg")
  if ((${#v_allow[@]} > 0)); then
    allowed=0
    for e in "${v_allow[@]}"; do
      for g in $groups; do glob_match "$g" "$e" && allowed=1; done
    done
    ((allowed == 1)) || deny_access "$u ($role): не в жодній з AllowGroups (${v_allow[*]}); групи: ${groups:-—}"
  fi
  while IFS= read -r e; do
    [[ -z "$e" ]] && continue
    for g in $groups; do
      glob_match "$g" "${e#!}" && deny_access "$u ($role): група $g у DenyGroups «$e» — sshd відкине"
    done
  done < <(cfg_values denygroups "$cfg")

  if [[ "$role" == агент ]]; then
    [[ "$(cfg_values authorizedkeyscommand "$cfg")" == none ]] ||
      bad+=("$u: AuthorizedKeysCommand не none — ключі agent беруться не з файла, verify їх не бачить")
    [[ "$(cfg_values trustedusercakeys "$cfg")" == none ]] ||
      bad+=("$u: TrustedUserCAKeys не none — сертифікат CA пустить agent без рядка в authorized_keys")
    agent_akfiles="$(cfg_values authorizedkeysfile "$cfg")"
  fi
  return 0
}

# Match за адресою оцінити нічим (МЕЖА вище) — тому порушення, а не мовчання.
check_match_blocks() {
  local f line
  for f in "$SSH_ETC/sshd_config" "$SSH_ETC"/sshd_config.d/*.conf; do
    [[ -f "$f" ]] || continue
    while IFS= read -r line; do
      bad+=("$f: «${line#"${line%%[![:space:]]*}"}» — verify рахує sshd лише для addr=127.0.0.1; блок за адресою може зачинити чи відчинити двері для T470")
    done < <(grep -iE '^[[:space:]]*match[[:space:]]' "$f" | grep -iE '(^|[[:space:]])(address|host|localaddress|localport|rdomain)[[:space:]]')
  done
}

agent_akfiles=""
if [[ -n "$admin" ]]; then
  before=${#bad[@]}
  check_user "$admin" адмін 1
  ((${#bad[@]} == before)) && ok+=("$admin (адмін): sshd пускає, лише ключем; паролів немає")
else
  bad+=("невідомо, ким входить адміністратор (--admin порожній) — перевірити, що він не зачинить собі двері, нічим")
fi
# agent мусить проходити, лише коли йому задано ключ a8-ctl.
before=${#bad[@]}
check_user "$agent" агент "$(( ${#wanted[@]} > 0 ? 1 : 0 ))"
if ((${#bad[@]} == before)); then
  ((${#wanted[@]} > 0)) && ok+=("$agent (агент): sshd пускає, лише ключем; паролів немає") ||
    ok+=("$agent (агент): ключа a8-ctl не задано — проходити AllowUsers не мусить; паролів немає")
fi
check_match_blocks

# ─── Файли ключів agent ──────────────────────────────────────────────────────
home="$("$GETENT" passwd "$agent" | cut -d: -f6)"
if [[ -z "$home" ]]; then
  bad+=("getent passwd $agent — домашньої теки не знайдено")
else
  [[ -n "$agent_akfiles" ]] || agent_akfiles=".ssh/authorized_keys .ssh/authorized_keys2"
  declare -A seen=()
  lines_total=0
  for p in $agent_akfiles; do
    p="${p//%%/$'\001'}"
    p="${p//%h/$home}"
    p="${p//%u/$agent}"
    p="${p//$'\001'/%}"
    [[ "$p" == /* ]] || p="$home/$p"
    [[ -e "$p" || -L "$p" ]] || continue
    if [[ -L "$p" || ! -f "$p" ]]; then
      bad+=("$p — не звичайний файл (симлінк?) — вміст ключів agent визначає не він")
      continue
    fi
    for q in "$p" "$(dirname "$p")"; do
      read -r owner mode < <(stat -c '%U %a' "$q")
      [[ "$owner" == "$agent" || "$owner" == root ]] ||
        bad+=("$q: власник $owner — писати ключі agent може не лише agent/root")
      (((8#$mode & 8#022) == 0)) ||
        bad+=("$q: права $mode — пишуть група чи інші (sshd StrictModes відкине, а хтось допише ключ)")
    done
    n=0
    while IFS= read -r line || [[ -n "$line" ]]; do
      n=$((n + 1))
      line="${line%$'\r'}"
      [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
      lines_total=$((lines_total + 1))
      if [[ "$line" =~ ^restrict,command=\"/usr/local/bin/a8-ctl\"\ ([^ ]+\ [^ ]+)(\ .*)?$ ]]; then
        kb="${BASH_REMATCH[1]}"
        found=0
        for w in "${wanted[@]}"; do [[ "$w" == "$kb" ]] && found=1; done
        if ((found)); then
          seen["$kb"]=1
        else
          bad+=("$p:$n — ключ a8-ctl не з поточних (відкликаний чи чужий): ${kb:0:24}…${kb: -8}")
        fi
      else
        bad+=("$p:$n — рядок не «$CTL_OPTS <ключ>» (опції — перше поле, рівно так): ${line:0:60}…")
      fi
    done <"$p"
  done
  for w in "${wanted[@]}"; do
    [[ -n "${seen[$w]:-}" ]] ||
      bad+=("ключ a8-ctl задано (${w:0:24}…${w: -8}), а рядка «$CTL_OPTS …» у файлах ключів $agent немає — двері зачинені")
  done
  ok+=("файли ключів $agent ($agent_akfiles): рядків $lines_total, кожен — $CTL_OPTS з поточним ключем; задано ключів: ${#wanted[@]}")
fi

if ((${#bad[@]} > 0)); then
  echo "a8-ssh-doors: порушень ${#bad[@]}:"
  printf '  ✗ %s\n' "${bad[@]}"
  exit 1
fi
printf '✓ %s\n' "${ok[@]}"
exit 0
