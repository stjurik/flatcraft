#!/usr/bin/env bash
# dash-page.test.sh — оракул сторінки пульту (ADR-042 §10): запускає
# tools/dashboard/render.test.js під `node --test` (вбудований у Node 22, нова
# залежність не потрібна) і мутаційно перевіряє три інваріанти чесності даних
# (ADR-042 §3): sectionState не ігнорує вік, sourcesSummary не рахує stale як
# ok, renderSection екранує HTML. Мутант, що вижив, — привід дописати сценарій
# у render.test.js, а не довіряти зеленому прогону без мутацій.
#
# DASH_RENDER_UNDER_TEST у render.test.js — та сама домовленість, що
# <СКРИПТ>_UNDER_TEST у решті tools/scripts/*.test.sh: тести ганяються проти
# файла-мутанта без копіювання самого тестового файлу.
#
# Запуск: tools/scripts/dash-page.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DASH_DIR="$HERE/../dashboard"
RENDER="$DASH_DIR/render.js"
TEST_FILE="$DASH_DIR/render.test.js"

fail=0
ok() { echo "✓ $1"; }
bad() {
  echo "✗ $1"
  fail=1
}

[[ -r "$RENDER" ]] || {
  echo "відмова: немає $RENDER" >&2
  exit 2
}
[[ -r "$TEST_FILE" ]] || {
  echo "відмова: немає $TEST_FILE" >&2
  exit 2
}

out="$(node --test "$TEST_FILE" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]]; then
  ok "render.test.js — усі сценарії пройдено"
else
  bad "render.test.js провалився (exit $rc):"
  echo "$out" >&2
fi

# ─── Мутації render.js: кожен інваріант §3 тримається тестом ───────────────
if [[ $fail -eq 0 ]]; then
  M="$(mktemp -d)"
  trap 'rm -rf "$M"' EXIT
  src="$(<"$RENDER")"
  n=0
  mutate() { # mutate <назва> <було> <стало> — «було» мусить стояти в файлі рівно раз
    local name="$1" from="$2" to="$3" d="$M/$((++n))" rest
    rest="${src#*"$from"}"
    if [[ "$rest" == "$src" || "$rest" == *"$from"* ]]; then
      bad "мутант «$name»: текст не знайдено рівно один раз — мутація застаріла"
      return
    fi
    mkdir -p "$d"
    printf '%s\n' "${src/"$from"/"$to"}" >"$d/render.js"
    if DASH_RENDER_UNDER_TEST="$d/render.js" node --test "$TEST_FILE" >"$d/out" 2>&1; then
      bad "мутант ВИЖИВ: $name"
    else
      ok "мутанта вбито: $name"
    fi
  }

  mutate "sectionState: вік не перевіряється (status ok завжди ok)" \
    'if (isStaleByAge(env, now)) return "stale";' \
    'if (false) return "stale";'

  mutate "sourcesSummary: stale/not_measured рахуються як ok" \
    'if (sectionState(list[i], now) === "ok") ok++;' \
    'if (sectionState(list[i], now) !== "error" && sectionState(list[i], now) !== "missing") ok++;'

  mutate "renderSection: esc() не екранує HTML" \
    "/[&<>\"']/g" \
    '/(?!)/g'

  # Правки оркестратора за рецензією Gemini 3.8 Flash (#203), не агента A8.
  mutate "pageNow: справжній знімок судиться за часом знімка, а не годинника" \
    '    if (example) {
      var snapMs' \
    '    if (true) {
      var snapMs'
  mutate "t5: зелений крок у розділі не ok" \
    'if (state !== "ok" && b === STEP_BADGE.good) b = STEP_BADGE.none;' \
    ''
  mutate "sectionState: невідомий status — ok" \
    'return env.status === "ok" ? "ok" : "error";' \
    'return "ok";'
  mutate "t5: бейдж кроку не рендериться" \
    "var badge = s.label" \
    'var badge = false && s.label'

  # index.html бере «зараз» саме з pageNow (інакше функція тестована, але не викликана).
  grep -q 'DashRender.pageNow(snap.collected_at, example, Date.now())' "$DASH_DIR/index.html" &&
    ok "index.html: «зараз» — через DashRender.pageNow" ||
    bad "index.html не викликає DashRender.pageNow — правило «знімок міг лежати» не діє"

  rm -rf "$M"
fi

if [[ "$fail" -eq 1 ]]; then
  echo "FAIL"
  exit 1
fi
echo "Усі тести пройдено."
