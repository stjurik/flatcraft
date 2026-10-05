#!/usr/bin/env bash
# dash-t5.test.sh — розділ "t5" (ADR-042 §6): 8 кроків треку T5 з docs/02_ROADMAP.md,
# "✅" = закрито, номер першого відкритого, data.a8 — not_measured (хвиля 4).
# Сценарії: справжній розділ T5 (steps + first_open); розділ відсутній — error;
# 7 і 9 кроків — error; змінний --roadmap; обгортка проходить dash-schema.sh validate.
# Мутації в кінці ламають dash-t5.sh по одному правилу — набір мусить почервоніти.
#
# Запуск: tools/scripts/dash-t5.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${DASH_T5_UNDER_TEST:-$HERE/dash-t5.sh}"
fail=0
ok() { echo "✓ $1"; }
bad() {
  echo "✗ $1"
  fail=1
  [[ -z "${DASH_T5_UNDER_TEST:-}" ]] || exit 1
}

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
NOW=2026-10-05T12:00:00Z

# ─── фікстура: синтетичний фрагмент docs/02_ROADMAP.md, 8 кроків, 1/3/5 закрито ──
make_roadmap() { # make_roadmap <файл> <кроки…> — кожен крок "N|✅|Назва" або "N||Назва"
  local file="$1"
  shift
  {
    echo "## Треки"
    echo
    echo "### T4. Щось інше"
    echo
    echo "1. Не рахується, бо це не той розділ"
    echo
    echo "### T5. Інфраструктура → автономне середовище розробки (вісім кроків)"
    echo
    echo "Текст-вступ, не нумерований рядок."
    echo
    local spec n mark title
    for spec in "$@"; do
      IFS='|' read -r n mark title <<<"$spec"
      if [[ -n "$mark" ]]; then
        echo "$n. ✅ **$title** (додатковий текст, PR #99)."
      else
        echo "$n. **$title** (додатковий текст)."
      fi
      echo "   - підпункт, що не має рахуватися як крок"
      echo
    done
    echo "## Ритми"
    echo
    echo "1. Не рахується — інший розділ"
  } >"$file"
}

STEPS8=(
  "1|✅|Хвости"
  "2||A8 preflight"
  "3|✅|Інспекція і контракт"
  "4||Генеральний план"
  "5|✅|Середовище на A8"
  "6||Автономія під наглядом"
  "7||Auto-merge оборотного класу"
  "8||Самокерований беклог"
)

make_roadmap "$T/roadmap8.md" "${STEPS8[@]}"

run() { out="$(bash "$SCRIPT" "$@" --now "$NOW" 2>&1)"; rc=$?; }

# ─── 1. справжній розділ: 8 кроків, status ok, first_open, a8 not_measured ─────
run --roadmap "$T/roadmap8.md"
if [[ $rc == 0 ]] && echo "$out" | jq -e '
    .status == "ok" and .section == "t5" and .interval_s == 3600 and .origin == "measured" and
    (.data.steps | length) == 8 and .data.first_open == 2 and
    .data.a8.status == "not_measured" and (.data.a8.reason | length) > 0
  ' >/dev/null 2>&1; then
  ok "8 кроків: status ok, 8 елементів, first_open=2, a8 not_measured"
else
  bad "8 кроків — неочікуваний вивід (rc=$rc): $out"
fi

if [[ $rc == 0 ]] && echo "$out" | jq -e '
    .data.steps[0] == {n: 1, title: "Хвости", closed: true} and
    .data.steps[1] == {n: 2, title: "A8 preflight", closed: false} and
    .data.steps[4] == {n: 5, title: "Середовище на A8", closed: true}
  ' >/dev/null 2>&1; then
  ok "8 кроків: closed рівно на тих, що мають ✅"
else
  bad "8 кроків — closed не збігається з ✅: $out"
fi

printf '%s' "$out" >"$T/env8.json"
vout="$(bash "$HERE/dash-schema.sh" validate "$T/env8.json" 2>&1)"
[[ "$vout" == ok ]] && ok "8 кроків: обгортка проходить dash-schema.sh validate" ||
  bad "8 кроків: validate — $vout"

# ─── 2. справжній docs/02_ROADMAP.md — не порожньо і не error ─────────────────
run
if [[ $rc == 0 ]] && echo "$out" | jq -e '.status == "ok" and (.data.steps | length) == 8' >/dev/null 2>&1; then
  ok "дефолтний docs/02_ROADMAP.md — 8 кроків, status ok"
else
  bad "дефолтний docs/02_ROADMAP.md — $out"
fi

# ─── 3. розділу "### T5." немає — error, а не порожній ok ─────────────────────
cat >"$T/no-t5.md" <<'EOF'
## Треки

### T4. Щось інше

1. Крок T4, не T5
EOF
run --roadmap "$T/no-t5.md"
if [[ $rc == 0 ]] && echo "$out" | jq -e '.status == "error" and (.data.error | length) > 0' >/dev/null 2>&1; then
  ok "немає розділу T5 — status error з поясненням"
else
  bad "немає розділу T5 — очікував error, отримав (rc=$rc): $out"
fi

# ─── 4. 7 кроків — error ───────────────────────────────────────────────────────
make_roadmap "$T/roadmap7.md" "${STEPS8[@]:0:7}"
run --roadmap "$T/roadmap7.md"
if [[ $rc == 0 ]] && echo "$out" | jq -e '.status == "error" and (.data.error | test("7"))' >/dev/null 2>&1; then
  ok "7 кроків — status error, у поясненні число 7"
else
  bad "7 кроків — очікував error з «7», отримав: $out"
fi

# ─── 5. 9 кроків — error ───────────────────────────────────────────────────────
make_roadmap "$T/roadmap9.md" "${STEPS8[@]}" "9||Дев'ятий зайвий крок"
run --roadmap "$T/roadmap9.md"
if [[ $rc == 0 ]] && echo "$out" | jq -e '.status == "error" and (.data.error | test("9"))' >/dev/null 2>&1; then
  ok "9 кроків — status error, у поясненні число 9"
else
  bad "9 кроків — очікував error з «9», отримав: $out"
fi

# ─── 6. усі закриті — first_open null ──────────────────────────────────────────
ALLCLOSED=("1|✅|a" "2|✅|b" "3|✅|c" "4|✅|d" "5|✅|e" "6|✅|f" "7|✅|g" "8|✅|h")
make_roadmap "$T/allclosed.md" "${ALLCLOSED[@]}"
run --roadmap "$T/allclosed.md"
if [[ $rc == 0 ]] && echo "$out" | jq -e '.status == "ok" and .data.first_open == null' >/dev/null 2>&1; then
  ok "усі 8 закриті — first_open: null"
else
  bad "усі закриті — очікував first_open null, отримав: $out"
fi

# ─── 7. --now передається у collected_at ───────────────────────────────────────
run --roadmap "$T/roadmap8.md"
[[ "$(jq -r .collected_at <<<"$out")" == "$NOW" ]] && ok "--now потрапляє у collected_at" ||
  bad "--now не потрапив у collected_at: $out"

# ─── 8. відмови ────────────────────────────────────────────────────────────────
out="$(bash "$SCRIPT" --roadmap "$T/немає-такого.md" --now "$NOW" 2>&1)"
rc=$?
[[ $rc == 2 ]] && ok "немає файла roadmap — exit 2" ||
  bad "немає файла roadmap — очікував exit 2, отримав $rc: $out"

out="$(bash "$SCRIPT" --roadmap "$T/roadmap8.md" --now "$NOW" --дивний 2>&1)"
rc=$?
[[ $rc == 2 ]] && ok "невідомий прапорець — exit 2" ||
  bad "невідомий прапорець — очікував exit 2, отримав $rc: $out"

# ─── Мутації: кожне правило тримається тестом ──────────────────────────────────
if [[ -z "${DASH_T5_UNDER_TEST:-}" && $fail == 0 ]]; then
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
    printf '%s\n' "${src/"$from"/"$to"}" >"$d/dash-t5.sh"
    if DASH_T5_UNDER_TEST="$d/dash-t5.sh" bash "$HERE/$(basename "$0")" >"$d/out" 2>&1; then
      bad "мутант ВИЖИВ: $name"
    else
      ok "мутанта вбито: $name"
    fi
  }

  mutate "✅ ігнорується (closed завжди false)" \
    '      closed=false
      [[ -n "$marker" ]] && closed=true' \
    '      closed=false'
  mutate "лічильник кроків не перевіряється (завжди ok)" \
    'if ((${#lines[@]} != 8)); then' \
    'if ((${#lines[@]} != 8)) && false; then'
  mutate "розділ «T5» не перевіряється на порожність" \
    'if [[ -z "$section" ]]; then' \
    'if false; then'
  mutate "a8 завжди measured, не not_measured" \
    'a8: {status: "not_measured", reason: "потрібен доступ до A8 — хвиля 4"}}' \
    'a8: {status: "measured", reason: "потрібен доступ до A8 — хвиля 4"}}'
  mutate "first_open бере максимум, не мінімум відкритого" \
    'min_by(.n) | .n) // null' \
    'max_by(.n) | .n) // null'
  mutate "секція не зупиняється на наступному заголовку" \
    'on && /^#/ { exit }' \
    'on && /^#####/ { exit }'

  rm -rf "$M"
fi

if [[ "$fail" -eq 1 ]]; then
  echo "FAIL"
  exit 1
fi
echo "Усі тести пройдено."
