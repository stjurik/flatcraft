#!/usr/bin/env bash
# check-journals.test.sh — оракул журналів на тимчасових git-репо: docs/13 (заголовки з
# бази лишаються), agy-stats.md (лише дописування), помилки виклику, спільне правило;
# мутації — кожне ключове рішення скрипта тримається тестом.
# Справжній репозиторій тест не читає: усе — у тимчасових каталогах.
# Запуск: tools/scripts/check-journals.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${CHECK_JOURNALS_UNDER_TEST:-$HERE/check-journals.sh}"
fail=0
ok() { echo "✓ $1"; }
bad() {
  echo "✗ $1"
  fail=1
  [[ -z "${CHECK_JOURNALS_UNDER_TEST:-}" ]] || exit 1
}

L=docs/13_PROGRESS_LOG.md
J=docs/promts/inputs/agy-stats.md
G="$(mktemp -d)"
M=""
cleanup() { rm -rf "$G" "${M:-}"; }
trap cleanup EXIT
GIT=(git -C "$G" -c user.name=t -c user.email=t@t -c commit.gpgsign=false)

# run <назва> <база> <гілка> <очікуваний exit> [підрядок у виводі]...
run() {
  local name="$1" base="$2" head="$3" want="$4" out rc needle
  shift 4
  out="$(cd "$G" && CHECK_JOURNALS_BASE="$base" CHECK_JOURNALS_HEAD="$head" bash "$SCRIPT" 2>&1)"
  rc=$?
  if [[ $rc != "$want" ]]; then
    bad "$name — очікував exit $want, отримав $rc: $out"
    return
  fi
  for needle in "$@"; do
    [[ "$out" == *"$needle"* ]] || {
      bad "$name — у виводі немає «$needle»: $out"
      return
    }
  done
  ok "$name"
}

# ─── База: журнал прогресу (новий запис — нагорі) і журнал іспиту ───────────
git -C "$G" init -q -b base
mkdir -p "$G/docs/promts/inputs"
cat >"$G/$L" <<'EOF'
# Журнал

## C — третій запис (2026-09-03)

текст C

## B — другий запис (2026-09-02)

текст B

## A — перший запис (2026-09-01)

текст A
EOF
cat >"$G/$J" <<'EOF'
# журнал

> Вердикт: частка викликів із вигадкою **не нижче 50%** — модель іде з ролі.

| Дата | Задача | Модель agy | Вигадок |
| ---- | ------ | ---------- | ------- |
| 2026-09-24 | рецензія #1 | Gemini 3.8 Flash (High) | **0** |
| 2026-09-25 | рецензія #2 | Claude Opus 4.6 (Thinking) | **1** |
EOF
"${GIT[@]}" add -A && "${GIT[@]}" commit -qm base

mk() { # mk <гілка> <від> <файл> <perl-вираз> — нова гілка від <від> з однією правкою
  "${GIT[@]}" switch -q -c "$1" "$2" && perl -0pi -e "$4" "$G/$3" && "${GIT[@]}" commit -qam "$1"
}
NEW_D='s/(# Журнал\n\n)/$1## D — новий запис (2026-09-04)\n\nтекст D\n\n/'
NEW_F='s/(# Журнал\n\n)/$1## F — запис гілки (2026-09-05)\n\nтекст F\n\n/'
NEW_U='s/(# Журнал\n\n)/$1## U — запис main (2026-09-06)\n\nтекст U\n\n/'

# docs/13
mk add-top base "$L" "$NEW_D"
mk drop-oldest base "$L" 's/## A — перший запис \(2026-09-01\)\n\nтекст A\n//'
mk drop-first base "$L" 's/## C — третій запис \(2026-09-03\)\n\nтекст C\n\n//'
mk renamed base "$L" 's/## B — другий запис/## B — другий запис (виправлено)/'
mk body-only base "$L" 's/текст B/текст B, скорочено/'
# Два коміти: перший знищує заголовок, другий нічого не повертає. Порівняння з HEAD~1
# цього не побачило б — потрібен merge-base.
mk two-commits base "$L" 's/## C — третій запис \(2026-09-03\)\n\nтекст C\n\n//'
perl -0pi -e "$NEW_D" "$G/$L" && "${GIT[@]}" commit -qam "two-commits: другий коміт"
# Заголовок, що в базі двічі.
mk dup-base base "$L" 's/\z/\n## A — перший запис (2026-09-01)\n\nдубль\n/'
mk dup-drop dup-base "$L" 's/\n## A — перший запис \(2026-09-01\)\n\nдубль\n//'
"${GIT[@]}" switch -q -c rm-log base && "${GIT[@]}" rm -q "$L" && "${GIT[@]}" commit -qm rm-log
# Сценарій d3acef6: у гілки свій запис нагорі, у main — теж; main змерджили в гілку,
# конфлікт розв'язано однією стороною — запис main зник.
mk up base "$L" "$NEW_U"
mk feat base "$L" "$NEW_F"
"${GIT[@]}" switch -q -c merge-bad feat && "${GIT[@]}" merge -q -s ours up -m "merge-bad: лише своя сторона"
# Те саме, але правильно: збережено обидві сторони.
"${GIT[@]}" switch -q -c merge-good feat && "${GIT[@]}" merge -q --no-commit -s ours up &&
  perl -0pi -e "$NEW_U" "$G/$L" && "${GIT[@]}" commit -qam "merge-good: обидві сторони"
# Файла в базі не було.
"${GIT[@]}" switch -q --orphan nofile-base && "${GIT[@]}" rm -rfq . >/dev/null 2>&1
echo "інше" >"$G/other.txt" && "${GIT[@]}" add -A && "${GIT[@]}" commit -qm nofile-base
"${GIT[@]}" switch -q -c nofile-add nofile-base && mkdir -p "$G/docs" && echo "## X — перший" >"$G/$L" &&
  "${GIT[@]}" add -A && "${GIT[@]}" commit -qm nofile-add

# agy-stats.md
mk st-append base "$J" 's/\z/| 2026-09-29 | рецензія #3 | claude-sonnet-5-5 (окрема сесія) | **0** |\n/'
mk st-realign base "$J" 's/\| 2026-09-24 \|/|   2026-09-24   |/; s/\| Дата \|/|   Дата   |/; s/\z/| 2026-09-29 | рецензія #3 | Gemini 3.8 Flash (High) | **0** |\n/'
mk st-edit base "$J" 's/\*\*1\*\*/**0**/'
mk st-del-row base "$J" 's/\| 2026-09-24 [^\n]*\n//'
mk st-reorder base "$J" 's/(\| 2026-09-24 [^\n]*\n)(\| 2026-09-25 [^\n]*\n)/$2$1/'
"${GIT[@]}" switch -q -c st-rm base && "${GIT[@]}" rm -q "$J" && "${GIT[@]}" commit -qm st-rm
# Рядок без замикаючого `|`: зміна останньої клітинки — теж зміна.
mk st-nopipe-base base "$J" 's/\z/| 2026-09-26 | рецензія #3 | Gemini 3.8 Flash (High) | **1**\n/'
mk st-nopipe-edit st-nopipe-base "$J" 's/\| \*\*1\*\*\n\z/| **0**\n/'
mk st-nopipe-pipe st-nopipe-base "$J" 's/(\| \*\*1\*\*)\n\z/$1 |\n/'
# Підзаголовок третього рівня — не запис журналу (межа перевірки).
mk sub-base base "$L" 's/(текст B\n)/$1\n### B.1 — деталь\n\nдеталь\n/'
mk sub-drop sub-base "$L" 's/\n### B\.1 — деталь\n\nдеталь\n//'
# Обидва журнали зіпсовано одразу.
mk both-bad base "$J" 's/\*\*1\*\*/**0**/'
perl -0pi -e 's/## C — третій запис \(2026-09-03\)\n\nтекст C\n\n//' "$G/$L" && "${GIT[@]}" commit -qam "both-bad: docs/13"

# ─── 1. docs/13: заголовки з бази лишаються ────────────────────────────────
run "docs/13: новий запис нагорі — чисто" base add-top 0 "журнали цілі"
run "docs/13: зник найстарший заголовок — блок з назвою" base drop-oldest 1 "БЛОК" "## A — перший запис (2026-09-01)"
run "docs/13: зник найновіший (перший) заголовок — блок з назвою" base drop-first 1 "## C — третій запис (2026-09-03)"
run "docs/13: заголовок перейменовано — блок" base renamed 1 "## B — другий запис"
run "docs/13: змінено лише текст запису — проходить (межа перевірки)" base body-only 0
run "docs/13: два коміти, перший знищив заголовок — блок (merge-base, не HEAD~1)" base two-commits 1 "## C — третій запис"
run "docs/13: заголовок двічі в базі, в гілці один — блок (повтори рахуються)" dup-base dup-drop 1 "## A — перший запис"
run "docs/13: файл видалено — блок" base rm-log 1 "зник заголовок"
run "docs/13: сценарій d3acef6 — запис main зник при merge — блок з назвою" up merge-bad 1 "## U — запис main (2026-09-06)"
run "docs/13: main змерджено, обидві сторони збережено — чисто" up merge-good 0
run "docs/13: гілка не мерджила main, у main є зайвий запис — чисто" up feat 0
run "docs/13: файла в базі не було — чисто" nofile-base nofile-add 0

# ─── 2. agy-stats.md: лише дописування ─────────────────────────────────────
run "agy-stats: дописано рядок — чисто" base st-append 0
run "agy-stats: перевирівняно старі й дописано — чисто" base st-realign 0
run "agy-stats: змінено старий рядок — блок" base st-edit 1 "БЛОК" "agy-stats.md"
run "agy-stats: видалено старий рядок — блок" base st-del-row 1 "agy-stats.md"
run "agy-stats: переставлено старі рядки — блок" base st-reorder 1 "agy-stats.md"
run "agy-stats: журнал видалено — блок" base st-rm 1 "agy-stats.md"
run "agy-stats: рядок без | у кінці, змінено останню клітинку — блок" st-nopipe-base st-nopipe-edit 1 "agy-stats.md"
run "agy-stats: до рядка дописано замикаючий | — чисто" st-nopipe-base st-nopipe-pipe 0
run "docs/13: зник підзаголовок ### — не блок (рахуються лише ##)" sub-base sub-drop 0
run "обидва журнали зіпсовано — два блоки в одному виводі" base both-bad 1 "agy-stats.md" "## C — третій запис" "порушень — 2"

# ─── 3. Помилки виклику — «не звірено», а не «чисто» ───────────────────────
run "бази немає — exit 2" немає-такої-бази add-top 2 "немає спільного предка"
X="$(mktemp -d)"
cp "$SCRIPT" "$X/check-journals.sh"
out="$(cd "$G" && CHECK_JOURNALS_BASE=base CHECK_JOURNALS_HEAD=add-top bash "$X/check-journals.sh" 2>&1)"
rc=$?
rm -rf "$X"
if [[ $rc == 2 && "$out" == *"немає"*"journal-rules.sh"* ]]; then
  ok "без journal-rules.sh — відмова, exit 2"
else
  bad "без journal-rules.sh — очікував exit 2 і «немає …journal-rules.sh», отримав $rc: $out"
fi

# ─── 4. Правило одне: функція визначена в бібліотеці, обидва скрипти її беруть ──
defs="$(grep -l 'append_only_violated()' "$HERE"/*.sh | grep -vc 'test\.sh$')"
if [[ "$defs" == 1 && -n "$(grep -l 'append_only_violated()' "$HERE/journal-rules.sh")" ]]; then
  ok "append_only_violated визначено один раз — у journal-rules.sh"
else
  bad "append_only_violated визначено в $defs файлах (очікував 1, у journal-rules.sh)"
fi
for s in review-class.sh check-journals.sh; do
  if grep -q 'source "\$LIB"' "$HERE/$s" && grep -q 'journal-rules.sh' "$HERE/$s"; then
    ok "$s підключає journal-rules.sh"
  else
    bad "$s не підключає journal-rules.sh — правило розійшлося б"
  fi
done

# ─── 5. Мутації: кожне ключове рішення тримається тестом ───────────────────
if [[ -z "${CHECK_JOURNALS_UNDER_TEST:-}" && $fail == 0 ]]; then
  M="$(mktemp -d)"
  src="$(<"$SCRIPT")"
  lib="$HERE/journal-rules.sh"
  libsrc="$(<"$lib")"
  n=0
  mutate() { # mutate <назва> <було> <стало> [lib] — «було» мусить стояти рівно раз
    local name="$1" from="$2" to="$3" which="${4:-script}" body rest d="$M/$((++n))"
    body="$src"
    [[ "$which" == lib ]] && body="$libsrc"
    rest="${body#*"$from"}"
    if [[ "$rest" == "$body" || "$rest" == *"$from"* ]]; then
      bad "мутант «$name»: текст не знайдено рівно один раз — мутація застаріла"
      return
    fi
    mkdir -p "$d"
    cp "$SCRIPT" "$d/check-journals.sh"
    cp "$lib" "$d/journal-rules.sh"
    if [[ "$which" == lib ]]; then
      printf '%s\n' "${body/"$from"/"$to"}" >"$d/journal-rules.sh"
    else
      printf '%s\n' "${body/"$from"/"$to"}" >"$d/check-journals.sh"
    fi
    if CHECK_JOURNALS_UNDER_TEST="$d/check-journals.sh" bash "$HERE/$(basename "$0")" >"$d/out" 2>&1; then
      bad "мутант ВИЖИВ: $name"
    else
      ok "мутанта вбито: $name"
    fi
  }
  # Три мутанти з issue #169.
  mutate "порівняння з HEAD~1 замість merge-base" \
    'mb="$(git merge-base "$BASE" "$HEAD_REF" 2>/dev/null)" || {' \
    'mb="$(git rev-parse "$HEAD_REF~1" 2>/dev/null)" || {'
  mutate "перший заголовок пропускається" \
    'old_h="$(headings <<<"$old")"' \
    'old_h="$(headings <<<"$old" | tail -n +2)"'
  mutate "append_only_violated завжди «чисто»" \
    'append_only_violated() {' \
    'append_only_violated() {
  return 1' lib
  # Решта рішень.
  mutate "повтори заголовків не рахуються" 'c[$0]--; else print' 'c[$0]; else print'
  mutate "назва зниклого заголовка не друкується" \
    'violations+=("$PROGRESS_LOG: зник заголовок «$h»")' \
    'violations+=("$PROGRESS_LOG: зник заголовок")'
  mutate "видалений docs/13 — «чисто»" \
    'new="$(git show "$HEAD_REF:$PROGRESS_LOG" 2>/dev/null)" || new=""' \
    'new="$(git show "$HEAD_REF:$PROGRESS_LOG" 2>/dev/null)" || new="$old"'
  mutate "docs/13 не перевіряється" 'if old="$(git show "$mb:$PROGRESS_LOG" 2>/dev/null)"; then' 'if false; then'
  mutate "agy-stats не перевіряється" 'if append_only_violated "$JOURNAL" "$JOURNAL_ROW_RE"; then' 'if false; then'
  mutate "порушення — вихід 0" 'журнал лише доповнюється"
  exit 1' 'журнал лише доповнюється"
  exit 0'
  mutate "без спільного предка — «чисто»" '(у CI потрібен fetch-depth: 0)" >&2
  exit 2' '(у CI потрібен fetch-depth: 0)" >&2
  exit 0'
  mutate "без бібліотеки — не відмова" 'немає $LIB — журнали не звірено" >&2
  exit 2' 'немає $LIB — журнали не звірено" >&2
  exit 0'
  mutate "порядок рядків журналу не звіряється" \
    '[[ "$(head -n "$n" <<<"$new")" == "$old" ]] || return 0' \
    '[[ -z "$(LC_ALL=C comm -23 <(sort <<<"$old") <(sort <<<"$new"))" ]] || return 0' lib
  mutate "вирівнювання таблиці — теж зміна" 'gsub(/^[ \t]+|[ \t]+$/, "", f); ' '' lib
  mutate "остання клітинка без | губиться" 'last = ($NF ~ /^[ \t]*$/) ? NF - 1 : NF;' 'last = NF - 1;' lib
  mutate "заголовок — будь-який ##, не лише другого рівня" "headings() { grep -E '^## ' || true; }" "headings() { grep -E '^##' || true; }"
fi

if [[ $fail == 1 ]]; then
  echo "FAIL"
  exit 1
fi
echo "Усі тести пройдено."
