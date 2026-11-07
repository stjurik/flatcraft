#!/usr/bin/env bash
# parse-decisions.test.sh — власний тест parse-decisions.sh на синтетичному
# зведенні з відомою відповіддю.
#
# Скрипт під тестом береться через PARSE_DECISIONS_SH (дефолт — поруч), бо
# оракул приймання підставляє сюди обгортки-мутанти: кожна бере справжній
# вивід parse-decisions.sh і псує рівно одне поле (★→choice, merge, прийнято,
# вільний текст, код виходу 4→0 при питанні). Набір нижче мусить почервоніти
# на кожній з них — інакше псування пройшло б непоміченим в оркестраторі.
#
# Запуск: tools/scripts/parse-decisions.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${PARSE_DECISIONS_SH:-$HERE/parse-decisions.sh}"
fail=0
ok() { echo "✓ $1"; }
bad() {
  echo "✗ $1"
  fail=1
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/digest.md" <<'EOS'
# Зведення 2026-11-03

## Чекає на вас
1. Merge #310 — клас A.
   - ★ а) merge одразу
   - б) почекати
2. Що робити з модулем X — клас B.
   - ★ а) залишити
   - б) переробити
   - в) видалити
3. Ручна дія — застосувати конфіг.

## Що йде
4. Задача в роботі.
   - ★ а) не з «Чекає на вас»
EOS

run() { # run <відповідь>
  printf '%s\n' "$1" >"$tmp/reply.txt"
  set +e
  out="$("$SCRIPT" "$tmp/reply.txt" "$tmp/digest.md" 2>"$tmp/err")"
  rc=$?
  set -e
}
j() { jq -cS "$1" <<<"$out"; } # $1 — jq-вираз
expect() { # expect <назва> <jq-вираз> <очікуване>
  local name="$1" expr="$2" want="$3" got
  got="$(j "$expr")"
  if [[ "$got" == "$want" ]]; then ok "$name"; else bad "$name: $expr = $got, очікував $want"; fi
}

# 1. Повна відповідь: рішення, merge, прийнято і вільний текст разом.
run '1★ 2б merge: 310 311 прийнято: 305 — дякую, зроблено'
[[ "$rc" == 0 ]] && ok "повна відповідь: rc=0" || bad "повна відповідь: rc=$rc ($(cat "$tmp/err"))"
expect "decisions: ★ розгортається у варіант «а»" '.decisions' \
  '[{"choice":"а","item":1,"star":true},{"choice":"б","item":2,"star":false}]'
expect "merge: список номерів" '.merge' '[310,311]'
expect "прийнято: список номерів" '.accepted' '[305]'
[[ "$(jq -r .text <<<"$out")" == "дякую, зроблено" ]] && ok "вільний текст після «—»" ||
  bad "вільний текст: $(jq -r .text <<<"$out")"
expect "питань немає" '.questions' '[]'

# 2. Нормалізація телефонних форм дає той самий результат.
run '1* 2Б'
expect "1* = 1★" '.decisions' '[{"choice":"а","item":1,"star":true},{"choice":"б","item":2,"star":false}]'

# 3. Голий номер для пункту без варіантів — дійсна ручна дія.
run '3'
expect "пункт без варіантів: ручна дія" '.decisions' '[{"choice":null,"item":3,"star":false}]'

# 4. Незрозуміле → питання (код 4), жодного здогаду.
run '4★' # пункт 4 — у розділі «Що йде», не «Чекає на вас»
[[ "$rc" == 4 ]] && ok "пункт з іншого розділу → код 4" || bad "код: rc=$rc, очікував 4"
expect "питання є" '[.decisions, .merge, .accepted] | map(length)' '[0,0,0]'
[[ "$(j '.questions | length')" -ge 1 ]] && ok "є хоч одне питання" || bad "questions порожні"

run '2г' # у пункті 2 варіанта «г» немає (є лише а, б, в)
if [[ "$rc" == 4 ]] && [[ "$(j '.decisions')" == '[]' ]]; then ok "неіснуючий варіант → питання"; else
  bad "неіснуючий варіант: rc=$rc, decisions=$(j .decisions)"
fi

run '1б 1а' # пункт названо двічі
if [[ "$rc" == 4 ]] && [[ "$(j '.decisions')" == '[]' ]]; then ok "пункт двічі → питання"; else
  bad "пункт двічі: rc=$rc"
fi

run '2b' # латинська b — не вгадувати
if [[ "$rc" == 4 ]] && grep -q '2b' <<<"$(j '.questions')"; then ok "латинська літера → питання, що цитує токен"; else
  bad "латинська літера: rc=$rc, questions=$(j .questions)"
fi

if [[ "$fail" -eq 0 ]]; then
  echo "Усі тести пройдено."
  exit 0
else
  echo "FAIL"
  exit 1
fi
