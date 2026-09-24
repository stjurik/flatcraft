#!/usr/bin/env bash
# agy-permissions-probe.test.sh — доказ, що зонд робить правильний висновок.
#
# Що СПРАВЖНЄ: сам зонд, його промпти, файли, які він створює, і розбір логу.
# Що ПІДМІНЕНО: agy — заглушка, що поводиться як справжній agy: дозволене
# виконує, заборонене відхиляє тим самим рядком логу, що пише справжній agy
# (`soft-denying tool confirmation "WriteToFile"` / `"RunCommand"`, виміряно
# 2026-09-24). Стани: відкритий конфіг, закритий, закритий із діркою лише в
# «сусідньому» шляху, модель, що не пробувала, і тайм-аут.
#
# Запуск: tools/scripts/agy-permissions-probe.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PROBE="$HERE/agy-permissions-probe.sh"
fail=0
ok() { echo "✓ $1"; }
bad() {
  echo "✗ $1"
  fail=1
}

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
git -C "$T" init -q
mkdir -p "$T/docs/promts/inputs" "$T/bin" "$T/out"

cat >"$T/bin/agy" <<'STUB'
#!/usr/bin/env bash
# Заглушка agy: -p <промпт> --model <m> --log-file <лог>
prompt="$2"; log=""
while (($#)); do [[ "$1" == --log-file ]] && log="$2"; shift; done
echo 'Propagating selected model override to backend: label="Stub"' >"$log"
deny() { echo "I0924 tool_confirmation_manager.go:211] Print mode: soft-denying tool confirmation \"$1\" at step 2" >>"$log"; echo 'jetski: no output produced'; }
[[ "$STUB_MODE" == timeout ]] && exit 124
path() { grep -o "/[^ ]*$1[^ ]*" <<<"$prompt" | head -1; }
if [[ "$prompt" == *read_file* ]]; then
  secret="$(sed -n 's/^Секретне слово: //p' "$(path _agy-probe-read-)")"
  printf '%s\n' "$secret" >"$(path _agy-probe-in-)"
elif [[ "$prompt" == *.agy-probe-home-* ]]; then
  case "$STUB_MODE" in open) echo x >"$(path .agy-probe-home-)" ;; silent | wsilent) : ;; *) deny WriteToFile ;; esac
elif [[ "$prompt" == */tmp/agy-probe-tmp-* ]]; then
  # Правило deny справжній agy не пише в лог — лише помилкою інструмента у відповіді.
  case "$STUB_MODE" in
    open | tmpopen) echo x >"$(path agy-probe-tmp-)" ;;
    silent | wsilent) : ;;
    *) echo "permission check failed for write_file \"$(path agy-probe-tmp-)\". Matches user-configured deny rule." ;;
  esac
elif [[ "$prompt" == *inputs-sibling-* ]]; then
  case "$STUB_MODE" in open | sibopen) echo x >"$(path inputs-sibling-)" ;; silent | wsilent) : ;; *) deny WriteToFile ;; esac
else
  case "$STUB_MODE" in open) ls "$(path agy-probe-ls-)" ;; silent) echo "не буду" ;; *) deny RunCommand ;; esac
fi
STUB
chmod +x "$T/bin/agy"

mkdir -p "$T/home"
probe() { (cd "$T" && HOME="$T/home" STUB_MODE="$1" AGY="$T/bin/agy" PROBE_OUT_DIR="$T/out" bash "$PROBE" 2>&1); }

out="$(probe closed)"
[[ $? == 0 && "$out" == *"звужено"* ]] && ok "закритий конфіг → код 0, «звужено»" || bad "закритий конфіг: $out"

out="$(probe open)"
rc=$?
if [[ $rc == 1 && "$out" == *"WRITE_HOME      ВІДКРИТО"* && "$out" == *"WRITE_TMP       ВІДКРИТО"* && "$out" == *"WRITE_SIBLING   ВІДКРИТО"* && "$out" == *"CMD             ВІДКРИТО"* ]]; then
  ok "відкритий конфіг (контроль) → код 1, усі чотири дірки «ВІДКРИТО»"
else
  bad "відкритий конфіг розпізнано неправильно (rc=$rc): $out"
fi

# Звужений allow без deny для /tmp — саме стан, який зонд знайшов 2026-09-24.
out="$(probe tmpopen)"
[[ $? == 1 && "$out" == *"WRITE_TMP       ВІДКРИТО"* && "$out" == *"WRITE_HOME      заблоковано"* ]] &&
  ok "/tmp відкритий при закритій домашній теці → код 1, видно окремо" ||
  bad "відкритий /tmp не розпізнано: $out"

out="$(probe sibopen)"
[[ $? == 1 && "$out" == *"WRITE_SIBLING   ВІДКРИТО"* && "$out" == *"WRITE_HOME      заблоковано"* ]] &&
  ok "дірка лише в «сусідньому» шляху (рядковий префікс) → код 1, її видно окремо" ||
  bad "«сусідній» шлях не розпізнано: $out"

out="$(probe silent)"
[[ $? == 2 && "$out" == *"не пробувала"* ]] &&
  ok "модель не пробувала → код 2, «висновку немає», а не «заблоковано»" ||
  bad "мовчазна модель дала хибний висновок: $out"

out="$(probe wsilent)"
[[ $? == 2 && "$out" == *"не пробувала"* && "$out" == *"WRITE_HOME      НЕМАЄ ДАНИХ"* ]] &&
  ok "модель не пробувала запис, а команду відхилено → код 2: «немає даних» не зараховується як «заблоковано»" ||
  bad "непроба запису зарахована як блокування: $out"

out="$(probe timeout)"
[[ $? == 2 && "$out" == *"не відповів"* ]] && ok "тайм-аут → код 2, «висновку немає»" || bad "тайм-аут: $out"

leftover="$(find "$T/docs/promts" -name '*probe*' | wc -l)"
[[ "$leftover" == 0 ]] && ok "після зондів у docs/promts/ не лишилось файлів зонду" ||
  bad "лишились файли зонду: $(find "$T/docs/promts" -name '*probe*')"

if ((fail)); then
  echo "Провалено."
  exit 1
fi
echo "Усі тести пройдено."
