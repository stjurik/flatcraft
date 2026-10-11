#!/usr/bin/env bash
# journal-rules.sh — правило «журнал лише дописується», ОДНЕ на два скрипти:
# review-class.sh (там воно лише КЛАСИФІКУЄ PR як ризиковий) і check-journals.sh (там
# воно БЛОКУЄ merge). Правило не копіюється: дві копії розійшлися б, і PR, який один
# скрипт вважає чистим, інший би блокував (issue #169).
#
# Підключається через `source`, сам нічого не виконує. Той, хто підключає, до першого
# виклику append_only_violated задає BASE і HEAD_REF — git-посилання бази й гілки.
# Опори правила — JOURNAL, QUOTA і регекси їхніх рядків — теж тут.
#
# ЖУРНАЛ — АРХІВ І ТЕКА (рішення yurii 2026-10-11, #228). Спільний agy-stats.md давав
# конфлікт між будь-якими двома PR, тож нові рядки пишуться в окремий файл на PR:
# `docs/promts/inputs/agy-stats/<гілка, де «/» → «-»>.md`, напр. гілка feat/journal-per-pr →
# `agy-stats/feat-journal-per-pr.md`. Файл теки — лише шапка таблиці (та сама, що в
# архіві, слово в слово), роздільник і рядки викликів. agy-stats.md лишається архівом і
# рахується далі. Хто читає журнал (agy-stats-summary.sh, agy-opus-budget.sh), бере рядки
# з journal_rows — одне місце, де вирішено, які файли і в якому порядку. Від цього порядку
# залежить, які виклики йдуть в іспит, — ще одна причина, чому правка файла ризикова.
# Файл — механізм рецензії: його ослаблення має проходити з двома рецензіями (див.
# `tools/scripts/review-class.sh`, категорія «дозволи й безпека»).

JOURNAL='docs/promts/inputs/agy-stats.md'
JOURNAL_DIR='docs/promts/inputs/agy-stats'
QUOTA='docs/promts/inputs/agy-quota.md'
JOURNAL_ROW_RE='^\|[0-9]{4}-[0-9]{2}-[0-9]{2}\|'
QUOTA_ROW_RE='^\|[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}\|'

# Зміст рядка без вирівнювання: клітинки таблиці обрізані від пробілів, роздільник
# таблиці пропущено, у решті рядків — лише хвостові пробіли. `\|` — символ у клітинці.
# Рядок без замикаючого `|` (GFM це дозволяє) теж має останню клітинку: без неї зміна
# в ній була б невидима (знахідка Flash, рецензія #173).
journal_norm() {
  sed 's/\\|/\x1f/g' | awk -F'|' '
    /^\|[ \t:-]*-[ \t:|-]*$/ { next }
    /^\|/ { last = ($NF ~ /^[ \t]*$/) ? NF - 1 : NF; out = ""; for (i = 2; i <= last; i++) { f = $i; gsub(/^[ \t]+|[ \t]+$/, "", f); out = out "|" f } print out; next }
    { sub(/[ \t]+$/, ""); if ($0 != "") print }'
}
# append_only_violated <файл> <регекс нового рядка> — 0: старий зміст змінено,
# переставлено чи видалено, дописано щось, крім рядків за регексом у кінці, або
# звірити не вдалось; 1 — лише дописано такі рядки в кінець (або нічого не змінено).
append_only_violated() {
  local file="$1" row_re="$2" mb old new rest n
  mb="$(git merge-base "$BASE" "$HEAD_REF" 2>/dev/null)" || return 0
  old="$(git show "$mb:$file" 2>/dev/null)" || return 1 # файла в базі не було — усе дописано
  new="$(git show "$HEAD_REF:$file" 2>/dev/null)" || return 0 # файл видалено
  old="$(journal_norm <<<"$old")"
  new="$(journal_norm <<<"$new")"
  [[ "$new" == "$old" ]] && return 1
  # Старий зміст — дослівний префікс нового: порядок і розташування теж звіряються.
  # Через head/tail і просте порівняння: шаблон `"$old"*` на журналі в 300 КБ — 16 с.
  n="$(wc -l <<<"$old")"
  [[ "$(head -n "$n" <<<"$new")" == "$old" ]] || return 0
  rest="$(tail -n +"$((n + 1))" <<<"$new")"
  [[ -z "$(grep -Ev -- "$row_re" <<<"$rest")" ]] && return 1
  return 0
}

# Ім'я файла теки: лише латиниця, цифри, «.», «_», «-» (гілка, де «/» → «-»), і `.md`.
# Ім'я з переводом рядка чи пробілом розірвало б перелік файлів (контрприклад 3д, #230).
JOURNAL_NAME_RE='^[A-Za-z0-9._-]+\.md$'
# Рядок, схожий на рядок виклику, як би його не вирівняли. Порівнюється з тим, скільки
# рядків прочитав journal_rows: рядок `|2026-10-11|…` без пробілу читач мовчки пропускає
# (контрприклад 3а, #230), і лише різниця кількостей його видає.
JOURNAL_LOOSE_ROW_RE='^[[:space:]]*\|[[:space:]]*[0-9]{4}-[0-9]{2}-[0-9]{2}'
# Тека з цим файлом: тут же agy-stats-summary.sh і agy-opus-budget.sh (journal_unreadable_at).
JOURNAL_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ПОРЯДОК ІСПИТУ («перші 10 викликів моделі» — CLAUDE.md §0 п.2) = порядок, у якому рядки
# потрапили в main, як було з єдиним файлом, куди лише дописують у кінець (контрприклад
# п.4, #230: ключ за датою давав новому файлу з ранньою датою стати перед рядками архіву
# і переписати вже винесений вердикт). Звідси три правила:
#   1. Архів — перший, у порядку рядків файла.
#   2. Файли теки — за комітом першого батька main, що ДОДАВ файл (раніше доданий —
#      раніше; один коміт — за іменем, LC_ALL=C); файли, яких на merge-base з main ще
#      немає (свій PR), — після всіх, за іменем. У файлі — за номером рядка.
#   3. Файл, що вже є в базі, не змінюється, а архів не змінюється, щойно в базі є хоч
#      один файл теки (journal_archive_violated, journal_dir_file_violated): дописаний
#      туди рядок став би ПЕРЕД рядками пізніших файлів. Новий рядок — лише в новий файл.
# Порядок файлів береться з історії git, тож потрібна повна історія. Мілкий клон чи тека
# поза git при ≥2 файлах — відмова з причиною, а не тихо інший порядок.

# journal_archive_violated — архів у HEAD_REF проти merge-base(BASE, HEAD_REF): 0, якщо
# порушено «лише дописування» або архів змінено, коли в базі вже є файли теки.
journal_archive_violated() {
  local archbase before after
  append_only_violated "$JOURNAL" "$JOURNAL_ROW_RE" && return 0
  archbase="$(git merge-base "$BASE" "$HEAD_REF" 2>/dev/null)" || return 0
  [[ -n "$(git ls-tree -r --name-only "$archbase" -- "$JOURNAL_DIR/" 2>/dev/null)" ]] || return 1
  before="$(git show "$archbase:$JOURNAL" 2>/dev/null)" || return 1
  after="$(git show "$HEAD_REF:$JOURNAL" 2>/dev/null)" || return 0
  [[ "$(journal_norm <<<"$before")" != "$(journal_norm <<<"$after")" ]]
}

# journal_dir_file_violated <файл теки> — правило для файла в $JOURNAL_DIR (review-class.sh і
# check-journals.sh). 0 — порушення: файл не верхнього рівня, не .md чи з іменем поза
# JOURNAL_NAME_RE (підрахунок такого не читає чи не може прочитати); файл був у базі і
# змінився (правило 3 порядку вище; перевирівняння таблиці зміною не вважається) чи
# видалений; новий файл не того формату (new_journal_file_violated); звірити не вдалося.
# 1 — чисто.
journal_dir_file_violated() {
  local file="$1" fork was now
  [[ "$file" == "$JOURNAL_DIR"/* && "${file#"$JOURNAL_DIR"/}" =~ $JOURNAL_NAME_RE ]] || return 0
  fork="$(git merge-base "$BASE" "$HEAD_REF" 2>/dev/null)" || return 0
  if was="$(git show "$fork:$file" 2>/dev/null)"; then
    now="$(git show "$HEAD_REF:$file" 2>/dev/null)" || return 0
    [[ "$(journal_norm <<<"$was")" == "$(journal_norm <<<"$now")" ]] && return 1
    return 0
  fi
  new_journal_file_violated "$file"
}

# new_journal_file_violated <файл> — новий файл теки в HEAD_REF. 1 (чисто) — лише якщо
# сирі рядки такі, які прийме читач (journal_rows), без нормалізації (контрприклади 3а, 3б,
# #230): перший — шапка `| Дата …|` (з `|` в кінці), що після journal_norm слово в слово
# збігається з шапкою архіву в HEAD_REF; другий — роздільник таблиці; решта — рядки
# `| РРРР-ММ-ДД …` за тим самим шаблоном, що в journal_rows. Інакше 0. Зміст клітинок
# (число вигадок, кількість клітинок) так не звірити — його звіряє journal_unreadable_at,
# проганяючи самі лічильники.
new_journal_file_violated() {
  local file="$1" body want first second line sep_re=$'^\\|[ \t:-]*-[ \t:|-]*$'
  body="$(git show "$HEAD_REF:$file" 2>/dev/null)" || return 0
  # Без пайпа в grep -m1: під pipefail ранній вихід grep дав би SIGPIPE awk-у на журналі в
  # 300 КБ — і «відмову» на правильному файлі.
  want="$(git show "$HEAD_REF:$JOURNAL" 2>/dev/null)" || return 0
  want="$(journal_norm <<<"$want")"
  want="$(grep -E '^\|Дата\|' <<<"$want" | head -n 1 || true)"
  [[ -n "$want" ]] || return 0
  first="$(sed -n 1p <<<"$body")"
  second="$(sed -n 2p <<<"$body")"
  [[ "$first" =~ ^\|\ Дата\  && "$first" =~ \|[[:space:]]*$ ]] || return 0
  [[ "$(journal_norm <<<"$first")" == "$want" ]] || return 0
  [[ "$second" =~ $sep_re ]] || return 0
  while IFS= read -r line; do
    [[ "$line" =~ ^\|\ [0-9]{4}-[0-9]{2}-[0-9]{2}\  ]] || return 0
  done < <(tail -n +3 <<<"$body")
  return 1
}

# journal_unreadable_at <ревізія> — чи прочитають журнал ревізії (архів + тека) самі
# лічильники. 0 і причина в stdout — ні: agy-stats-summary.sh чи agy-opus-budget.sh вийшли
# не з 0 (чужа шапка, зсунуті клітинки, рядок без числа вигадок — контрприклади 3б, 3в, 3г,
# #230), або рядків, схожих на рядки викликів, більше, ніж прочитав journal_rows (3а). 1 —
# прочитають. Журнал ревізії розкладається в тимчасову теку; порядок файлів лічильник бере
# з історії цього репо (JOURNAL_REPO, JOURNAL_REV, JOURNAL_BASE = BASE).
journal_unreadable_at() {
  local rev="$1" t repo f n loose got why=()
  repo="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "не git-репозиторій"
    return 0
  }
  t="$(mktemp -d)"
  if ! git show "$rev:$JOURNAL" >"$t/agy-stats.md" 2>/dev/null; then
    rm -rf "$t"
    echo "немає архіву $JOURNAL"
    return 0
  fi
  mkdir -p "$t/agy-stats"
  while IFS= read -r -d '' f; do
    n="${f#"$JOURNAL_DIR"/}"
    [[ "$n" =~ $JOURNAL_NAME_RE ]] || continue # ім'я — окреме порушення (journal_dir_file_violated)
    git show "$rev:$f" >"$t/agy-stats/$n"
  done < <(git ls-tree -r -z --name-only "$rev" -- "$JOURNAL_DIR/")
  JOURNAL_REPO="$repo" JOURNAL_REV="$rev" JOURNAL_BASE="$BASE" \
    bash "$JOURNAL_LIB_DIR/agy-stats-summary.sh" "$t/agy-stats.md" >"$t/summary.out" 2>&1 ||
    why+=("agy-stats-summary.sh: $(grep -m1 'відмова' "$t/summary.out" || tail -n 1 "$t/summary.out")")
  AGY_QUOTA_FILE="$t/немає-показів.md" bash "$JOURNAL_LIB_DIR/agy-opus-budget.sh" "$t/agy-stats.md" >"$t/budget.out" 2>&1 ||
    why+=("agy-opus-budget.sh: $(grep -m1 'відмова' "$t/budget.out" || tail -n 1 "$t/budget.out")")
  loose="$(cat "$t/agy-stats.md" "$t"/agy-stats/*.md 2>/dev/null | grep -cE -- "$JOURNAL_LOOSE_ROW_RE" || true)"
  got="$(journal_rows "$t/agy-stats.md" unordered 2>/dev/null | wc -l || true)"
  ((loose == got)) || why+=("рядків викликів $loose, а прочитано $got — рядок не за шаблоном «| РРРР-ММ-ДД |» читач мовчки пропускає")
  rm -rf "$t"
  ((${#why[@]})) || return 1
  printf '%s; ' "${why[@]}"
  echo
  return 0
}

# journal_order <тека> <ім'я>... — імена файлів теки в порядку іспиту (правило 2 вище).
# Репо — JOURNAL_REPO або те, де лежить тека; ревізія — JOURNAL_REV (дефолт HEAD); база —
# JOURNAL_BASE (дефолт origin/main; немає такої — сама ревізія). Вихід 2 з причиною в stderr.
journal_order() {
  local dir="$1" repo rel top rev="${JOURNAL_REV:-HEAD}" base="${JOURNAL_BASE:-origin/main}" fork n c
  shift
  local -A arrived=()
  _jo_refuse() { echo "відмова: порядок файлів теки $dir не визначити — $1" >&2; }
  if [[ -n "${JOURNAL_REPO:-}" ]]; then
    repo="$JOURNAL_REPO"
    rel="$JOURNAL_DIR"
  else
    repo="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || {
      _jo_refuse "тека не в git-репозиторії, а порядок береться з історії git (коміт, що додав файл)"
      return 2
    }
    top="$(cd "$repo" && pwd -P)"
    rel="$(cd "$dir" && pwd -P)"
    rel="${rel#"$top"/}"
  fi
  [[ "$(git -C "$repo" rev-parse --is-shallow-repository 2>/dev/null)" == false ]] || {
    _jo_refuse "мілкий клон: коміт, що додав файл, поза історією (потрібен fetch-depth: 0)"
    return 2
  }
  git -C "$repo" rev-parse -q --verify "$base^{commit}" >/dev/null || base="$rev"
  fork="$(git -C "$repo" merge-base "$base" "$rev" 2>/dev/null)" || {
    _jo_refuse "немає спільного предка $base і $rev"
    return 2
  }
  # Коміти першого батька від найстаршого; для злиття — diff з першим батьком. Ім'я, додане
  # кілька разів (видалено й додано знову), — за ОСТАННІМ додаванням: файл у базі прийшов тоді.
  while IFS=$'\t' read -r c n; do
    arrived[$n]="$c"
  done < <(git -C "$repo" log --first-parent --reverse --diff-merges=first-parent --no-renames \
    --diff-filter=A --name-only --format='%x01' "$fork" -- "$rel/" |
    awk -v rel="$rel/" '$0 == "\001" { c++; next } index($0, rel) == 1 { n = substr($0, length(rel) + 1); if (n !~ /\//) print c "\t" n }')
  # Спершу — чи є файл у базі: ім'я, колись додане й видалене, в історії є, але новий файл
  # PR з тим самим іменем мусить стати в кінець, а не на місце старого (рецензія Flash, #230).
  for n in "$@"; do
    if ! git -C "$repo" cat-file -e "$fork:$rel/$n" 2>/dev/null; then
      printf '1\t0\t%s\n' "$n"
    elif [[ -n "${arrived[$n]:-}" ]]; then
      printf '0\t%010d\t%s\n' "${arrived[$n]}" "$n"
    else
      _jo_refuse "$n є в базі, але коміту, що його додав, в історії першого батька немає"
      return 2
    fi
  done | LC_ALL=C sort -t $'\t' -k1,1n -k2,2n -k3,3 | cut -f3
}

# journal_files <архів> [unordered] — файли журналу в порядку читання: архів, далі файли
# теки поруч з ним (<тека архіву>/agy-stats/*.md, лише верхній рівень) у порядку іспиту
# (journal_order). unordered — за іменем, без git: для того, кому порядок не важить
# (agy-opus-budget.sh рахує виклики за датою), щоб не залежати від історії. Ім'я поза
# JOURNAL_NAME_RE — відмова (вихід 2).
journal_files() {
  local archive="$1" mode="${2:-ordered}" dir f names=() sorted
  dir="$(dirname "$archive")/${JOURNAL_DIR##*/}"
  printf '%s\n' "$archive"
  [[ -d "$dir" ]] || return 0
  while IFS= read -r -d '' f; do
    f="${f##*/}"
    [[ "$f" =~ $JOURNAL_NAME_RE ]] || {
      echo "відмова: ім'я файла теки «$f» — лише латиниця, цифри, «.», «_», «-» і .md" >&2
      return 2
    }
    names+=("$f")
  done < <(find "$dir" -mindepth 1 -maxdepth 1 -type f -name '*.md' -print0)
  ((${#names[@]})) || return 0
  if [[ "$mode" == unordered ]] || ((${#names[@]} == 1)); then
    sorted="$(printf '%s\n' "${names[@]}" | LC_ALL=C sort)"
  else
    sorted="$(journal_order "$dir" "${names[@]}")" || return 2
  fi
  while IFS= read -r f; do printf '%s/%s\n' "$dir" "$f"; done <<<"$sorted"
}

# journal_rows <архів> [unordered] — рядки викликів з архіву й усіх файлів теки, ОДНИМ
# потоком і в порядку іспиту (правила вище; unordered — див. journal_files). `\|` у
# клітинці вже замінено на \x1f, тож споживач ріже рядок по «|» без пасток.
#
# ВІДМОВИ (stderr, вихід 3, решта рядків іде далі — як і раніше в кожному скрипті):
# у рядку не стільки клітинок, скільки в шапці його файла (неекранований «|» зсуває
# колонки); у файлі теки — рядок до шапки або шапка, що не збігається з шапкою архіву
# (колонки читаються за місцем, тож чужий порядок колонок мовчки дав би чужі числа).
# Перелік файлів не склався (journal_files) — вихід 2, рядків немає.
journal_rows() {
  local list files
  list="$(journal_files "$1" "${2:-}")" || return 2
  mapfile -t files <<<"$list"
  awk -F'|' '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function cellsof(   i, o) { o = ""; for (i = 2; i < NF; i++) o = o "|" trim($i); return o }
    FNR == 1 { fi++; cells = 0 }
    { gsub(/\\\|/, "\037") }
    /^\| Дата / {
      if (cells) next
      cells = NF
      if (fi == 1) canon = cellsof()
      else if (cellsof() != canon) {
        printf "відмова: %s — шапка таблиці не та, що в архіві (колонки читаються за місцем)\n", FILENAME > "/dev/stderr"
        bad = 1; skip = fi
      }
      next
    }
    /^\| [0-9]{4}-[0-9]{2}-[0-9]{2} / {
      if (skip == fi) next
      if (fi > 1 && !cells) {
        printf "відмова: %s — %s: рядок до шапки таблиці, клітинки не звірити\n", FILENAME, trim($2) > "/dev/stderr"
        bad = 1; next
      }
      if (cells && NF != cells) {
        printf "відмова: %s — %s: у рядку %d клітинок замість %d; найімовірніше, неекранований «|» у тексті (пишіть \\|)\n", FILENAME, trim($2), NF - 2, cells - 2 > "/dev/stderr"
        bad = 1; next
      }
      print
    }
    END { if (bad) exit 3 }' "${files[@]}"
}
