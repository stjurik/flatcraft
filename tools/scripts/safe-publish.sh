#!/usr/bin/env bash
# safe-publish.sh — публікація лише після check-leak.sh, з незамаскованим кодом виходу.
#
# ЧОМУ ЦЕ ІСНУЄ. 2026-10-01 ланцюжок `check-leak.sh … | tail -1 && gh …` замаскував код
# виходу: пайп повернув код `tail`, тобто 0, і три коміти пройшли попри блок. Блок тоді
# стосувався рядка, що вже лежав у журналі, а не нових. Рішення yurii 2026-10-01
# дослівно: «публікація лише через обгортку, у коміті перевіряються лише додані рядки».
#
# РЕЖИМИ.
#   safe-publish.sh gh <файл-тексту> <pr|issue> <create|edit|comment> [аргументи gh]...
#       Перевіряє файл тексту і всі аргументи (у них заголовок PR — він теж публікація),
#       лише тоді: gh <аргументи> --body-file <файл-тексту>. Текст іде тільки через
#       перевірений файл: --body, --body-file, --fill, --editor, --web, --template
#       обгортка відхиляє; create без --title теж (gh спитав би заголовок у терміналі). `issue edit` не дозволено — оркестратор його не вживає.
#   safe-publish.sh commit <файл-повідомлення>
#       Перевіряє повідомлення і ДОДАНІ рядки індексу (`git diff --cached`), лише тоді
#       git commit -F <файл-повідомлення>. Рядок, що вже був у файлі до коміту, не
#       перевіряється: він уже в історії, і блок на ньому зупиняв би кожен коміт.
#       Коміт злиття (є MERGE_HEAD): перевіряються лише рядки, яких немає в ЖОДНОМУ з
#       батьків (HEAD і кожен MERGE_HEAD) — combined diff, як у push. Diff проти HEAD
#       робив «доданими» всі рядки main, які main перевирівняв (зупинка #178, #222).
#   safe-publish.sh push [remote]
#       Перевіряє все, що push зробить публічним: повідомлення й додані рядки кожного
#       коміту з HEAD, якого ще немає на гілках ЦЬОГО remote (`HEAD --not
#       --remotes=<remote>`): коміт, що є лише на іншому remote, для цього ще не
#       публічний. Перевіряється й назва поточної гілки. Покомітно, а не сумарним diff: адреса, додана й потім видалена,
#       усе одно лишається в історії. Лише тоді git push -u <remote, дефолт origin> HEAD.
#
# Вихід: код check-leak.sh як є (1 — блок, 2 — помилка виклику, 3 — не перевірено), і
# тоді нічого не опубліковано; 2 — помилка виклику обгортки; інакше — код gh чи git.
#
# ЧОГО НЕ ДОВОДИТЬ.
#   - Механічно обгортку ніщо не вмикає: прямий `gh` чи `git push` її обходить.
#   - Межі самого check-leak.sh (його шапка): лише адреси й файл відомої адреси.
#   - Шляхи файлів у diff і бінарні файли не перевіряються — лише додані рядки тексту.
#   - push перевіряє коміти відносно ЛОКАЛЬНИХ копій віддалених гілок: застарілий
#     `git fetch` дає перевірку ширшу, а не вужчу.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/check-leak.sh"

die() {
  echo "safe-publish: $1" >&2
  exit 2
}
usage() {
  die "використання: safe-publish.sh gh <файл> <pr|issue> <create|edit|comment> [аргументи] | commit <файл> | push [remote]"
}

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# Єдине місце, де запускається check-leak. Без пайпа і без `|| true`: код виходу
# check-leak — код обгортки, і далі нічого не виконується.
check() {
  bash "$CHECK" "$@"
  local rc=$?
  if [[ $rc != 0 ]]; then
    echo "safe-publish: check-leak дав $rc — нічого не опубліковано" >&2
    exit "$rc"
  fi
}

# Додані рядки diff з stdin: лише рядки `+` усередині hunk-ів, без заголовків `+++`.
# Стан hunk-а скидається на кожному `diff --git`, тож `+++ b/…` наступного файла не
# потрапляє в текст. Рядок, що в тому самому hunk-у видалено й додано дослівно, — не
# новий: так git показує останній рядок без `\n`, до якого дописали (контрприклад
# Claude Sonnet 5.5, #188). Combined diff merge-коміту (`@@@`, по колонці на батька):
# рядок новий, лише якщо `+` стоїть у КОЖНІЙ колонці, тобто його немає в жодному з
# батьків. Рядок з `+` лише в частині колонок уже є в іншому батьку (#222): гілка
# свого батька перевіряє його власним комітом, а main уже публічний.
added_lines() {
  awk '
    /^diff (--git|--cc|--combined) /{h=0; next}
    /^@@/{h=1; match($0, /^@+/); np=RLENGTH-1; delete gone; next}
    !h{next}
    {pre=substr($0, 1, np); txt=substr($0, np+1)}
    pre ~ /-/ {if (np==1) gone[txt]++; next}
    pre ~ /^\++$/ {if (gone[txt] > 0) {gone[txt]--; next} print txt}'
}

staged_added() {
  local mh tree c parents=()
  mh="$(git rev-parse --git-path MERGE_HEAD)" || return 1
  if [[ -f "$mh" ]]; then
    # Злиття: індекс записується в тимчасовий коміт з усіма батьками і читається тим
    # самим combined diff, що й у push. Коміт не потрапляє в жодну гілку — лише
    # висячий об'єкт, який прибере git gc. Нерозв'язаний конфлікт — write-tree
    # відмовить, і git commit відмовив би так само.
    tree="$(git write-tree)" || return 1
    parents=(-p HEAD)
    while read -r c; do
      [[ -n "$c" ]] && parents+=(-p "$c")
    done <"$mh"
    c="$(GIT_AUTHOR_NAME=safe-publish GIT_AUTHOR_EMAIL=none GIT_COMMITTER_NAME=safe-publish \
      GIT_COMMITTER_EMAIL=none git commit-tree "$tree" "${parents[@]}" -m probe)" || return 1
    git show --no-color --no-ext-diff --no-textconv -U0 --format= --cc "$c" | added_lines
    return
  fi
  git diff --cached --no-color --no-ext-diff --no-textconv -U0 | added_lines
}

# Для кожного неопублікованого коміту — його diff з батьком (перший коміт — з порожнім
# деревом). Merge-коміт — combined diff (`--cc`): лише те, чого немає в жодному з
# батьків. Батьки, яких ще немає на remote, перевіряються самі; ті, що вже є, — уже
# публічні, і merge `origin/main` у гілку не блокується старим рядком main
# (контрприклад Claude Sonnet 5.5, #188).
unpushed_added() {
  local c revs
  revs="$(git rev-list HEAD --not --remotes="$remote")" || return 1
  for c in $revs; do
    git show --no-color --no-ext-diff --no-textconv -U0 --format= --cc "$c" | added_lines || return 1
  done
}

mode="${1:-}"
[[ $# -gt 0 ]] && shift
case "$mode" in
  gh)
    [[ $# -ge 3 ]] || usage
    body="$1"
    shift
    # «-» для gh --body-file і git commit -F — це stdin, а не перевірений файл.
    [[ "$body" != -* ]] || die "файл тексту «$body» схожий на прапорець або stdin — дай шлях"
    case "$1 $2" in
      "pr create" | "pr edit" | "pr comment" | "issue create" | "issue comment") ;;
      *) die "gh $1 $2 — не публікація з переліку (pr create|edit|comment, issue create|comment)" ;;
    esac
    for a in "$@"; do
      case "$a" in
        -b | -b?* | --body | --body=* | -F | -F?* | --body-file | --body-file=* | \
          -f | --fill* | -e | --editor* | -w | --web* | \
          -T | -T?* | --template | --template=* | --recover | --recover=*)
          die "аргумент «$a» передає текст повз перевірений файл — заборонено"
          ;;
        -t?*) ;; # -t<заголовок>: решта — значення заголовка, не прапорці
        -[!-]?*)
          # Кластер коротких прапорців (`-de` = --draft --editor) обходив перелік вище.
          die "кластер коротких прапорців «$a» — пиши кожен прапорець окремо"
          ;;
      esac
    done
    # create без заголовка: gh питає його в терміналі, і введене минає перевірку.
    if [[ "$2" == create ]]; then
      has_title=""
      for a in "$@"; do
        case "$a" in -t | -t?* | --title | --title=*) has_title=1 ;; esac
      done
      [[ -n "$has_title" ]] || die "$1 create без --title — gh спитав би заголовок повз перевірку"
    fi
    printf '%s\n' "$@" >"$T/args"
    check "$body" "$T/args"
    gh "$@" --body-file "$body"
    exit $?
    ;;
  commit)
    [[ $# -eq 1 ]] || usage
    msg="$1"
    [[ "$msg" != -* ]] || die "файл повідомлення «$msg» схожий на прапорець або stdin — дай шлях"
    staged_added >"$T/added" || die "не вдалося зібрати додані рядки індексу (git diff --cached; у злитті — git write-tree: чи розв'язано конфлікт?)"
    check "$msg" "$T/added"
    git commit -F "$msg"
    exit $?
    ;;
  push)
    [[ $# -le 1 ]] || usage
    remote="${1:-origin}"
    git remote get-url "$remote" >/dev/null 2>&1 || die "немає remote «$remote»"
    git rev-list HEAD --not --remotes="$remote" --format=%B >"$T/messages" || die "git rev-list не вдався"
    # Назва гілки теж стає публічною (контрприклад Claude Sonnet 5.5, #188).
    git rev-parse --abbrev-ref HEAD >>"$T/messages" || die "git rev-parse не вдався"
    unpushed_added >"$T/added" || die "git show не вдався"
    check "$T/messages" "$T/added"
    git push -u "$remote" HEAD
    exit $?
    ;;
  *) usage ;;
esac
