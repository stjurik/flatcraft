#!/usr/bin/env bash
# agy-call.test.sh — власний тест agy-call.sh. Заглушка agy, без мережі й квот.
#
# Скрипт під тестом береться через AGY_CALL_SH (дефолт — поруч), бо оракул
# приймання підставляє сюди мутанти-обгортки: кожен мусить почервонити цей
# тест. Усі потрібні змінні (AGY, AGY_CALL_LOGS, AGY_CALL_ROOTS) тест
# експортує сам — оракул запускає його з чистим середовищем.
#
# Запуск: tools/scripts/agy-call.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${AGY_CALL_SH:-$HERE/agy-call.sh}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAIL=0

mkdir -p "$TMP/bin" "$TMP/logs" "$TMP/wt/docs/promts/inputs"
git init -q "$TMP/wt"
git -C "$TMP/wt" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init

# Заглушка agy: /usage — один рядок TSV; робочий виклик пише лог у форматі
# справжнього agy (ранній «resolved via default», потім «Propagating …» —
# джерело мітки) і за STUB_SCOPE=1 пише файл поза докладеним — межі мають
# зреагувати.
cat >"$TMP/bin/agy" <<'EOS'
#!/usr/bin/env bash
mkdir -p "$STUB_DIR/calls"
n=$(ls "$STUB_DIR/calls" 2>/dev/null | wc -l)
printf '%s\n' "$@" >"$STUB_DIR/calls/$((n + 1))"
if [ "$1" = "-p" ] && [ "$2" = "/usage" ]; then
  printf 'Gemini Models\tWeekly Limit Remaining\t90%%\t2026-11-01T00:00:00Z\n'
  exit 0
fi
model="" log=""
while [ $# -gt 0 ]; do
  case "$1" in
    --model) model="$2"; shift 2 ;;
    --log-file) log="$2"; shift 2 ;;
    *) shift ;;
  esac
done
case "$model" in
  gemini-3.8-flash-high) label="Gemini 3.8 Flash (High)" ;;
  *) label="Unknown" ;;
esac
{
  echo 'I resolved via default: label="Gemini 3.1 Pro (High)"'
  echo "I Propagating selected model override to backend: label=\"$label\""
} >"$log"
if [ "${STUB_SCOPE:-0}" = 1 ]; then
  echo x >"$STUB_WT/rogue-from-test.txt"
fi
if [ -n "${STUB_APPEND:-}" ]; then
  echo "дописано agy" >>"$STUB_APPEND"
fi
echo "Вердикт: ✅ готово"
EOS
chmod +x "$TMP/bin/agy"

export STUB_DIR="$TMP" STUB_WT="$TMP/wt"
export AGY="$TMP/bin/agy"
export AGY_CALL_LOGS="$TMP/logs"
export AGY_CALL_ROOTS="$TMP"

ctx() { # ctx <ім'я> — створити свіжий файл контексту, надрукувати шлях
  local f="$TMP/wt/docs/promts/inputs/_agy-$1.md"
  printf 'контекст %s\n' "$1" >"$f"
  printf '%s' "$f"
}
calls_n() { ls "$TMP/calls" 2>/dev/null | wc -l | tr -d ' '; }
reset_calls() { rm -rf "$TMP/calls"; }

check() {
  local name="$1" ok="$2"
  if [ "$ok" = 1 ]; then
    echo "✓ $name"
  else
    echo "✗ $name"
    FAIL=1
  fi
}

# 1. Щасливий шлях: rc=0, рівно 4 рядки stdout, рядок журналу є і каже «ok —».
reset_calls
c1="$(ctx happy)"
out="$("$SCRIPT" "$TMP/wt" "$c1" gemini-3.8-flash-high happy1)"
rc=$?
[ "$rc" = 0 ] && ok1=1 || ok1=0
check "happy: rc=0" "$ok1"
[ "$(printf '%s\n' "$out" | wc -l)" = 4 ] && ok2=1 || ok2=0
check "happy: рівно 4 рядки stdout" "$ok2"
row1="$TMP/logs/happy1.row.md"
[ -f "$row1" ] && ok3=1 || ok3=0
check "happy: рядок журналу існує" "$ok3"
if [ -f "$row1" ] && grep -qF 'ok —' "$row1"; then ok4=1; else ok4=0; fi
check "happy: рядок журналу містить «ok —»" "$ok4"

# 2. Відмова ДО виклику agy: поганий виклик (не 4 аргументи) → rc=2, agy не викликано.
reset_calls
c2="$(ctx refuse)"
"$SCRIPT" "$TMP/wt" "$c2" gemini-3.8-flash-high >/dev/null 2>&1
rc=$?
[ "$rc" = 2 ] && ok5=1 || ok5=0
check "відмова: rc=2" "$ok5"
[ "$(calls_n)" = 0 ] && ok6=1 || ok6=0
check "відмова: agy жодного разу не викликано" "$ok6"

# 3. Межі порушено: agy пише файл поза докладеним → rc=3, stdout «межі: ПОРУШЕНО»,
#    у рядку журналу — «межі ПОРУШЕНО».
reset_calls
c3="$(ctx scope)"
out3="$(STUB_SCOPE=1 "$SCRIPT" "$TMP/wt" "$c3" gemini-3.8-flash-high scope1 2>&1)"
rc=$?
rm -f "$TMP/wt/rogue-from-test.txt"
[ "$rc" = 3 ] && ok7=1 || ok7=0
check "межі: rc=3" "$ok7"
if printf '%s\n' "$out3" | grep -qF 'межі: ПОРУШЕНО'; then ok8=1; else ok8=0; fi
check "межі: stdout «межі: ПОРУШЕНО»" "$ok8"
row3="$TMP/logs/scope1.row.md"
if [ -f "$row3" ] && grep -qF 'межі ПОРУШЕНО' "$row3"; then ok9=1; else ok9=0; fi
check "межі: рядок журналу містить «межі ПОРУШЕНО»" "$ok9"

# 4. Межі на не-ASCII шляху (рецензія #307): файл з кириличною назвою брудний ДО
#    виклику, agy дописує в нього → rc=3. Без core.quotePath=false git бере шлях у
#    вісімкові лапки, sha_of бачить MISSING і до, і після — зміна непомітна.
reset_calls
printf 'до\n' >"$TMP/wt/тест.md"
git -C "$TMP/wt" add -- "тест.md" && git -C "$TMP/wt" -c user.name=t -c user.email=t@t commit -q -m cyr
printf 'брудний до виклику\n' >>"$TMP/wt/тест.md"
c4="$(ctx cyr)"
STUB_APPEND="$TMP/wt/тест.md" "$SCRIPT" "$TMP/wt" "$c4" gemini-3.8-flash-high cyr1 >/dev/null 2>&1
rc=$?
git -C "$TMP/wt" checkout -q -- "тест.md"
[ "$rc" = 3 ] && ok10=1 || ok10=0
check "межі: дописування в брудний не-ASCII файл → rc=3" "$ok10"

if [ "$FAIL" = 0 ]; then
  echo "Усі тести пройдено"
  exit 0
else
  echo "ТЕСТИ ЧЕРВОНІ"
  exit 1
fi
