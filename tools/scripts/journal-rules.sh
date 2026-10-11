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

# journal_dir_file_violated <файл теки> — правило для файла в $JOURNAL_DIR (review-class.sh і,
# для нових файлів, check-journals.sh).
# 0 — ризиково: файл не верхнього рівня чи не .md (підрахунок такого не читає, тож рядок у
# ньому мовчки випав би з іспиту); файл був у базі, і його старий зміст змінено (те саме
# append_only_violated); новий файл, у якому шапка не та, що в архіві, або є щось, крім
# шапки, роздільника й рядків викликів (new_journal_file_violated) — правило «такі виклики не рахуються» можна не переписати, а покласти
# новим файлом; звірити не вдалося. 1 — лише дописано рядки (чи новий файл лише з таблиці).
journal_dir_file_violated() {
  local file="$1" fork body
  [[ "$file" == "$JOURNAL_DIR"/*.md && "${file#"$JOURNAL_DIR"/}" != */* ]] || return 0
  fork="$(git merge-base "$BASE" "$HEAD_REF" 2>/dev/null)" || return 0
  if git cat-file -e "$fork:$file" 2>/dev/null; then
    append_only_violated "$file" "$JOURNAL_ROW_RE"
    return
  fi
  new_journal_file_violated "$file"
}

# new_journal_file_violated <файл> — новий файл теки в HEAD_REF. 1 (чисто) — лише якщо
# перший рядок — шапка таблиці, що після journal_norm слово в слово збігається з шапкою
# архіву в HEAD_REF, другий — роздільник таблиці, а решта — лише рядки викликів
# (JOURNAL_ROW_RE). Інакше 0. ЧОМУ звіряти шапку: підрахунок (journal_rows) відмовляється
# від файла з чужою шапкою, і тоді agy-stats-summary.sh та agy-opus-budget.sh виходять з
# 3 для ВСІХ наступних PR (знахідка Flash, рецензія #230). Правило одне на review-class.sh
# і check-journals.sh: перший лише класифікував би, а CI пропустив би.
new_journal_file_violated() {
  local file="$1" body want first second rest sep_re=$'^\\|[ \t:-]*-[ \t:|-]*$'
  body="$(git show "$HEAD_REF:$file" 2>/dev/null)" || return 0
  # Без пайпа в grep -m1: під pipefail ранній вихід grep дав би SIGPIPE awk-у на журналі в
  # 300 КБ — і «відмову» на правильному файлі.
  want="$(git show "$HEAD_REF:$JOURNAL" 2>/dev/null)" || return 0
  want="$(journal_norm <<<"$want")"
  want="$(grep -E '^\|Дата\|' <<<"$want" | head -n 1 || true)"
  [[ -n "$want" ]] || return 0
  first="$(sed -n 1p <<<"$body")"
  second="$(sed -n 2p <<<"$body")"
  rest="$(tail -n +3 <<<"$body")"
  [[ "$(journal_norm <<<"$first")" == "$want" ]] || return 0
  [[ "$second" =~ $sep_re ]] || return 0
  [[ -z "$(journal_norm <<<"$rest" | grep -Ev -- "$JOURNAL_ROW_RE")" ]] && return 1
  return 0
}

# journal_files <архів> — файли журналу в порядку читання: спершу архів, далі файли теки
# поруч з ним (<тека архіву>/agy-stats/*.md, лише верхній рівень) за іменем у байтовому
# порядку (LC_ALL=C — від локалі не залежить).
journal_files() {
  local dir
  dir="$(dirname "$1")/${JOURNAL_DIR##*/}"
  printf '%s\n' "$1"
  [[ -d "$dir" ]] || return 0
  find "$dir" -mindepth 1 -maxdepth 1 -type f -name '*.md' | LC_ALL=C sort
}

# journal_rows <архів> — рядки викликів з архіву й усіх файлів теки, ОДНИМ потоком і в
# порядку іспиту («перші 10 викликів моделі» — CLAUDE.md §0 п.2). `\|` у клітинці вже
# замінено на \x1f, тож споживач ріже рядок по «|» без пасток.
#
# ПОРЯДОК (детермінований, через усі файли разом). Ключ рядка — найпізніша дата від
# початку ЙОГО файла до нього включно; рівні ключі — архів раніше за теку, файли теки за
# іменем (LC_ALL=C), у файлі — за номером рядка. ЧОМУ не просто дата: в архіві дати йдуть
# не підряд (рядок 2026-10-05 після 2026-10-09 — бувало), а іспит у ньому завжди рахувався
# за порядком у файлі. Сортування за самою датою переставило б старі рядки і заднім
# числом змінило б уже винесені вердикти. Ключ «найпізніша дата до рядка» в межах одного
# файла не спадає, тож порядок усередині файла лишається як був, а файли між собою
# зливаються за датою. Для файлів з датами підряд це і є «за датою».
# ЧОГО НЕ ДОВОДИТЬ: що дата рядка справжня. Рядок у новому файлі теки, датований заднім
# числом, стане в порядку раніше за пізніші виклики і може зсунути межу «перших 10»;
# дату звіряє рецензент з логом agy (`--log-file`), не цей код.
#
# ВІДМОВИ (stderr, вихід 3, решта рядків іде далі — як і раніше в кожному скрипті):
# у рядку не стільки клітинок, скільки в шапці його файла (неекранований «|» зсуває
# колонки); у файлі теки — рядок до шапки або шапка, що не збігається з шапкою архіву
# (колонки читаються за місцем, тож чужий порядок колонок мовчки дав би чужі числа).
journal_rows() {
  local files
  mapfile -t files < <(journal_files "$1")
  awk -F'|' '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function cellsof(   i, o) { o = ""; for (i = 2; i < NF; i++) o = o "|" trim($i); return o }
    FNR == 1 { fi++; cells = 0; maxd = "" }
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
      d = trim($2)
      if (d > maxd) maxd = d
      printf "%s\t%d\t%d\t%s\n", maxd, fi, FNR, $0
    }
    END { if (bad) exit 3 }' "${files[@]}" | LC_ALL=C sort -t "$(printf '\t')" -k1,1 -k2,2n -k3,3n | cut -f4-
}
