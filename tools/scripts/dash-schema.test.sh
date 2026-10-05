#!/usr/bin/env bash
# dash-schema.test.sh — основа пульту (ADR-042 §2): обгортка, «застарів?», валідація
# проти snapshot.schema.json. Сценарії складено так, щоб кожне визначення мало
# випадок, де правильна і неправильна реалізація розходяться: свіже / рівно на межі
# 3×interval_s / застаріле / годинник у майбутньому; кожне обов'язкове поле відсутнє
# окремо; невідомий status і origin; data не об'єкт; кілька причин одразу; невалідний
# JSON; top-level не об'єкт.
#
# Мутації в кінці ламають dash-schema.sh по одному визначенню — набір мусить
# почервоніти; інакше мутант «вижив» і тест нічого не доводить.
#
# Запуск: tools/scripts/dash-schema.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${DASH_SCHEMA_UNDER_TEST:-$HERE/dash-schema.sh}"
SCHEMA="$HERE/../dashboard/snapshot.schema.json"
fail=0
ok() { echo "✓ $1"; }
bad() {
  echo "✗ $1"
  fail=1
  [[ -z "${DASH_SCHEMA_UNDER_TEST:-}" ]] || exit 1
}

[[ -r "$SCHEMA" ]] || {
  echo "відмова: немає схеми $SCHEMA" >&2
  exit 2
}

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# ─── stale: свіже / межа / застаріле / годинник ────────────────────────────
NOW=2026-09-30T14:00:00Z

expect_stale() { # expect_stale <назва> <collected_at> <interval_s> <очікуваний слово> <очікуваний exit>
  local name="$1" ts="$2" interval="$3" want_word="$4" want_rc="$5" out rc
  out="$(DASH_SCHEMA_FILE="$SCHEMA" bash "$SCRIPT" stale "$ts" "$interval" --now "$NOW" 2>&1)"
  rc=$?
  if [[ "$out" == "$want_word" && "$rc" == "$want_rc" ]]; then
    ok "$name"
  else
    bad "$name — очікував «$want_word» exit $want_rc, отримав «$out» exit $rc"
  fi
}

# interval_s=300 (5 хв) → межа 3× = 900 с.
expect_stale "свіже: вік 300с (< 900с)" 2026-09-30T13:55:00Z 300 fresh 1
expect_stale "рівно на межі 3×: вік 900с — ще свіже" 2026-09-30T13:45:00Z 300 fresh 1
expect_stale "щойно за межею: вік 901с — застаріле" 2026-09-30T13:44:59Z 300 stale 0
expect_stale "сильний оракул: вік 4×interval_s — застаріле" 2026-09-30T13:40:00Z 300 stale 0
expect_stale "годинник: майбутнє на interval_s — ще не «годинник»" 2026-09-30T14:05:00Z 300 fresh 1
expect_stale "годинник: майбутнє більш ніж на interval_s" 2026-09-30T14:05:01Z 300 clock 2

out="$(DASH_SCHEMA_FILE="$SCHEMA" bash "$SCRIPT" stale "не-час" 300 --now "$NOW" 2>&1)"
rc=$?
[[ $rc == 2 && "$out" == *"відмова"* ]] && ok "stale: поганий collected_at — відмова exit 2" ||
  bad "stale: поганий collected_at — очікував відмову exit 2, отримав exit $rc: $out"

out="$(DASH_SCHEMA_FILE="$SCHEMA" bash "$SCRIPT" stale "$NOW" 0 --now "$NOW" 2>&1)"
rc=$?
[[ $rc == 2 && "$out" == *"відмова"* ]] && ok "stale: interval_s=0 — відмова exit 2" ||
  bad "stale: interval_s=0 — очікував відмову exit 2, отримав exit $rc: $out"

# ─── envelope ───────────────────────────────────────────────────────────────
env_out="$(DASH_SCHEMA_FILE="$SCHEMA" bash "$SCRIPT" envelope a8 "A8 зараз" "a8-ro-shell: df" 300 measured ok '{"n":1}' --now "$NOW" 2>&1)"
if [[ "$(jq -c . <<<"$env_out" 2>/dev/null)" == '{"schema_version":1,"section":"a8","title":"A8 зараз","source":"a8-ro-shell: df","collected_at":"2026-09-30T14:00:00Z","interval_s":300,"status":"ok","origin":"measured","data":{"n":1}}' ]]; then
  ok "envelope: друкує обгортку з --now"
else
  bad "envelope: неочікуваний вивід: $env_out"
fi

printf '%s' "$env_out" >"$T/env.json"
vout="$(DASH_SCHEMA_FILE="$SCHEMA" bash "$SCRIPT" validate "$T/env.json" 2>&1)"
vrc=$?
[[ "$vout" == ok && $vrc == 0 ]] && ok "envelope: власний вивід проходить validate" ||
  bad "envelope: власний вивід не пройшов validate: $vout (exit $vrc)"

env_default="$(DASH_SCHEMA_FILE="$SCHEMA" bash "$SCRIPT" envelope a8 t s 60 reading ok '{}' 2>&1)"
coll="$(jq -r .collected_at <<<"$env_default" 2>/dev/null)"
[[ "$coll" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] && ok "envelope: без --now — системний час UTC ISO 8601" ||
  bad "envelope: без --now collected_at не схожий на UTC ISO 8601: $env_default"

out="$(DASH_SCHEMA_FILE="$SCHEMA" bash "$SCRIPT" envelope a8 t s -5 reading ok '{}' --now "$NOW" 2>&1)"
rc=$?
[[ $rc == 2 ]] && ok "envelope: interval_s від'ємний — відмова exit 2" ||
  bad "envelope: interval_s=-5 мав дати відмову exit 2, отримав exit $rc: $out"

out="$(DASH_SCHEMA_FILE="$SCHEMA" bash "$SCRIPT" envelope a8 t s 60 reading ok '[1,2]' --now "$NOW" 2>&1)"
rc=$?
[[ $rc == 2 ]] && ok "envelope: data не об'єкт (масив) — відмова exit 2" ||
  bad "envelope: data=[1,2] мав дати відмову exit 2, отримав exit $rc: $out"

out="$(DASH_SCHEMA_FILE="$SCHEMA" bash "$SCRIPT" envelope a8 t s 60 reading ok 'не json' --now "$NOW" 2>&1)"
rc=$?
[[ $rc == 2 ]] && ok "envelope: data не JSON — відмова exit 2" ||
  bad "envelope: data='не json' мав дати відмову exit 2, отримав exit $rc: $out"

# ─── validate: базова обгортка для мутацій поля ────────────────────────────
base() { # base <jq-вираз>... — валідна обгортка, по черзі пропущена через кожен вираз
  local j='{"schema_version":1,"section":"a8","title":"A8 зараз","source":"src","collected_at":"2026-09-30T14:00:00Z","interval_s":300,"status":"ok","origin":"measured","data":{"n":1}}'
  local expr
  for expr in "$@"; do
    j="$(jq -c "$expr" <<<"$j")"
  done
  printf '%s' "$j"
}

expect_validate() { # expect_validate <назва> <json> <очікуваний вивід> <очікуваний exit>
  local name="$1" json="$2" want="$3" want_rc="$4" out rc
  printf '%s' "$json" >"$T/v.json"
  out="$(DASH_SCHEMA_FILE="$SCHEMA" bash "$SCRIPT" validate "$T/v.json" 2>&1)"
  rc=$?
  if [[ "$out" == "$want" && "$rc" == "$want_rc" ]]; then
    ok "$name"
  else
    bad "$name — очікував «$want» exit $want_rc, отримав «$out» exit $rc"
  fi
}

expect_validate "validate: валідна обгортка — ok" "$(base)" ok 0

for field in schema_version section title source collected_at interval_s status origin data; do
  expect_validate "validate: відсутнє поле «$field»" \
    "$(jq -c "del(.$field)" <<<"$(base)")" "reject $field" 3
done

expect_validate "validate: невідомий status «green»" "$(base '.status = "green"')" "reject status" 3
expect_validate "validate: невідомий origin" "$(base '.origin = "guessed"')" "reject origin" 3
expect_validate "validate: data — масив, не об'єкт" "$(base '.data = [1,2,3]')" "reject data" 3
expect_validate "validate: data — рядок, не об'єкт" "$(base '.data = "x"')" "reject data" 3
expect_validate "validate: schema_version=2" "$(base '.schema_version = 2')" "reject schema_version" 3
expect_validate "validate: schema_version як рядок" "$(base '.schema_version = "1"')" "reject schema_version" 3
expect_validate "validate: interval_s=0" "$(base '.interval_s = 0')" "reject interval_s" 3
expect_validate "validate: interval_s від'ємний" "$(base '.interval_s = -1')" "reject interval_s" 3
expect_validate "validate: interval_s дробовий" "$(base '.interval_s = 1.5')" "reject interval_s" 3
expect_validate "validate: interval_s рядком" "$(base '.interval_s = "300"')" "reject interval_s" 3
expect_validate "validate: collected_at без Z (офсет)" "$(base '.collected_at = "2026-09-30T14:00:00+02:00"')" "reject collected_at" 3
expect_validate "validate: collected_at — не ISO 8601" "$(base '.collected_at = "30.09.2026"')" "reject collected_at" 3
expect_validate "validate: section — порожній рядок" "$(base '.section = ""')" "reject section" 3

# Кілька причин одразу — усі перелічені, не лише перша.
expect_validate "validate: кілька причин одразу" \
  "$(base '.status = "green"' '.origin = "guessed"' 'del(.source)')" \
  "reject source,status,origin" 3

expect_validate "validate: top-level — масив" '[1,2,3]' \
  "reject schema_version,section,title,source,collected_at,interval_s,status,origin,data" 3

printf 'не json' >"$T/badjson.json"
out="$(DASH_SCHEMA_FILE="$SCHEMA" bash "$SCRIPT" validate "$T/badjson.json" 2>&1)"
rc=$?
[[ "$out" == "reject json" && $rc == 3 ]] && ok "validate: невалідний JSON — reject json" ||
  bad "validate: невалідний JSON — очікував «reject json» exit 3, отримав «$out» exit $rc"

out="$(DASH_SCHEMA_FILE="$SCHEMA" bash "$SCRIPT" validate "$T/no-such-file.json" 2>&1)"
rc=$?
[[ $rc == 2 ]] && ok "validate: немає файла — exit 2" ||
  bad "validate: немає файла — очікував exit 2, отримав $rc: $out"

# ─── Мутації: кожне визначення тримається тестом ───────────────────────────
if [[ -z "${DASH_SCHEMA_UNDER_TEST:-}" && $fail == 0 ]]; then
  M="$(mktemp -d)"
  src="$(<"$SCRIPT")"
  n=0
  mutate() { # mutate <назва> <було> <стало> — «було» мусить стояти в скрипті рівно раз
    local name="$1" from="$2" to="$3" d="$M/$((++n))" rest
    rest="${src#*"$from"}"
    if [[ "$rest" == "$src" || "$rest" == *"$from"* ]]; then
      bad "мутант «$name»: текст не знайдено рівно один раз — мутація застаріла"
      return
    fi
    mkdir -p "$d"
    printf '%s\n' "${src/"$from"/"$to"}" >"$d/dash-schema.sh"
    if DASH_SCHEMA_UNDER_TEST="$d/dash-schema.sh" bash "$HERE/$(basename "$0")" >"$d/out" 2>&1; then
      bad "мутант ВИЖИВ: $name"
    else
      ok "мутанта вбито: $name"
    fi
  }

  mutate "stale: множник 3 → 30" \
    'if ((age > 3 * interval_s)); then' \
    'if ((age > 30 * interval_s)); then'
  mutate "stale: межа stale >= замість > (рівно на межі теж stale)" \
    'if ((age > 3 * interval_s)); then' \
    'if ((age >= 3 * interval_s)); then'
  mutate "stale: завжди повертає «свіже»" \
    $'if ((age > 3 * interval_s)); then\n    echo stale\n    return 0\n  fi' \
    $'if ((age > 3 * interval_s)) && false; then\n    echo stale\n    return 0\n  fi'
  mutate "stale: годинник не впізнається (поріг ×10)" \
    'if ((future > interval_s)); then' \
    'if ((future > interval_s * 10)); then'

  mutate "validate: невідомий status приймається" \
    '          (if (($data.status? // null) as $v | $v != null and ($status_enum | index($v)) != null) then empty else "status" end),' \
    '          empty,'
  mutate "validate: невідомий origin приймається" \
    '          (if (($data.origin? // null) as $v | $v != null and ($origin_enum | index($v)) != null) then empty else "origin" end),' \
    '          empty,'
  mutate "validate: data не перевіряється як об'єкт" \
    '          (if ($data.data? | type == "object") then empty else "data" end)' \
    '          empty'
  mutate "validate: schema_version не перевіряється" \
    '          (if ($data.schema_version? == 1) then empty else "schema_version" end),' \
    '          empty,'
  mutate "validate: interval_s не перевіряється" \
    '          (if ($data.interval_s? | type == "number" and . > 0 and (. | floor) == .) then empty else "interval_s" end),' \
    '          empty,'
  mutate "validate: зупиняється на першій причині" \
    '    | if ($bad | length) == 0 then "ok" else "reject " + ($bad | join(",")) end' \
    '    | if ($bad | length) == 0 then "ok" else "reject " + ($bad[0]) end'
  mutate "validate: top-level не об'єкт не ловиться" \
    '(if ($data | type) != "object"' \
    '(if false'
  mutate "validate: невалідний JSON не ловиться" \
    $'  jq -e . "$file" >/dev/null 2>&1 || {\n    echo "reject json"\n    return 3\n  }\n' \
    ''

  rm -rf "$M"
fi

if [[ "$fail" -eq 1 ]]; then
  echo "FAIL"
  exit 1
fi
echo "Усі тести пройдено."
