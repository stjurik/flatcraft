#!/usr/bin/env bash
# a8-ssh-doors.test.sh — сценарії для a8-ssh-doors.sh (#305, #301).
#
# sshd, getent і id підмінено заглушками: ефективна конфігурація — файл, який
# друкує заглушка `sshd -T` (окремий на користувача, якщо є T.<user>). Формат
# виводу заглушки — той самий, що в справжнього OpenSSH 9.6p1 (рядок на запис
# AllowUsers/DenyUsers/…; виміряно 2026-11-09). Якщо справжній sshd є і запускається
# (`sshd -T -f`), у кінці — ще прогін на ньому: він перевіряє саме цей формат.
#
# Кожен червоний сценарій — обхід, який V22i до #305 пропускав або який назвала
# рецензія #305 (Flash, Argon, Sonnet): рядок-обхід у коментарі, pty, ключ без
# слова a8-ctl, відкликаний ключ, заданий ключ без рядка, AllowUsers без адміна,
# agent@адреса, DenyUsers, AllowGroups, Match Address, authorized_keys2.
#
# Запуск: tools/scripts/a8-ssh-doors.test.sh
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/a8-ssh-doors.sh"
fail=0
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILlNFDkKQRcRq2c1i1TaZWUtvoCpy8sbgQEOOzluehSS"
OLD="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO+6ubU4kALwVywAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
LINE="restrict,command=\"/usr/local/bin/a8-ctl\" $KEY a8-ctl@t470"

# Здорова ефективна конфігурація (`sshd -T`, лише рядки, які читає скрипт).
T_OK='pubkeyauthentication yes
passwordauthentication no
kbdinteractiveauthentication no
permitrootlogin no
authenticationmethods any
authorizedkeyscommand none
trustedusercakeys none
authorizedkeysfile .ssh/authorized_keys .ssh/authorized_keys2
allowusers yurii
allowusers agent'

# setup <тека> <вміст authorized_keys або «-» — файла немає> [<вміст sshd -T>]
setup() {
  local d="$1"
  rm -rf "$d"
  mkdir -p "$d/bin" "$d/etc/sshd_config.d" "$d/home/agent/.ssh"
  chmod 700 "$d/home/agent/.ssh"
  if [[ "$2" != - ]]; then
    printf '%s\n' "$2" >"$d/home/agent/.ssh/authorized_keys"
    chmod 600 "$d/home/agent/.ssh/authorized_keys"
  fi
  printf '%s\n' "${3:-$T_OK}" >"$d/T"
  printf 'Include /etc/ssh/sshd_config.d/*.conf\n' >"$d/etc/sshd_config"
  cat >"$d/bin/sshd" <<EOF
#!/usr/bin/env bash
# заглушка sshd -T -C user=<u>,…: друкує T.<u>, якщо є, інакше T
[[ "\$1" == -T && "\$2" == -C ]] || exit 9
u="\${3#user=}"; u="\${u%%,*}"
f="$d/T.\$u"; [[ -f "\$f" ]] || f="$d/T"
cat "\$f"
EOF
  printf '#!/usr/bin/env bash\n[[ "$1" == passwd ]] || exit 2\nprintf "%%s:x:uid:gid:gecos:%s/home/%%s:/bin/bash\\n" "$2" "$2"\n' "$d" >"$d/bin/getent"
  printf '#!/usr/bin/env bash\n[[ "$1" == -Gn ]] || exit 2\n[[ "$2" == agent ]] && echo "agent docker" || echo "%s sudo"\n' '$2' >"$d/bin/id"
  chmod +x "$d/bin/"*
}

run() { # run <тека> [аргументи…] → $tmp/out, код у $rc
  local d="$1"
  shift
  rc=0
  A8_SSHD="$d/bin/sshd" A8_SSH_ETC="$d/etc" A8_GETENT="$d/bin/getent" A8_ID="$d/bin/id" A8_KEYS_OWNER="$ME" \
    "$SCRIPT" "$@" >"$tmp/out" 2>&1 || rc=$?
}

# expect <назва> <код> <підрядок або ""> <тека> [аргументи…]
expect() {
  local name="$1" want="$2" sub="$3"
  shift 3
  run "$@"
  if [[ "$rc" -ne "$want" ]]; then
    echo "✗ $name — очікував exit $want, отримав $rc"
    sed 's/^/    /' "$tmp/out"
    fail=1
  elif [[ -n "$sub" ]] && ! grep -qF -- "$sub" "$tmp/out"; then
    echo "✗ $name — немає «$sub»"
    sed 's/^/    /' "$tmp/out"
    fail=1
  else
    echo "✓ $name"
  fi
}

A=(--agent agent --admin yurii)
# Файли ключів у тесті належать тому, хто тест запускає (у CI — runner): тільки
# root міг би віддати їх agent'у. Шов A8_KEYS_OWNER визнає цього власника.
ME="$(id -un)"
d="$tmp/d"

# ─── Здорові стани ───────────────────────────────────────────────────────────
setup "$d" "$LINE"
expect "рядок a8-ctl з поточним ключем, обидва в AllowUsers → 0" 0 "рядків 1" "$d" "${A[@]}" --key "$KEY a8-ctl@t470"
expect "--key=… теж приймається → 0" 0 "" "$d" "${A[@]}" "--key=$KEY"
expect "коментар ключа в змінній інший — важить лише тип і base64 → 0" 0 "" "$d" "${A[@]}" --key "$KEY інший"
setup "$d" "# коментар
$LINE

$LINE"
expect "коментарі, порожні рядки й дубль того самого рядка → 0" 0 "рядків 2" "$d" "${A[@]}" --key "$KEY"
setup "$d" - "$(grep -v '^allowusers' <<<"$T_OK")"
expect "без AllowUsers, ключа не задано й файла немає → 0" 0 "" "$d" "${A[@]}"
setup "$d" - "$(grep -v '^allowusers agent' <<<"$T_OK")"
expect "ключа не задано: agent може не проходити AllowUsers → 0" 0 "проходити AllowUsers не мусить" "$d" "${A[@]}"
setup "$d" "$LINE" "${T_OK/allowusers agent/allowusers a*}"
expect "AllowUsers шаблоном a* → 0" 0 "" "$d" "${A[@]}" --key "$KEY"
setup "$d" "$LINE" "$T_OK
allowgroups docker
allowgroups sudo"
expect "AllowGroups, у які входять обидва → 0" 0 "" "$d" "${A[@]}" --key "$KEY"
setup "$d" "$LINE" "${T_OK/authenticationmethods any/authenticationmethods publickey,password publickey}"
expect "AuthenticationMethods із варіантом «лише publickey» → 0" 0 "" "$d" "${A[@]}" --key "$KEY"
setup "$d" "$LINE"
printf 'Match User agent\n  ForceCommand /usr/local/bin/a8-ctl\n' >"$d/etc/sshd_config.d/50-agent.conf"
expect "Match User (не за адресою) → 0" 0 "" "$d" "${A[@]}" --key "$KEY"

# ─── Файли ключів agent: рядок за полями, не підрядком (#301 п.2, #305) ──────
setup "$d" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFULLSHELLFULLSHELLFULLSHELLFULLSHELL123 restrict command=\"/usr/local/bin/a8-ctl\" a8-ctl
$LINE"
expect "рядок-обхід: restrict і command= лише в коментарі → 1" 1 "опції — перше поле" "$d" "${A[@]}" --key "$KEY"
setup "$d" "restrict,pty,port-forwarding,command=\"/usr/local/bin/a8-ctl\" $KEY a8-ctl@t470"
expect "restrict,pty,port-forwarding,command=… → 1" 1 "опції — перше поле" "$d" "${A[@]}" --key "$KEY"
setup "$d" "$LINE
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFULLSHELLFULLSHELLFULLSHELLFULLSHELL123 yurii@t470"
expect "другий ключ без слова a8-ctl і без опцій (повна оболонка agent) → 1" 1 "опції — перше поле" "$d" "${A[@]}" --key "$KEY"
setup "$d" "command=\"/usr/local/bin/a8-ctl\" $KEY"
expect "той самий ключ без restrict → 1" 1 "опції — перше поле" "$d" "${A[@]}" --key "$KEY"
setup "$d" "restrict,command=\"/usr/local/bin/a8-ro-shell\" $KEY"
expect "ключ з іншою командою (a8-ro-shell на agent не передбачено) → 1" 1 "опції — перше поле" "$d" "${A[@]}" --key "$KEY"
setup "$d" "restrict,command=\"/usr/local/bin/a8-ctl\"	$KEY"
expect "табуляція між опціями й ключем — не те, що пише роль → 1" 1 "опції — перше поле" "$d" "${A[@]}" --key "$KEY"
setup "$d" "$LINE
restrict,command=\"/usr/local/bin/a8-ctl\" $OLD a8-ctl@old"
expect "відкликаний ключ лишився рядком a8-ctl (#301 п.1) → 1" 1 "не з поточних" "$d" "${A[@]}" --key "$KEY"
setup "$d" -
expect "ключ задано, а файла немає (так було 07.11 вранці) → 1" 1 "двері зачинені" "$d" "${A[@]}" --key "$KEY"
setup "$d" "# $LINE"
expect "ключ задано, а рядок закоментовано → 1" 1 "двері зачинені" "$d" "${A[@]}" --key "$KEY"
setup "$d" "$LINE"
printf '%s\n' "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFULLSHELLFULLSHELLFULLSHELLFULLSHELL123 x" >"$d/home/agent/.ssh/authorized_keys2"
expect "повна оболонка в authorized_keys2 (sshd читає й його) → 1" 1 "authorized_keys2:1" "$d" "${A[@]}" --key "$KEY"
setup "$d" "$LINE" "${T_OK/authorizedkeysfile .ssh\/authorized_keys .ssh\/authorized_keys2/authorizedkeysfile /etc/ssh/keys/%u}"
mkdir -p "$d/etc/keys"
expect "AuthorizedKeysFile абсолютний, з %u — файла немає, ключ задано → 1" 1 "двері зачинені" "$d" "${A[@]}" --key "$KEY"
setup "$d" "$LINE"
if [[ "$ME" != root ]]; then
  ME_SAVED="$ME" ME=someone-else
  expect "файли ключів належать не agent і не root → 1" 1 "власник $ME_SAVED" "$d" "${A[@]}" --key "$KEY"
  ME="$ME_SAVED"
else
  echo "· від root файли ключів належать root (дозволено) — сценарій «чужий власник» пропущено; CI ганяє не від root"
fi
setup "$d" "$LINE"
chmod 664 "$d/home/agent/.ssh/authorized_keys"
expect "authorized_keys з правом запису групі → 1" 1 "права 664" "$d" "${A[@]}" --key "$KEY"
setup "$d" "$LINE"
mv "$d/home/agent/.ssh/authorized_keys" "$d/real"
ln -s "$d/real" "$d/home/agent/.ssh/authorized_keys"
expect "authorized_keys — симлінк → 1" 1 "не звичайний файл" "$d" "${A[@]}" --key "$KEY"
setup "$d" "$LINE"
expect "--key не рядок .pub → 1" 1 "не рядок .pub" "$d" "${A[@]}" --key "ssh-ed25519"

# ─── sshd: хто проходить (рецензія #305, п.1, 3, 4) ──────────────────────────
setup "$d" "$LINE" "$(grep -v '^allowusers agent' <<<"$T_OK")"
expect "AllowUsers yurii, ключ a8-ctl є (стан 07.11) → 1" 1 "agent (агент): не проходить AllowUsers" "$d" "${A[@]}" --key "$KEY"
setup "$d" "$LINE" "$(grep -v '^allowusers yurii' <<<"$T_OK")"
expect "AllowUsers agent без адміна — адмін зачинив би собі двері → 1" 1 "yurii (адмін): не проходить AllowUsers" "$d" "${A[@]}" --key "$KEY"
setup "$d" "$LINE" "${T_OK/allowusers agent/allowusers agent@203.0.113.9}"
expect "agent@<інша адреса> не зараховується як «пускає» → 1" 1 "пускає лише з адреси" "$d" "${A[@]}" --key "$KEY"
setup "$d" "$LINE" "${T_OK/allowusers agent/allowusers agentx}"
expect "agentx ≠ agent → 1" 1 "не проходить AllowUsers" "$d" "${A[@]}" --key "$KEY"
setup "$d" "$LINE" "${T_OK/allowusers agent/allowusers ag[e]nt}"
expect "[ ] у шаблоні sshd — буквально, не клас bash → 1" 1 "не проходить AllowUsers" "$d" "${A[@]}" --key "$KEY"
setup "$d" "$LINE" "$T_OK
denyusers ag*"
expect "DenyUsers ag* → 1" 1 "DenyUsers «ag*»" "$d" "${A[@]}" --key "$KEY"
setup "$d" "$LINE" "$T_OK
allowgroups sudo"
expect "AllowGroups sudo, agent лише в docker → 1" 1 "не в жодній з AllowGroups" "$d" "${A[@]}" --key "$KEY"
setup "$d" "$LINE" "$T_OK
denygroups docker"
expect "DenyGroups docker → 1" 1 "у DenyGroups" "$d" "${A[@]}" --key "$KEY"
setup "$d" "$LINE" "${T_OK/passwordauthentication no/passwordauthentication yes}"
expect "паролі увімкнено → 1" 1 "PasswordAuthentication не no" "$d" "${A[@]}" --key "$KEY"
setup "$d" "$LINE" "${T_OK/kbdinteractiveauthentication no/kbdinteractiveauthentication yes}"
expect "keyboard-interactive увімкнено → 1" 1 "KbdInteractiveAuthentication не no" "$d" "${A[@]}" --key "$KEY"
setup "$d" "$LINE" "${T_OK/permitrootlogin no/permitrootlogin without-password}"
expect "PermitRootLogin without-password → 1" 1 "PermitRootLogin не no" "$d" "${A[@]}" --key "$KEY"
setup "$d" "$LINE" "${T_OK/pubkeyauthentication yes/pubkeyauthentication no}"
expect "PubkeyAuthentication no → 1" 1 "PubkeyAuthentication не yes" "$d" "${A[@]}" --key "$KEY"
setup "$d" "$LINE" "${T_OK/authenticationmethods any/authenticationmethods publickey,password}"
expect "AuthenticationMethods publickey,password — одним ключем не ввійти → 1" 1 "AuthenticationMethods" "$d" "${A[@]}" --key "$KEY"
setup "$d" "$LINE" "${T_OK/authorizedkeyscommand none/authorizedkeyscommand /usr/bin/fetch-keys}"
expect "AuthorizedKeysCommand — ключі не з файла → 1" 1 "AuthorizedKeysCommand не none" "$d" "${A[@]}" --key "$KEY"
setup "$d" "$LINE" "${T_OK/trustedusercakeys none/trustedusercakeys /etc/ssh/ca.pub}"
expect "TrustedUserCAKeys — сертифікат пустить agent без рядка → 1" 1 "TrustedUserCAKeys не none" "$d" "${A[@]}" --key "$KEY"
setup "$d" "$LINE"
printf 'Match Address 198.51.100.0/24\n  PasswordAuthentication yes\n' >"$d/etc/sshd_config.d/60-lan.conf"
expect "Match Address у sshd_config.d — verify адреси не знає → 1" 1 "лише для addr=127.0.0.1" "$d" "${A[@]}" --key "$KEY"
setup "$d" "$LINE"
printf 'Match User agent Host t470\n' >>"$d/etc/sshd_config"
expect "Match User … Host … у sshd_config → 1" 1 "лише для addr=127.0.0.1" "$d" "${A[@]}" --key "$KEY"
setup "$d" "$LINE" "$T_OK"
printf '%s\n' "$(sed 's/^passwordauthentication no/passwordauthentication yes/' <<<"$T_OK")" >"$d/T.agent"
expect "паролі вимкнено для адміна, але не для agent (Match User) → 1" 1 "agent (агент): PasswordAuthentication" "$d" "${A[@]}" --key "$KEY"
setup "$d" "$LINE"
expect "адміністратора не названо → 1" 1 "невідомо, ким входить адміністратор" "$d" --agent agent --admin "" --key "$KEY"
setup "$d" "$LINE"
printf '#!/usr/bin/env bash\necho "sshd: no hostkeys available -- exiting." >&2\nexit 1\n' >"$d/bin/sshd"
expect "sshd -T не відпрацював → 1" 1 "sshd -T для yurii: rc=1" "$d" "${A[@]}" --key "$KEY"

# ─── Мутації скрипта ─────────────────────────────────────────────────────────
# Копія скрипта з однією вадою: сценарій, що її ловить, МУСИТЬ почервоніти.
# Тест, зелений на зламаному скрипті, доводить лише власну присутність.
mutant() { # mutant <назва> <було> <стало> — далі виклик expect із SCRIPT=мутант
  python3 - "$SCRIPT" "$tmp/mut.sh" "$2" "$3" <<'PY2'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src).read()
assert s.count(old) == 1, "фікстура застаріла: " + old[:60]
open(dst, "w").write(s.replace(old, new, 1))
PY2
  chmod +x "$tmp/mut.sh"
}
expect_mut() { # expect_mut <назва> <тека> [аргументи…] — мутант мусить дати 0 там, де чинний дає 1
  local name="$1" real="$SCRIPT"
  shift
  SCRIPT="$tmp/mut.sh" run "$@"
  local mrc=$rc
  SCRIPT="$real"
  if [[ "$mrc" -eq 0 ]]; then
    echo "✓ мутація «$name»: мутант пропускає, тож сценарій справді ловить цю ваду"
  else
    echo "✗ мутація «$name»: мутант теж дав $mrc — сценарій ловить щось інше"
    sed 's/^/    /' "$tmp/out"
    fail=1
  fi
}
mutant "підрядок замість поля опцій" \
  'if [[ "$line" =~ ^restrict,command=\"/usr/local/bin/a8-ctl\"\ ([^ ]+\ [^ ]+)(\ .*)?$ ]]; then' \
  'if [[ "$line" =~ restrict ]] && [[ "$line" =~ command=\"/usr/local/bin/a8-ctl\" ]] && [[ "$line" =~ (ssh-[a-z0-9]+\ [A-Za-z0-9+/=]+) ]]; then'
setup "$d" "restrict,pty,port-forwarding,command=\"/usr/local/bin/a8-ctl\" $KEY a8-ctl@t470"
expect_mut "підрядок замість поля опцій" "$d" "${A[@]}" --key "$KEY"
mutant "немає перевірки «ключ задано — рядок є»" \
  'bad+=("ключ a8-ctl задано (${w:0:24}…${w: -8}), а рядка «$CTL_OPTS …» у файлах ключів $agent немає — двері зачинені")' ':'
setup "$d" -
expect_mut "немає перевірки «ключ задано — рядок є»" "$d" "${A[@]}" --key "$KEY"
mutant "адміна не перевіряємо" 'check_user "$admin" адмін 1' ':'
setup "$d" "$LINE" "$(grep -v '^allowusers yurii' <<<"$T_OK")"
expect_mut "адміна не перевіряємо" "$d" "${A[@]}" --key "$KEY"
mutant "запис з @ зараховується як «пускає»" '        glob_match "$u" "$upart" && maybe+=" $e"' '        glob_match "$u" "$upart" && allowed=1'
setup "$d" "$LINE" "${T_OK/allowusers agent/allowusers agent@203.0.113.9}"
expect_mut "запис з @ зараховується як «пускає»" "$d" "${A[@]}" --key "$KEY"

# ─── Справжній sshd (якщо є): формат -T такий, як у заглушки ─────────────────
real_sshd=/usr/sbin/sshd
if [[ -x "$real_sshd" ]] && id agent >/dev/null 2>&1 && id yurii >/dev/null 2>&1 &&
  "$real_sshd" -T -f /dev/null -C user=agent,host=localhost,addr=127.0.0.1 >/dev/null 2>&1; then
  cfg="$tmp/sshd_config"
  printf '%s\n' 'PasswordAuthentication no' 'KbdInteractiveAuthentication no' 'PermitRootLogin no' \
    'AllowUsers yurii agent' >"$cfg"
  printf '#!/usr/bin/env bash\nexec %s -f %s "$@"\n' "$real_sshd" "$cfg" >"$tmp/sshd-real"
  chmod +x "$tmp/sshd-real"
  setup "$d" "$LINE"
  agent_home="$(getent passwd agent | cut -d: -f6)"
  rc=0
  # Ключів у справжньому home agent не чіпаємо: ключа не задаємо, файли там — чиї є.
  A8_SSHD="$tmp/sshd-real" A8_SSH_ETC="$d/etc" "$SCRIPT" --agent agent --admin yurii >"$tmp/out" 2>&1 || rc=$?
  if [[ "$rc" -eq 0 ]] && grep -qF "agent (агент): ключа a8-ctl не задано" "$tmp/out"; then
    echo "✓ справжній sshd -T: AllowUsers yurii agent, паролі вимкнено (home agent: $agent_home, код $rc)"
  else
    echo "✗ справжній sshd -T: AllowUsers yurii agent мав пройти"
    sed 's/^/    /' "$tmp/out"
    fail=1
  fi
  printf '%s\n' 'PasswordAuthentication no' 'KbdInteractiveAuthentication no' 'PermitRootLogin no' \
    'AllowUsers yurii' >"$cfg"
  rc=0
  A8_SSHD="$tmp/sshd-real" A8_SSH_ETC="$d/etc" "$SCRIPT" --agent agent --admin yurii --key "$KEY" >"$tmp/out" 2>&1 || rc=$?
  if [[ "$rc" -eq 1 ]] && grep -qF "agent (агент): не проходить AllowUsers (yurii)" "$tmp/out"; then
    echo "✓ справжній sshd -T: AllowUsers yurii при заданому ключі → 1 (стан 07.11)"
  else
    echo "✗ справжній sshd -T: AllowUsers yurii мав дати «не проходить AllowUsers (yurii)», код $rc"
    sed 's/^/    /' "$tmp/out"
    fail=1
  fi
else
  echo "· справжнього sshd (або користувачів agent і yurii) немає — прогін на ньому пропущено, лише заглушка"
fi

if [[ "$fail" -eq 0 ]]; then
  echo "a8-ssh-doors: усі сценарії пройдено"
else
  echo "a8-ssh-doors: є падіння" >&2
fi
exit "$fail"
