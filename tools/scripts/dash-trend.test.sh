#!/usr/bin/env bash
# dash-trend.test.sh — розділ "trend" (ADR-042 §6): коміти ref по тижнях (з
# понеділка 00:00:00 UTC), продукт — apps/|workers/|packages/, решта — процес.
# git — справжній, у тимчасовому репозиторії з комітами на задані дати
# (GIT_AUTHOR_DATE/GIT_COMMITTER_DATE). Сценарії: коміт і apps/, і docs/ — продукт
# (перший файл у git --name-only — НЕ apps/, рецензія на мутант «лише перший файл»);
# тиждень без комітів — нулі, а не пропуск; межа тижня (неділя 23:59:59 UTC /
# понеділок 00:00:00 UTC); weeks_without_product рахує лише в межах вікна;
# last_product_commit шукає по всій історії ref, а не лише у вікні --weeks;
# --ref і --repo; немає ref — відмова; обгортка проходить dash-schema.sh validate.
# Мутації в кінці ламають dash-trend.sh по одному правилу — набір мусить почервоніти.
#
# Запуск: tools/scripts/dash-trend.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${DASH_TREND_UNDER_TEST:-$HERE/dash-trend.sh}"
fail=0
ok() { echo "✓ $1"; }
bad() {
  echo "✗ $1"
  fail=1
  [[ -z "${DASH_TREND_UNDER_TEST:-}" ]] || exit 1
}

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# Ізоляція git від конфігурації машини (хуки, підпис, шаблони).
export HOME="$T/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
mkdir -p "$HOME"

REPO="$T/repo"
git init -q -b main "$REPO"

commit_at() { # commit_at <ISO-час> <повідомлення> <файл1> [файл2 …] — додає/оновлює файли й комітить
  local ts="$1" msg="$2"
  shift 2
  local f
  for f in "$@"; do
    mkdir -p "$REPO/$(dirname "$f")"
    echo "x" >>"$REPO/$f"
  done
  git -C "$REPO" add "$@"
  GIT_AUTHOR_DATE="$ts" GIT_COMMITTER_DATE="$ts" git -C "$REPO" commit -q -m "$msg"
}

# Тиждень 07.09 (Пн): C1 продукт (apps/), C2 процес на межі неділя 23:59:59 UTC —
# мусить лишитись у тому самому тижні, не перейти у наступний.
commit_at 2026-09-07T10:00:00Z "c1 product" apps/a.txt
commit_at 2026-09-13T23:59:59Z "c2 process boundary" docs/x.md

# Тиждень 14.09 (Пн): C3 рівно на межі понеділка 00:00:00 UTC — новий тиждень, продукт.
commit_at 2026-09-14T00:00:00Z "c3 product boundary" workers/w.py

# Тиждень 21.09 — без комітів (перевіряється самим вікном, нижче).

# Тиждень 28.09 (Пн): C4 — multi-file, README.md ПЕРЕД apps/ у git --name-only
# (перевірено окремо), але все одно продукт — ловить мутант «лише перший файл».
commit_at 2026-09-28T09:00:00Z "c4 multi-file product" README.md apps/a2.txt
commit_at 2026-09-29T08:00:00Z "c5 process" docs/y.md

NOW=2026-09-30T12:00:00Z # Ср, поточний тиждень — Пн 28.09.

run() { out="$(bash "$SCRIPT" --repo "$REPO" --ref main --now "$NOW" "$@" 2>&1)"; rc=$?; }

# ─── 1. чотири тижні: значення, нулі на порожньому тижні, межі ────────────────
run --weeks 4
if [[ $rc == 0 ]]; then
  got="$(jq -c '.data.weeks' <<<"$out" 2>/dev/null)"
  want='[{"week_start":"2026-09-07T00:00:00Z","product":1,"process":1},{"week_start":"2026-09-14T00:00:00Z","product":1,"process":0},{"week_start":"2026-09-21T00:00:00Z","product":0,"process":0},{"week_start":"2026-09-28T00:00:00Z","product":1,"process":1}]'
  [[ "$got" == "$want" ]] && ok "4 тижні: значення й нулі на порожньому тижні збігаються" ||
    bad "4 тижні — отримав: $got"
else
  bad "4 тижні — rc=$rc: $out"
fi

if [[ $rc == 0 ]] && echo "$out" | jq -e '
    .status == "ok" and .section == "trend" and .interval_s == 3600 and .origin == "measured"
  ' >/dev/null 2>&1; then
  ok "обгортка: section/interval_s/origin правильні"
else
  bad "обгортка: неочікувані поля: $out"
fi

printf '%s' "$out" >"$T/env.json"
vout="$(bash "$HERE/dash-schema.sh" validate "$T/env.json" 2>&1)"
[[ "$vout" == ok ]] && ok "обгортка проходить dash-schema.sh validate" ||
  bad "validate — $vout"

# ─── 2. last_product_commit — multi-file коміт (apps/ не першим файлом) ───────
c4_sha="$(git -C "$REPO" log --format=%H --grep='^c4 multi-file product$' main)"
if [[ $rc == 0 ]] && echo "$out" | jq -e --arg sha "$c4_sha" '
    .data.last_product_commit.sha == $sha and
    .data.last_product_commit.subject == "c4 multi-file product" and
    .data.last_product_commit.date == "2026-09-28T09:00:00Z"
  ' >/dev/null 2>&1; then
  ok "last_product_commit — multi-file коміт (README.md перед apps/) визнано продуктом"
else
  bad "last_product_commit — очікував c4, отримав: $out"
fi

# ─── 3. weeks_without_product — у межах вікна, зупиняється на непорожньому ────
run --weeks 2 # [21.09 (0), 28.09 (1)]
[[ $rc == 0 && "$(jq -r .data.weeks_without_product <<<"$out")" == 0 ]] &&
  ok "weeks_without_product=0: останній тиждень вікна вже продуктовий" ||
  bad "weeks_without_product (вікно 2) — rc=$rc: $out"

# ─── 4. weeks_without_product — кілька порожніх тижнів підряд ─────────────────
NOW2=2026-10-12T12:00:00Z # Пн; продуктових комітів після 28.09 немає.
out="$(bash "$SCRIPT" --repo "$REPO" --ref main --now "$NOW2" --weeks 3 2>&1)"
rc=$?
if [[ $rc == 0 ]] && echo "$out" | jq -e '
    .data.weeks_without_product == 2 and
    (.data.weeks | map(.week_start) == ["2026-09-28T00:00:00Z","2026-10-05T00:00:00Z","2026-10-12T00:00:00Z"])
  ' >/dev/null 2>&1; then
  ok "weeks_without_product=2: два порожні тижні підряд від поточного назад"
else
  bad "weeks_without_product (вікно 3, NOW2) — rc=$rc: $out"
fi

# ─── 5. last_product_commit — поза вузьким вікном --weeks ─────────────────────
out="$(bash "$SCRIPT" --repo "$REPO" --ref main --now "$NOW2" --weeks 1 2>&1)"
rc=$?
if [[ $rc == 0 ]] && echo "$out" | jq -e '
    (.data.weeks | length) == 1 and .data.weeks[0].product == 0 and
    .data.last_product_commit.subject == "c4 multi-file product"
  ' >/dev/null 2>&1; then
  ok "last_product_commit знаходиться й тоді, коли сам коміт поза вікном --weeks 1"
else
  bad "last_product_commit поза вікном — rc=$rc: $out"
fi

# ─── 6. --ref — лише коміти вказаної гілки ─────────────────────────────────────
git -C "$REPO" branch feature-empty "$(git -C "$REPO" rev-list --max-parents=0 main)"
out="$(bash "$SCRIPT" --repo "$REPO" --ref feature-empty --now "$NOW" --weeks 4 2>&1)"
rc=$?
if [[ $rc == 0 ]] && echo "$out" | jq -e '.data.last_product_commit.subject == "c1 product"' >/dev/null 2>&1; then
  ok "--ref: гілка без пізніших комітів не бачить main"
else
  bad "--ref feature-empty — rc=$rc: $out"
fi

# ─── 6б. правки оркестратора за рецензією Gemini 3.8 Flash (#204), не агента A8 ──
# Дефолт --weeks — 13 тижнів.
out="$(bash "$SCRIPT" --repo "$REPO" --ref main --now "$NOW" 2>&1)"
[[ "$(jq '.data.weeks | length' <<<"$out" 2>/dev/null)" == 13 ]] && ok "без --weeks — 13 тижнів" ||
  bad "без --weeks — очікував 13 тижнів: $out"

# Merge-коміт: рахується один раз, за файлами, які приніс; коміти гілки — не окремо.
R2="$T/repo2"
git init -q -b main "$R2"
c2() { # c2 <ISO-час> <повідомлення> <файл>
  mkdir -p "$R2/$(dirname "$3")" && echo x >>"$R2/$3" && git -C "$R2" add "$3" &&
    GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" git -C "$R2" commit -q -m "$2"
}
c2 2026-09-28T08:00:00Z "base docs" docs/a.md
git -C "$R2" checkout -q -b feat
c2 2026-09-28T09:00:00Z "feat apps" apps/a.txt
c2 2026-09-28T09:30:00Z "feat apps 2" apps/b.txt
git -C "$R2" checkout -q main
GIT_AUTHOR_DATE=2026-09-28T10:00:00Z GIT_COMMITTER_DATE=2026-09-28T10:00:00Z \
  git -C "$R2" merge -q --no-ff -m "merge feat" feat
# Кирилиця в шляху: без core.quotePath=false git бере шлях у лапки.
c2 2026-09-29T08:00:00Z "кирилиця" "apps/документ.txt"
out="$(bash "$SCRIPT" --repo "$R2" --ref main --now "$NOW" --weeks 1 2>&1)"
if echo "$out" | jq -e '.data.weeks == [{"week_start":"2026-09-28T00:00:00Z","product":2,"process":1}]
    and .data.last_product_commit.subject == "кирилиця"' >/dev/null 2>&1; then
  ok "merge — один продуктовий запис; кириличний шлях у apps/ — продукт"
else
  bad "merge/кирилиця — отримав: $out"
fi

# Жодного продуктового коміту — last_product_commit null.
R3="$T/repo3"
git init -q -b main "$R3"
mkdir -p "$R3/docs" && echo x >"$R3/docs/a.md" && git -C "$R3" add docs/a.md &&
  GIT_AUTHOR_DATE=2026-09-28T08:00:00Z GIT_COMMITTER_DATE=2026-09-28T08:00:00Z git -C "$R3" commit -q -m "docs only"
out="$(bash "$SCRIPT" --repo "$R3" --ref main --now "$NOW" --weeks 1 2>&1)"
[[ "$(jq -c '.data.last_product_commit' <<<"$out" 2>/dev/null)" == null ]] &&
  ok "без продуктових комітів — last_product_commit null" ||
  bad "без продуктових комітів — отримав: $out"

# ─── 7. відмови ─────────────────────────────────────────────────────────────────
out="$(bash "$SCRIPT" --repo "$T/немає-репо" --ref main --now "$NOW" 2>&1)"
rc=$?
[[ $rc == 2 ]] && ok "немає git-репозиторію за --repo — exit 2" ||
  bad "немає репозиторію — очікував exit 2, отримав $rc: $out"

out="$(bash "$SCRIPT" --repo "$REPO" --ref no-such-ref --now "$NOW" 2>&1)"
rc=$?
[[ $rc == 2 ]] && ok "немає ref — exit 2" ||
  bad "немає ref — очікував exit 2, отримав $rc: $out"

out="$(bash "$SCRIPT" --repo "$REPO" --ref main --now "$NOW" --weeks 0 2>&1)"
rc=$?
[[ $rc == 2 ]] && ok "--weeks 0 — exit 2" ||
  bad "--weeks 0 — очікував exit 2, отримав $rc: $out"

out="$(bash "$SCRIPT" --repo "$REPO" --ref main --now "не-час" 2>&1)"
rc=$?
[[ $rc == 2 ]] && ok "поганий --now — exit 2" ||
  bad "поганий --now — очікував exit 2, отримав $rc: $out"

# ─── Мутації: кожне правило тримається тестом ──────────────────────────────────
if [[ -z "${DASH_TREND_UNDER_TEST:-}" && $fail == 0 ]]; then
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
    printf '%s\n' "${src/"$from"/"$to"}" >"$d/dash-trend.sh"
    if DASH_TREND_UNDER_TEST="$d/dash-trend.sh" bash "$HERE/$(basename "$0")" >"$d/out" 2>&1; then
      bad "мутант ВИЖИВ: $name"
    else
      ok "мутанта вбито: $name"
    fi
  }

  mutate "продукт — лише за першим файлом коміту" \
    $'  elif [[ -n "$line" && $have_commit == 1 ]]; then\n    case "$line" in\n      apps/* | workers/* | packages/*) is_product=1 ;;\n    esac\n  fi' \
    $'  elif [[ -n "$line" && $have_commit == 1 ]]; then\n    if [[ "$is_product" == 0 && -z "${seen_file:-}" ]]; then\n      case "$line" in\n        apps/* | workers/* | packages/*) is_product=1 ;;\n      esac\n    fi\n    seen_file=1\n  fi'
  mutate "тиждень починається з неділі, не понеділка" \
    'iso_wd=$(((day_index + 3) % 7))' \
    'iso_wd=$(((day_index + 2) % 7))'
  mutate "weeks_without_product не зупиняється на продуктовому тижні" \
    '  ((week_product[$w] > 0)) && break' \
    '  :'
  mutate "last_product_commit обмежено вікном --weeks" \
    '    if ((commit_epoch > last_product_epoch)); then' \
    '    if ((commit_epoch > last_product_epoch)) && ((wk >= first_week_start)); then'
  empty_week_from="$(printf '%s\n' '  weeks_json="$(jq -c --arg ws "$ws" --argjson p "${week_product[$w]}" --argjson pr "${week_process[$w]}" \' '    '"'"'. + [{week_start: $ws, product: $p, process: $pr}]'"'"' <<<"$weeks_json")"')"
  empty_week_to="$(printf '%s\n' '  if ((week_product[$w] > 0 || week_process[$w] > 0)); then' '  weeks_json="$(jq -c --arg ws "$ws" --argjson p "${week_product[$w]}" --argjson pr "${week_process[$w]}" \' '    '"'"'. + [{week_start: $ws, product: $p, process: $pr}]'"'"' <<<"$weeks_json")"' '  fi')"
  mutate "порожній тиждень пропускається, а не нуль" "$empty_week_from" "$empty_week_to"

  mutate "merge рахується без --first-parent" \
    ' --first-parent --diff-merges=first-parent \' \
    ' \'
  mutate "шляхи в лапках (core.quotePath)" \
    '-c core.quotePath=false log' \
    'log'
  mutate "дефолт --weeks не 13" 'WEEKS=13' 'WEEKS=12'
  mutate "sha останнього продуктового не записується" \
    '      last_product_sha="$commit_sha"' \
    '      last_product_sha=""'
  mutate "немає продуктових — не null" \
    '  last_product_json="null"' \
    '  last_product_json="{}"'

  rm -rf "$M"
fi

if [[ "$fail" -eq 1 ]]; then
  echo "FAIL"
  exit 1
fi
echo "Усі тести пройдено."
