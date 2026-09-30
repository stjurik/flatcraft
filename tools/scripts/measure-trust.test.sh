#!/usr/bin/env bash
# measure-trust.test.sh — набір для measure-trust.sh.
#
# ЧОМУ ЦЕЙ НАБІР ІСНУЄ. Реальний прогін на A8 зачіпає ОДНУ гілку класифікатора
# з трьох; решта перевіряється лише тут. Найдорожчий кейс — §4: відмова CLI
# (`--dangerously-skip-permissions cannot be used with root/sudo privileges`,
# exit 1) МУСИТЬ дати NOT-MEASURED, а не TRUSTED. Саме ця плутанина вже дала
# хибний висновок у хмарній сесії: «файл не створено» зарахували як «deny
# спрацював», хоча виклику не сталося. Якщо гілку зламають — впаде цей рядок.
#
# Наприкінці — мутаційна перевірка: зламаний впізнавач МУСИТЬ завалити набір.
# Інакше «зелений» нічого не означав би (клас розриву — `docs/16` §1).
set -uo pipefail

SCRIPT_REAL="$(cd "$(dirname "$0")" && pwd)/measure-trust.sh"
TMP="$(realpath "$(mktemp -d)")"
trap 'rm -rf "$TMP"' EXIT
suite_fail=0

# ── Фальшивий claude ───────────────────────────────────────────────────────
# Кожен режим — один реальний спосіб, яким CLI відповідає (або не відповідає).
mkdir -p "$TMP/bin"
cat >"$TMP/bin/claude" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
prompt=""
while [[ $# -gt 0 ]]; do
  case "$1" in -p|--print) prompt="$2"; shift 2 ;; *) shift ;; esac
done
nonce="$(grep -oE 'TRUST-PROBE-[0-9a-f]+' <<<"$prompt" | head -1)"
case "${STUB_MODE:-trusted}" in
  trusted)   printf '%s\n' "$nonce" ;;
  untrusted) printf 'Ignoring 37 permissions.allow entries from .claude/settings.json: this workspace has not been trusted.\n' >&2
             printf '%s\n' "$nonce" ;;
  # Відмова інструмента: рядка Ignoring немає І nonce немає.
  root_deny) printf '%s\n' "--dangerously-skip-permissions cannot be used with root/sudo privileges for security reasons" >&2
             exit 1 ;;
  empty)     : ;;
  hang)      sleep 5 ;;
esac
exit 0
STUB
chmod +x "$TMP/bin/claude"

# ── Пісочниця: фальшивий HOME із ~/.claude.json ────────────────────────────
make_config() {
  local path="$1" body="${2:-}"
  cat >"$path" <<EOF
{
  "numStartups": 12,
  "installMethod": "npm",
  "projects": {$body}
}
EOF
}

run_suite() {
  local script="$1" fail=0 n=0
  local probe_dir="$TMP/probe-dir"
  mkdir -p "$probe_dir"

  # check <назва> <очікуваний-exit> <STUB_MODE> [аргументи]
  check() {
    local name="$1" expected="$2" mode="$3"
    shift 3
    local cfg="$TMP/cfg$((++n)).json" actual=0
    make_config "$cfg"
    HOME="$TMP" CLAUDE_CONFIG="$cfg" PATH="$TMP/bin:$PATH" STUB_MODE="$mode" \
      "$script" probe "$probe_dir" "$@" >"$TMP/out.txt" 2>&1 || actual=$?
    if [[ "$actual" -eq "$expected" ]]; then
      echo "  ✓ $name"
    else
      echo "  ✗ $name — очікував exit $expected, отримав $actual"
      sed 's/^/      /' "$TMP/out.txt"
      fail=1
    fi
    if [[ -n "${EXPECT_RE:-}" ]] && ! grep -qE "$EXPECT_RE" "$TMP/out.txt"; then
      echo "  ✗ $name — у виводі немає «$EXPECT_RE»"
      sed 's/^/      /' "$TMP/out.txt"
      fail=1
    fi
  }

  # 1. Немає рядка Ignoring + nonce повернувся → TRUSTED.
  check "nonce без Ignoring → 0 (TRUSTED)" 0 trusted
  # 2. Рядок є → UNTRUSTED, і число N мусить бути у виводі.
  EXPECT_RE='N=37'
  check "Ignoring 37 → 1 (UNTRUSTED), N розпізнано" 1 untrusted
  unset EXPECT_RE
  # 3. Відмова CLI → NOT-MEASURED. НЕ TRUSTED: рядка Ignoring там теж немає,
  #    і без окремої гілки відмова зарахувалась би як успіх.
  EXPECT_RE='NOT-MEASURED'
  check "відмова root/sudo → 2 (NOT-MEASURED), не 0" 2 root_deny
  unset EXPECT_RE
  # 4. Порожній вивід — теж «невідомо», а не «довірена».
  check "порожній вивід → 2 (NOT-MEASURED)" 2 empty
  # 5. Таймаут — той самий клас.
  check "таймаут → 2 (NOT-MEASURED)" 2 hang --timeout 1

  return "$fail"
}

echo "── класифікатор проти фальшивого claude"
run_suite "$SCRIPT_REAL" || suite_fail=1

# ── Робота з конфігом ──────────────────────────────────────────────────────
echo "── set / show / unset у ~/.claude.json"
CFG="$TMP/cfg-rw.json"
DIR="$TMP/wt-probe"
mkdir -p "$DIR"
ABS="$(realpath "$DIR")"
make_config "$CFG" "\"/some/other/project\": {\"hasTrustDialogAccepted\": true, \"history\": [1,2]}"
rw() { HOME="$TMP" CLAUDE_CONFIG="$CFG" bash "$SCRIPT_REAL" "$@"; }

if rw show "$DIR" >/dev/null 2>&1; then
  echo "  ✗ show на незаписаній теці дав 0 — має бути 1"; suite_fail=1
else
  echo "  ✓ show до запису → ненульовий (базова лінія прогону B)"
fi

rw set "$DIR" >/dev/null 2>&1 || { echo "  ✗ set дав ненульовий код"; suite_fail=1; }
if rw show "$DIR" >/dev/null 2>&1; then
  echo "  ✓ set → show бачить довіру"
else
  echo "  ✗ set не зафіксувався"; suite_fail=1
fi

# Ідемпотентність: другий set не додає другого запису й не падає.
rw set "$DIR" >/dev/null 2>&1 || { echo "  ✗ повторний set впав"; suite_fail=1; }
COUNT="$(python3 -c "
import json,sys
d=json.load(open('$CFG'))
print(sum(1 for k in d['projects'] if k=='$ABS'))
")"
[[ "$COUNT" == "1" ]] && echo "  ✓ set двічі → один запис (ідемпотентність)" \
  || { echo "  ✗ set двічі → записів: $COUNT"; suite_fail=1; }

# Найважливіше для безпеки виміру: чужі ключі недоторкані.
if python3 -c "
import json,sys
d=json.load(open('$CFG'))
assert d['numStartups']==12, d.get('numStartups')
assert d['installMethod']=='npm'
o=d['projects']['/some/other/project']
assert o['hasTrustDialogAccepted'] is True
assert o['history']==[1,2], o
" 2>/dev/null; then
  echo "  ✓ чужі проєкти й корінні ключі збережені"
else
  echo "  ✗ set зіпсував сторонні дані — вимір не має права бути деструктивним"; suite_fail=1
fi

# Бекап мусить існувати: правка живого конфігу без копії неприйнятна.
[[ -f "$CFG.measure-bak" ]] && echo "  ✓ бекап конфігу створено" \
  || { echo "  ✗ бекапу немає"; suite_fail=1; }

rw unset "$DIR" >/dev/null 2>&1 || { echo "  ✗ unset впав"; suite_fail=1; }
if rw show "$DIR" >/dev/null 2>&1; then
  echo "  ✗ після unset show досі бачить довіру"; suite_fail=1
else
  echo "  ✓ unset → базова лінія повернулась"
fi
rw unset "$DIR" >/dev/null 2>&1 && echo "  ✓ unset двічі → 0 (ідемпотентність)" \
  || { echo "  ✗ повторний unset впав"; suite_fail=1; }

# Зіпсований JSON: відмова, а не перезапис.
BROKEN="$TMP/broken.json"
printf '{ це не json' >"$BROKEN"
BEFORE="$(cat "$BROKEN")"
CODE=0
HOME="$TMP" CLAUDE_CONFIG="$BROKEN" bash "$SCRIPT_REAL" set "$DIR" >/dev/null 2>&1 || CODE=$?
[[ "$CODE" -eq 2 && "$(cat "$BROKEN")" == "$BEFORE" ]] \
  && echo "  ✓ зіпсований JSON → 2, файл не переписано" \
  || { echo "  ✗ зіпсований JSON → код $CODE або файл змінено"; suite_fail=1; }

# Відсутній конфіг не створюємо: це сховало б «Claude тут не запускався».
ABSENT="$TMP/absent.json"
CODE=0
HOME="$TMP" CLAUDE_CONFIG="$ABSENT" bash "$SCRIPT_REAL" set "$DIR" >/dev/null 2>&1 || CODE=$?
[[ "$CODE" -eq 2 && ! -e "$ABSENT" ]] \
  && echo "  ✓ немає конфігу → 2, файл не створюється" \
  || { echo "  ✗ немає конфігу → код $CODE або файл створено"; suite_fail=1; }

# ── Мутаційна перевірка ────────────────────────────────────────────────────
echo "── мутаційна перевірка (зламаний класифікатор мусить завалити набір)"
mutate() {
  local name="$1" expr="$2" copy="$TMP/mutant.sh"
  sed "$expr" "$SCRIPT_REAL" >"$copy"
  chmod +x "$copy"
  if cmp -s "$copy" "$SCRIPT_REAL"; then
    echo "  ✗ мутація «$name» нічого не змінила — вираз більше не влучає у код"
    suite_fail=1; return
  fi
  if run_suite "$copy" >"$TMP/mutant.log" 2>&1; then
    echo "  ✗ мутація «$name» пройшла незаміченою — гілка не перевіряється"
    sed 's/^/      /' "$TMP/mutant.log"
    suite_fail=1
  else
    echo "  ✓ мутація «$name» впіймана"
  fi
}

mutate "впізнавач Ignoring" 's/Ignoring \[0-9\]+ permissions/ЦЕ-НІКОЛИ-НЕ-ЗБІГАЄТЬСЯ/'
mutate "звірка nonce (гілка NOT-MEASURED)" 's/if ! grep -qF -- "\$NONCE" "\$OUT"; then/if false; then/'

if [[ "$suite_fail" -eq 0 ]]; then
  echo "Усі тести пройдено."
else
  echo "Є падіння."
  exit 1
fi
