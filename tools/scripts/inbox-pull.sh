#!/usr/bin/env bash
# inbox-pull.sh — вхідні yurii з приватного stjurik/hart-inbox у теку для розбору.
#
# ЧОМУ ЦЕ ІСНУЄ. Рішення yurii 2026-10-04 (клас A): зауваження до сайту та ідеї
# виробів yurii пише з телефона в приватний репозиторій hart-inbox (дві форми,
# `tools/inbox/forms/`). Розбирає їх оркестратор: цей скрипт → чернетка agy
# (`docs/promts/agy-inbox.md`) → перевірка оркестратора → issue в беклозі flatcraft.
# Порядок — `docs/promts/orchestrator-autonomy.md` §7.
#
# ДВІ МЕЖІ, ЗАРАДИ ЯКИХ СКРИПТ ОКРЕМИЙ, А НЕ РЯДОК У ПРОМПТІ:
#   1. Вміст приватного репозиторію (фото, тексти) пишеться ЛИШЕ в
#      `docs/promts/inputs/_inbox/` робочого дерева flatcraft, і лише якщо git цю
#      теку ігнорує. Деінде скрипт писати відмовляється: flatcraft публічний, а
#      неігнорована тека — один `git add -A` до витоку чужих фото.
#   2. У hart-inbox скрипт лише ставить мітки й пише коментар (`mark`). Тексту
#      yurii він не змінює, нічого не закриває й не видаляє.
#
# Використання:
#   inbox-pull.sh                       — забрати нерозібрані issues у _inbox/<N>/
#   inbox-pull.sh mark <N> <підсумок> <файл-коментаря>
#       підсумок: «в беклозі» | «потрібна відповідь» | «відхилено»
#
# Що «нерозібране»: відкрите issue без мітки «оброблено» — дослівно за рішенням yurii.
# Коментарі оркестратора несуть приховану позначку INBOX_MARK: в issue.md видно, хто
# що написав.
#
# Що лягає в _inbox/<N>/:
#   issue.md           — заголовок, мітки, посилання, текст і коментарі;
#   img-<k>.<ext>      — зображення з тексту й коментарів (лише хости GitHub);
#   images.txt         — яке зображення звідки (адреса без підписаного запиту);
#   backlog-titles.txt — номери й назви відкритих issues flatcraft (пошук дублікатів).
#
# Зображення приватного репозиторію GitHub віддає лише з підписаними посиланнями
# (`private-user-images.githubusercontent.com/...?jwt=`, кілька хвилин життя). Їх дає
# поле body_html у відповіді API з `Accept: application/vnd.github.full+json`; токен
# gh для цього не потрібен і скрипт його не читає.
#
# ЧОГО НЕ ДОВОДИТЬ. Що issue написав саме yurii (репозиторій приватний — інших
# авторів там немає); що зображення без чутливих даних — тому вони й лишаються поза
# git. Розмір і тип зображення перевіряються, вміст — ні.
#
# Змінні: INBOX_REPO (дефолт stjurik/hart-inbox), INBOX_BACKLOG_REPO (stjurik/flatcraft).
# Вихід: 0 — гаразд; 1 — збій gh/curl; 2 — відмова (місце запису, аргументи).
set -euo pipefail

INBOX="${INBOX_REPO:-stjurik/hart-inbox}"
BACKLOG="${INBOX_BACKLOG_REPO:-stjurik/flatcraft}"
INBOX_MARK='<!-- inbox-bot -->'
OUTCOMES=("в беклозі" "потрібна відповідь" "відхилено")
MAX_IMAGE_BYTES=20000000

die() {
  echo "inbox-pull: $1" >&2
  exit "${2:-2}"
}

# ─── mark: лише мітки й коментар у hart-inbox ────────────────────────────────
mark() {
  [[ $# -eq 3 ]] || die "mark <N> <підсумок> <файл-коментаря>"
  local n="$1" outcome="$2" file="$3" o ok=0 tmp current remove=()
  [[ "$n" =~ ^[1-9][0-9]*$ ]] || die "номер issue — «$n»?"
  for o in "${OUTCOMES[@]}"; do [[ "$outcome" == "$o" ]] && ok=1; done
  ((ok)) || die "підсумок «$outcome» — лише: ${OUTCOMES[*]/%/;}"
  [[ -s "$file" ]] || die "немає файла коментаря «$file» або він порожній"

  tmp="$(mktemp)"
  { cat "$file"; printf '\n\n%s\n' "$INBOX_MARK"; } >"$tmp"
  gh issue comment "$n" -R "$INBOX" --body-file "$tmp" >/dev/null || {
    rm -f "$tmp"
    die "gh: коментар до #$n не пішов" 1
  }
  rm -f "$tmp"

  # Знімаємо лише ті мітки, що стоять: «нове» і попередній підсумок.
  current="$(gh issue view "$n" -R "$INBOX" --json labels -q '.labels[].name')" || die "gh: мітки #$n не прочитано" 1
  while IFS= read -r o; do
    [[ "$o" == "нове" ]] && remove+=("$o")
    for x in "${OUTCOMES[@]}"; do [[ "$o" == "$x" && "$o" != "$outcome" ]] && remove+=("$o"); done
  done <<<"$current"
  local args=(--add-label "оброблено,$outcome")
  ((${#remove[@]})) && args+=(--remove-label "$(IFS=,; echo "${remove[*]}")")
  gh issue edit "$n" -R "$INBOX" "${args[@]}" >/dev/null || die "gh: мітки #$n не змінено" 1
  echo "inbox-pull: #$n — оброблено, $outcome"
}

if [[ "${1:-}" == "mark" ]]; then
  shift
  mark "$@"
  exit 0
fi
[[ $# -eq 0 ]] || die "невідомі аргументи: $* (без аргументів — pull; або mark …)"

# ─── pull: куди писати ───────────────────────────────────────────────────────
top="$(git rev-parse --show-toplevel 2>/dev/null)" || die "не в git-дереві — запускайте з робочого дерева flatcraft"
[[ -f "$top/docs/18_NEW_PART_SPEC.md" && -f "$top/tools/inbox/labels.tsv" ]] ||
  die "«$top» — не flatcraft; деінде скрипт не пише"
# Лише головне дерево: agy пише тільки в його docs/promts/inputs/, а не у worktree.
[[ "$(git -C "$top" rev-parse --path-format=absolute --git-dir)" == "$(git -C "$top" rev-parse --path-format=absolute --git-common-dir)" ]] ||
  die "«$top» — git worktree; запускайте в головному дереві (~/hart), куди може писати agy"
rel="docs/promts/inputs/_inbox"
out="$top/$rel"
# Посилання — до check-ignore: той за посиланням теж відмовить, але з хибною причиною.
for p in "$top/docs/promts/inputs" "$out"; do
  [[ -L "$p" ]] && die "$p — символьне посилання; пишу лише в справжню теку"
done
# Саму теку, а не файл у ній: правило `*.md` зробило б issue.md «ігнорованим», а
# зображення поруч — ні (рецензія Gemini 3.8 Flash).
git -C "$top" check-ignore -q "$rel/" ||
  die "$rel не в .gitignore — вміст приватного репозиторію пішов би в публічний; відмова"
mkdir -p "$out"

# ─── pull: що забрати ────────────────────────────────────────────────────────
list="$(gh issue list -R "$INBOX" --state open --limit 200 --json number,labels)" || die "gh: список $INBOX не прочитано" 1
mapfile -t picked < <(jq -r '.[] | select([.labels[].name] | index("оброблено") | not) | .number' <<<"$list")
if ((${#picked[@]} == 0)); then
  echo "inbox-pull: нерозібраних немає"
  exit 0
fi

titles="$(gh issue list -R "$BACKLOG" --state open --limit 1000 --json number,title -q '.[] | "#\(.number) \(.title)"')" ||
  die "gh: беклог $BACKLOG не прочитано" 1

# fetch_images <тека> <html>... — зображення з HTML у <тека>/img-<k>.<ext>.
fetch_images() {
  local dir="$1" k=0 url clean f mime ext
  shift
  : >"$dir/images.txt"
  # Тег може бути розбитий на рядки; `data-canonical-src` — не той src (рецензія Flash).
  while IFS= read -r url; do
    [[ -z "$url" ]] && continue
    # Заміна в лапках: у bash 5.2 голий `&` у заміні означає «знайдений текст».
    url="${url//'&amp;'/'&'}"
    clean="${url%%\?*}"
    case "$clean" in
      https://private-user-images.githubusercontent.com/* | https://user-images.githubusercontent.com/* | https://github.com/user-attachments/*) ;;
      *)
        echo "пропущено (не хост GitHub): $clean" >>"$dir/images.txt"
        continue
        ;;
    esac
    k=$((k + 1))
    f="$dir/img-$k"
    if ! curl -fsSL --max-time 60 --max-filesize "$MAX_IMAGE_BYTES" -o "$f" "$url"; then
      rm -f "$f"
      echo "img-$k: не завантажено — $clean" >>"$dir/images.txt"
      continue
    fi
    mime="$(file --mime-type -b "$f")"
    case "$mime" in
      image/png) ext=png ;;
      image/jpeg) ext=jpg ;;
      image/gif) ext=gif ;;
      image/webp) ext=webp ;;
      *)
        rm -f "$f"
        echo "img-$k: відкинуто, тип $mime — $clean" >>"$dir/images.txt"
        continue
        ;;
    esac
    mv "$f" "$f.$ext"
    echo "img-$k.$ext ← $clean" >>"$dir/images.txt"
  done < <(printf '%s\n' "$@" | tr '\n' ' ' | grep -oE '<img [^>]*>' |
    sed -nE 's/.*[[:space:]]src="(https:\/\/[^"]+)".*/\1/p')
}

for n in "${picked[@]}"; do
  issue="$(gh api "repos/$INBOX/issues/$n" -H 'Accept: application/vnd.github.full+json')" || die "gh: #$n не прочитано" 1
  comments="$(gh api "repos/$INBOX/issues/$n/comments" --paginate -H 'Accept: application/vnd.github.full+json')" ||
    die "gh: коментарі #$n не прочитано" 1
  dir="$out/$n"
  rm -rf "$dir"
  mkdir -p "$dir"
  {
    jq -r '"# #\(.number) — \(.title)\n\nПосилання (приватне): \(.html_url)\nМітки: \([.labels[].name] | join(", "))\nСтворено: \(.created_at)\n\n## Текст\n\n\(.body // "")"' <<<"$issue"
    jq -r --arg mark "$INBOX_MARK" '.[] | "\n## Коментар \(.created_at)\(if (.body // "") | contains($mark) then " — оркестратор" else " — yurii" end)\n\n\(.body // "" | split($mark) | join(""))"' <<<"$comments"
  } >"$dir/issue.md"
  mapfile -t htmls < <(jq -r '.body_html // ""' <<<"$issue"; jq -r '.[].body_html // ""' <<<"$comments")
  fetch_images "$dir" "${htmls[@]}"
  printf '%s\n' "$titles" >"$dir/backlog-titles.txt"
  echo "inbox-pull: #$n → $rel/$n ($(grep -c '^img-[0-9]*\.' "$dir/images.txt" || true) зобр.)"
done
