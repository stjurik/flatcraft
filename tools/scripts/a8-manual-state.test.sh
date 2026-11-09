#!/usr/bin/env bash
# a8-manual-state.test.sh — сценарії для a8-manual-state.sh (#306).
#
# ufw підмінено заглушкою, що друкує заготовлений `ufw status verbose`. Формат
# заготовки — вивід справжнього ufw 0.36.2 (Ubuntu 24.04), знятий 2026-11-09 на
# правилах docs/19 §B.3 і кількох навмисно поганих. Рядки «(v6)» у пісочниці не
# з'являлись (IPv6 вимкнено) — їх форма тут за аналогією, НЕ ВИМІРЯНО.
#
# Запуск: tools/scripts/a8-manual-state.test.sh
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/a8-manual-state.sh"
fail=0
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

HEAD='Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), disabled (routed)
New profiles: skip

To                         Action      From
--                         ------      ----'
LAN='22/tcp                     ALLOW IN    192.0.2.0/24              '
TS='Anywhere on tailscale0     ALLOW IN    Anywhere                  '

setup() { # setup <тека> <вивід ufw status verbose>
  local d="$1"
  rm -rf "$d"
  mkdir -p "$d/bin" "$d/etc/systemd/system/docker.service.d" "$d/etc/ufw" "$d/etc/ssh/sshd_config.d" "$d/etc/sysctl.d"
  printf '%s\n' "$2" >"$d/ufw.out"
  printf '#!/usr/bin/env bash\n[[ "$1 $2" == "status verbose" ]] || exit 9\ncat "%s/ufw.out"\n' "$d" >"$d/bin/ufw"
  printf '#!/usr/bin/env bash\necho "passwordauthentication no"\necho "allowusers yurii"\n' >"$d/bin/sshd"
  chmod +x "$d/bin/"*
  printf '[Service]\nExecStartPost=/usr/sbin/ufw reload\n' >"$d/etc/systemd/system/docker.service.d/ufw-reload.conf"
  printf '%s\n' '# rules.input-after' '# BEGIN A8 DOCKER-USER' '*filter' ':DOCKER-USER - [0:0]' 'COMMIT' '# END A8 DOCKER-USER' >"$d/etc/ufw/after.rules"
}

run() { # run <тека> <режим>
  rc=0
  A8_UFW="$1/bin/ufw" A8_ETC="$1/etc" A8_SSHD="$1/bin/sshd" "$SCRIPT" "$2" >"$tmp/out" 2>&1 || rc=$?
}

expect() { # expect <назва> <код> <підрядок або ""> <тека> [режим]
  local name="$1" want="$2" sub="$3"
  run "$4" "${5:-check}"
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

d="$tmp/d"

setup "$d" "$HEAD
$LAN"
expect "docs/19 §B.3: лише 22/tcp з LAN, drop-in і блок after.rules як в описі → 0" 0 "вхідних дозволів 1: 22/tcp ← 192.0.2.0/24" "$d"
setup "$d" "$HEAD
$LAN
$TS"
expect "дозвіл на інтерфейсі (Anywhere on tailscale0) — не з інтернету, друкується → 0" 0 "Anywhere on tailscale0 ← Anywhere" "$d"
setup "$d" "$HEAD
$LAN
23                         DENY IN     Anywhere                  "
expect "DENY IN з Anywhere — не дозвіл → 0" 0 "вхідних дозволів 1" "$d"

setup "$d" "$HEAD
$LAN
80/tcp                     ALLOW IN    Anywhere                  "
expect "80/tcp ALLOW IN з Anywhere → 1" 1 "«80/tcp ALLOW IN Anywhere» — вхідне з інтернету" "$d"
setup "$d" "$HEAD
2222/tcp                   LIMIT IN    Anywhere                  "
expect "LIMIT IN з Anywhere — теж відчинено → 1" 1 "2222/tcp LIMIT IN Anywhere" "$d"
setup "$d" "$HEAD
$LAN
22/tcp (v6)                ALLOW IN    Anywhere (v6)             "
expect "22/tcp (v6) з Anywhere (v6) → 1" 1 "Anywhere (v6)» — вхідне з інтернету" "$d"
setup "$d" "Status: inactive"
expect "ufw вимкнено → 1" 1 "ufw не увімкнено" "$d"
setup "$d" "${HEAD/deny (incoming)/allow (incoming)}
$LAN"
expect "Default: allow (incoming) → 1" 1 "deny incoming, allow outgoing" "$d"
setup "$d" "$HEAD
$LAN"
printf '#!/usr/bin/env bash\necho "ERROR: You need to be root to run this script" >&2\nexit 1\n' >"$d/bin/ufw"
expect "ufw status не відпрацював → 1" 1 "ufw status verbose не відпрацював" "$d"

setup "$d" "$HEAD
$LAN"
rm "$d/etc/systemd/system/docker.service.d/ufw-reload.conf"
expect "ufw-reload.conf немає → 1" 1 "ufw-reload.conf немає" "$d"
setup "$d" "$HEAD
$LAN"
printf '[Service]\nExecStartPost=/bin/true\n' >"$d/etc/systemd/system/docker.service.d/ufw-reload.conf"
expect "ufw-reload.conf без ufw reload → 1" 1 "без ExecStartPost=… ufw reload" "$d"
setup "$d" "$HEAD
$LAN"
sed -i '/^:DOCKER-USER/d' "$d/etc/ufw/after.rules"
expect "after.rules без :DOCKER-USER - [0:0] → 1" 1 "без блоку «# BEGIN A8 DOCKER-USER»" "$d"
setup "$d" "$HEAD
$LAN"
rm "$d/etc/ufw/after.rules"
expect "after.rules немає → 1" 1 "after.rules немає" "$d"

setup "$d" "$HEAD
$LAN"
printf 'vm.swappiness=10\n' >"$d/etc/sysctl.d/99-a8.conf"
printf 'AllowUsers yurii\n' >"$d/etc/ssh/sshd_config.d/99-hardening.conf"
expect "inventory: ufw, блок after.rules, drop-in'и, sshd, 99-a8.conf — усе в дампі → 0" 0 "vm.swappiness=10" "$d" inventory
for want in "## ufw status verbose" ":DOCKER-USER - [0:0]" "ExecStartPost=/usr/sbin/ufw reload" "AllowUsers yurii" "allowusers yurii" "/etc/sysctl.d/99-a8.conf"; do
  grep -qF -- "$want" "$tmp/out" || { echo "✗ inventory без «$want»"; fail=1; }
done
expect "неправильний режим → 2" 2 "використання" "$d" status

# ─── Мутації ─────────────────────────────────────────────────────────────────
mut() { # mut <назва> <було> <стало> <тека-сценарій> — мутант мусить дати 0 там, де чинний 1
  python3 - "$SCRIPT" "$tmp/mut.sh" "$2" "$3" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src).read()
assert s.count(old) == 1, "фікстура застаріла: " + old[:60]
open(dst, "w").write(s.replace(old, new, 1))
PY
  chmod +x "$tmp/mut.sh"
  local mrc=0
  A8_UFW="$4/bin/ufw" A8_ETC="$4/etc" A8_SSHD="$4/bin/sshd" "$tmp/mut.sh" check >"$tmp/out" 2>&1 || mrc=$?
  if [[ "$mrc" -eq 0 ]]; then echo "✓ мутація «$1» ловиться сценарієм"; else
    echo "✗ мутація «$1»: мутант теж дав $mrc"
    sed 's/^/    /' "$tmp/out"
    fail=1
  fi
}
setup "$d" "$HEAD
80/tcp                     ALLOW IN    Anywhere                  "
mut "Anywhere не відрізняється від LAN" '[[ "$from" == Anywhere || "$from" == "Anywhere (v6)" ]] && [[ "$to" != *" on "* ]]' 'false' "$d"
setup "$d" "$HEAD
2222/tcp                   LIMIT IN    Anywhere                  "
mut "LIMIT IN не рахується" '(ALLOW|LIMIT)\ IN' '(ALLOW)\ IN' "$d"
# Справжній вимкнений ufw рядка Default не друкує — тоді червоніє й він; тут він є,
# щоб сценарій ловив саме перевірку «Status: active».
setup "$d" "${HEAD/Status: active/Status: inactive}"
mut "вимкнений ufw не помічається" "grep -qx 'Status: active' <<<\"\$st\" ||" 'true ||' "$d"

if [[ "$fail" -eq 0 ]]; then
  echo "a8-manual-state: усі сценарії пройдено"
else
  echo "a8-manual-state: є падіння" >&2
fi
exit "$fail"
