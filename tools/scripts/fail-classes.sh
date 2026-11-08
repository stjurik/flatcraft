#!/usr/bin/env bash
# fail-classes.sh — лічильник класів помилок і правило трьох (#285, спринт 02.11 S4г).
#
# ЧОМУ ЦЕ ІСНУЄ. CLAUDE.md §0 п.6 (ADR-039 §8): клас помилки, що повторився тричі,
# АВТОМАТИЧНО породжує задачу «змінити процес». Поки лічильник веде людина
# коментарями в #285, і поріг пропускають — випадок 3 класу «код є, запускає його
# ніщо» (install-orchestrator-profile.sh, #285) минув без задачі. Цей скрипт
# рахує самостійно, і третій випадок класу сам публікує issue «Змінити процес».
#
# ДІЄСЛОВА
#   add <клас> <опис> <посилання>     Новий випадок класу: дописує рядок у
#                                      cases.tsv; на N-му (N ≥ 3) випадку класу без
#                                      issue — публікує `issue create`, з issue —
#                                      `issue comment`.
#   count [<клас>]                    Без аргументу — `<клас>\t<N>` для кожного
#                                      класу в порядку реєстру; з аргументом —
#                                      лише число.
#   register <клас> <назва>           Новий клас у реєстр, issue = «-».
#
# РЕЄСТР (TSV, без заголовка, `$FAIL_CLASSES_DIR`, дефолт
# docs/promts/inputs/fail-classes поруч із корінем репо):
#   classes.tsv   <клас>\t<назва класу>\t<номер issue «Змінити процес» або ->
#   cases.tsv     <дата UTC YYYY-MM-DD>\t<клас>\t<опис>\t<посилання>
#
# ПУБЛІКАЦІЯ — лише через $SAFE_PUBLISH (дефолт safe-publish.sh поруч), ніколи
# напряму `gh`: той самий check-leak, що й решта публікацій оркестратора.
# Створення: `$SAFE_PUBLISH gh <тіло> issue create --title "Змінити процес
# (правило трьох): <назва класу>"`. Тіло — таблиця всіх випадків класу з
# посиланнями і розділ «Оракул» з «ЗАПОВНИТИ» (CLAUDE.md §2 п.2: задача без
# оракула не береться в роботу). Номер нового issue береться лише з рядка
# stdout, що весь є URL `^https?://…/issues/<N>$` — інші рядки (наприклад,
# check-leak) можуть містити інші числа. Коментар: `$SAFE_PUBLISH gh <тіло>
# issue comment <issue>` з описом і посиланням нового випадку, без таблиці.
#
# Публікація впала (код safe-publish ≠ 0, або для create — нема рядка-URL з
# номером) → рядок випадку лишається в cases.tsv, реєстр не змінюється, код 3.
# Наступний add того самого класу пробує опублікувати знову — випадків, що вже
# перейшли поріг, це не губить.
#
# LOCK. Увесь виклик (add, register, count) — під flock на
# $FAIL_CLASSES_DIR/.lock (у .gitignore теки): два паралельні треті випадки
# мають дати рівно одне issue, не два.
#
# ЧОГО НЕ РОБИТЬ. Нічого не комітить і не пушить — рядки реєстру лишаються на
# диску, оркестратор комітить їх у своєму PR дня. Нічого не викликає сам: у
# циклі доби його кличе оркестратор (register/add — коли фіксує клас збою; зараз
# це коментар у #285) — без цього виклику скрипт сам стане випадком класу «код
# є, запускає його ніщо».
#
# Виходи: 0 — зроблено; 2 — помилка використання чи дані реєстру; 3 — публікація
# не пройшла (випадок не загублено — див. вище).
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="${FAIL_CLASSES_DIR:-$HERE/../../docs/promts/inputs/fail-classes}"
PUBLISH="${SAFE_PUBLISH:-$HERE/safe-publish.sh}"
CLASSES="$DIR/classes.tsv"
CASES="$DIR/cases.tsv"
LOCKFILE="$DIR/.lock"

die() { # die <пояснення> [<код, дефолт 2>]
  echo "fail-classes: $1" >&2
  exit "${2:-2}"
}
usage() {
  die "використання: fail-classes.sh add <клас> <опис> <посилання> | count [<клас>] | register <клас> <назва>"
}

has_tab_or_nl() { # has_tab_or_nl <текст> — 0, якщо текст має TAB чи \n (псує TSV)
  case "$1" in
    *$'\t'* | *$'\n'*) return 0 ;;
    *) return 1 ;;
  esac
}

verb="${1:-}"
[[ $# -gt 0 ]] && shift

case "$verb" in
  add | count | register) ;;
  *) usage ;;
esac

mkdir -p "$DIR" || die "не вдалося створити $DIR"
exec 9>"$LOCKFILE" || die "не вдалося відкрити $LOCKFILE"
flock -x 9 || die "не вдалося взяти flock на $LOCKFILE"
[[ -f "$CLASSES" ]] || : >"$CLASSES"
[[ -f "$CASES" ]] || : >"$CASES"

T="$(mktemp -d)" || die "не вдалося створити тимчасову теку"
trap 'rm -rf "$T"' EXIT

# class_field <клас> <номер поля> — поле рядка classes.tsv з точним збігом $1.
class_field() {
  awk -F'\t' -v c="$1" -v n="$2" '$1 == c { print $n; exit }' "$CLASSES"
}
class_exists() {
  awk -F'\t' -v c="$1" '$1 == c { f = 1 } END { exit !f }' "$CLASSES"
}

case_count() { # case_count <клас> — число рядків cases.tsv цього класу
  awk -F'\t' -v c="$1" '$2 == c' "$CASES" | wc -l | tr -d ' '
}

do_add() {
  (($# == 3)) || die "add: потрібно рівно 3 аргументи: <клас> <опис> <посилання>"
  local class="$1" desc="$2" link="$3"

  class_exists "$class" || die "add: клас «$class» не зареєстровано (спершу register)"
  [[ -n "$desc" ]] || die "add: опис порожній"
  has_tab_or_nl "$desc" && die "add: опис містить TAB чи перевід рядка"
  case "$link" in
    http://* | https://*) ;;
    *) die "add: посилання має починатись з http:// чи https://" ;;
  esac
  has_tab_or_nl "$link" && die "add: посилання містить TAB чи перевід рядка"

  local class_name class_issue date n
  class_name="$(class_field "$class" 2)"
  class_issue="$(class_field "$class" 3)"
  date="$(date -u +%Y-%m-%d)"

  printf '%s\t%s\t%s\t%s\n' "$date" "$class" "$desc" "$link" >>"$CASES" ||
    die "add: не вдалося дописати cases.tsv"
  n="$(case_count "$class")"
  echo "клас $class: випадків $n"

  ((n >= 3)) || return 0

  if [[ "$class_issue" == "-" ]]; then
    publish_create "$class" "$class_name"
  else
    publish_comment "$class_issue" "$desc" "$link"
  fi
}

# publish_create <клас> <назва класу> — випадок N ≥ 3, у класу ще немає issue.
publish_create() {
  local class="$1" name="$2" body="$T/create-body.md" out new_issue
  {
    echo "Правило трьох (CLAUDE.md §0 п.6, ADR-039 §8): клас помилки «$name» ($class)"
    echo "повторився тричі — ця задача створена автоматично, без участі людини."
    echo
    echo "## Випадки"
    echo
    echo "| Дата | Опис | Посилання |"
    echo "| --- | --- | --- |"
    awk -F'\t' -v c="$class" '$2 == c { printf "| %s | %s | %s |\n", $1, $3, $4 }' "$CASES"
    echo
    echo "## Оракул"
    echo
    echo "ЗАПОВНИТИ"
  } >"$body"

  out="$("$PUBLISH" gh "$body" issue create --title "Змінити процес (правило трьох): $name")"
  local rc=$?
  if ((rc == 0)); then
    new_issue="$(grep -E '^https?://[^[:space:]]+/issues/[0-9]+$' <<<"$out" | tail -n1 | grep -oE '[0-9]+$')"
  fi
  if ((rc != 0)) || [[ -z "${new_issue:-}" ]]; then
    die "add: публікація issue create не пройшла (код $rc)" 3
  fi
  update_class_issue "$class" "$new_issue"
  echo "issue #$new_issue"
}

# publish_comment <issue> <опис> <посилання> — випадок N ≥ 3, у класу вже є issue.
publish_comment() {
  local issue="$1" desc="$2" link="$3" body="$T/comment-body.md"
  printf '%s\n\n%s\n' "$desc" "$link" >"$body"
  "$PUBLISH" gh "$body" issue comment "$issue" >/dev/null
  local rc=$?
  ((rc == 0)) || die "add: публікація issue comment не пройшла (код $rc)" 3
}

update_class_issue() { # update_class_issue <клас> <номер issue>
  local tmp="$T/classes.tsv"
  awk -F'\t' -v OFS='\t' -v c="$1" -v n="$2" '{ if ($1 == c) $3 = n; print }' "$CLASSES" >"$tmp" &&
    mv "$tmp" "$CLASSES"
}

do_count() {
  if (($# == 0)); then
    local class n
    while IFS=$'\t' read -r class _ _; do
      [[ -n "$class" ]] || continue
      n="$(case_count "$class")"
      printf '%s\t%s\n' "$class" "$n"
    done <"$CLASSES"
  elif (($# == 1)); then
    class_exists "$1" || die "count: невідомий клас «$1»"
    case_count "$1"
  else
    die "count: занадто багато аргументів"
  fi
}

do_register() {
  (($# == 2)) || die "register: потрібно рівно 2 аргументи: <клас> <назва>"
  local class="$1" name="$2"
  [[ "$class" =~ ^[a-z0-9-]+$ ]] || die "register: клас «$class» має бути ^[a-z0-9-]+\$"
  ! class_exists "$class" || die "register: клас «$class» уже зареєстровано"
  [[ -n "$name" ]] || die "register: назва порожня"
  has_tab_or_nl "$name" && die "register: назва містить TAB чи перевід рядка"
  printf '%s\t%s\t-\n' "$class" "$name" >>"$CLASSES" || die "register: не вдалося дописати classes.tsv"
}

case "$verb" in
  add) do_add "$@" ;;
  count) do_count "$@" ;;
  register) do_register "$@" ;;
esac
