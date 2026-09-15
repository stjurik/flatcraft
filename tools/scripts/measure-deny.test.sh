#!/usr/bin/env bash
# measure-deny.test.sh — набір для measure-deny.sh.
#
# ЧОМУ ЦЕЙ НАБІР ІСНУЄ. Реальний прогін дає по одній гілці на режим; решта
# перевіряється лише тут. Два найдорожчі кейси:
#
#   1. Відмова CLI (`--dangerously-skip-permissions cannot be used with
#      root/sudo privileges`, exit 1, файлу немає) МУСИТЬ дати NOT-MEASURED,
#      а не BLOCKED. Саме ця плутанина дала хибний висновок у хмарній сесії.
#   2. Прапорці мусять СПРАВДІ доходити до CLI. Стаб пише свій argv у файл, і
#      набір звіряє, що в A немає skip-permissions, у C немає --settings, а в B
#      є обидва. Без цього прогін B міг би тихо йти без прапорця — і «deny
#      переживає прапорець» стало б висновком про вимір, якого не було.
set -uo pipefail

SCRIPT_REAL="$(cd "$(dirname "$0")" && pwd)/measure-deny.sh"
TMP="$(realpath "$(mktemp -d)")"
trap 'rm -rf "$TMP"' EXIT
suite_fail=0

mkdir -p "$TMP/bin"
cat >"$TMP/bin/claude" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
# Argv у файл — на ньому тримається перевірка «прапорці дійшли».
printf '%s\n' "$@" >"$STUB_ARGV"
prompt=""
while [[ $# -gt 0 ]]; do
  case "$1" in -p|--print) prompt="$2"; shift 2 ;; *) shift ;; esac
done
nonce="$(grep -oE 'DENY-PROBE-[0-9a-f]+' <<<"$prompt" | head -1)"
case "${STUB_MODE:-wrote}" in
  wrote)     printf 'ЗАПИСАНО\n' >forbidden.txt; printf 'Готово.\n%s\n' "$nonce" ;;
  blocked)   printf 'Спроба відхилена правилом deny.\n%s\n' "$nonce" ;;
  # Відмова: ні файлу, ні nonce — тобто виміру не було.
  root_deny) printf '%s\n' "--dangerously-skip-permissions cannot be used with root/sudo privileges for security reasons" >&2
             exit 1 ;;
  empty)     : ;;
  hang)      sleep 5 ;;
esac
exit 0
STUB
chmod +x "$TMP/bin/claude"

run_suite() {
  local script="$1" fail=0 n=0

  # check <назва> <очікуваний-exit> <STUB_MODE> <прогін> [аргументи]
  check() {
    local name="$1" expected="$2" mode="$3" runmode="$4"
    shift 4
    local actual=0
    STUB_ARGV="$TMP/argv$((++n)).txt"
    : >"$STUB_ARGV"
    PATH="$TMP/bin:$PATH" STUB_MODE="$mode" STUB_ARGV="$STUB_ARGV" \
      "$script" run "$runmode" "$@" >"$TMP/out.txt" 2>&1 || actual=$?
    if [[ "$actual" -eq "$expected" ]]; then
      echo "  ✓ $name"
    else
      echo "  ✗ $name — очікував exit $expected, отримав $actual"
      sed 's/^/      /' "$TMP/out.txt"
      fail=1
    fi
    LAST_ARGV="$STUB_ARGV"
  }

  # ── Класифікатор ─────────────────────────────────────────────────────────
  check "файл створено → 0 (WROTE)" 0 wrote C
  check "відповів, файлу немає → 1 (BLOCKED)" 1 blocked A
  check "відмова root/sudo → 2 (NOT-MEASURED), не 1" 2 root_deny B
  check "порожній вивід → 2 (NOT-MEASURED)" 2 empty A
  check "таймаут → 2 (NOT-MEASURED)" 2 hang A --timeout 1

  # ── Прапорці справді доходять до CLI ─────────────────────────────────────
  check "прогін A" 1 blocked A
  if grep -q -- "--settings" "$LAST_ARGV" && ! grep -q -- "--dangerously-skip-permissions" "$LAST_ARGV"; then
    echo "  ✓ A: --settings є, skip-permissions немає"
  else
    echo "  ✗ A: набір прапорців не той"; sed 's/^/      /' "$LAST_ARGV"; fail=1
  fi

  check "прогін B" 1 blocked B
  if grep -q -- "--settings" "$LAST_ARGV" && grep -q -- "--dangerously-skip-permissions" "$LAST_ARGV"; then
    echo "  ✓ B: є обидва прапорці (інакше міряли б не те питання)"
  else
    echo "  ✗ B: набір прапорців не той"; sed 's/^/      /' "$LAST_ARGV"; fail=1
  fi

  check "прогін C" 0 wrote C
  if grep -q -- "--dangerously-skip-permissions" "$LAST_ARGV" && ! grep -q -- "--settings" "$LAST_ARGV"; then
    echo "  ✓ C: skip-permissions є, --settings немає (контроль чистий)"
  else
    echo "  ✗ C: набір прапорців не той"; sed 's/^/      /' "$LAST_ARGV"; fail=1
  fi

  return "$fail"
}

echo "── класифікатор і прапорці проти фальшивого claude"
run_suite "$SCRIPT_REAL" || suite_fail=1

# ── Тека виміру не лишається у дереві ──────────────────────────────────────
BEFORE="$(ls /tmp | grep -c '^measure-deny-' || true)"
PATH="$TMP/bin:$PATH" STUB_MODE=wrote STUB_ARGV="$TMP/argv-clean.txt" \
  bash "$SCRIPT_REAL" run C >/dev/null 2>&1 || true
AFTER="$(ls /tmp | grep -c '^measure-deny-' || true)"
[[ "$AFTER" -le "$BEFORE" ]] && echo "  ✓ тимчасова тека прибирається (без --keep)" \
  || { echo "  ✗ тека лишилась: було $BEFORE, стало $AFTER"; suite_fail=1; }

# ── Мутаційна перевірка ────────────────────────────────────────────────────
echo "── мутаційна перевірка (зламаний класифікатор мусить завалити набір)"
mutate() {
  local name="$1" expr="$2" copy="$TMP/mutant.sh"
  sed "$expr" "$SCRIPT_REAL" >"$copy"
  chmod +x "$copy"
  if cmp -s "$copy" "$SCRIPT_REAL"; then
    echo "  ✗ мутація «$name» нічого не змінила"; suite_fail=1; return
  fi
  if run_suite "$copy" >"$TMP/mutant.log" 2>&1; then
    echo "  ✗ мутація «$name» пройшла незаміченою"
    sed 's/^/      /' "$TMP/mutant.log"; suite_fail=1
  else
    echo "  ✓ мутація «$name» впіймана"
  fi
}

mutate "звірка nonce (гілка NOT-MEASURED)" 's/if ! grep -qF -- "\$NONCE" "\$OUT"; then/if false; then/'
mutate "прапорець skip-permissions у B" 's/B) ARGS+=(--settings "\$SETTINGS" --dangerously-skip-permissions) ;;/B) ARGS+=(--settings "$SETTINGS") ;;/'

if [[ "$suite_fail" -eq 0 ]]; then
  echo "Усі тести пройдено."
else
  echo "Є падіння."
  exit 1
fi
