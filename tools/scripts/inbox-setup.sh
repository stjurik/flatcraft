#!/usr/bin/env bash
# inbox-setup.sh — мітки й форми приватного stjurik/hart-inbox з git flatcraft.
#
# ЧОМУ ЦЕ ІСНУЄ. Форми й мітки hart-inbox — конфігурація; якої немає в git, тієї
# не існує (CLAUDE.md §0 п.5). Джерело — `tools/inbox/` (labels.tsv, forms/*.yml);
# цей скрипт переносить його в hart-inbox. Повторний запуск нічого не ламає: мітка
# оновлюється (`--force`), файл форми перезаписується за sha.
#
# Пише в hart-inbox лише дві речі: мітки і файли `.github/ISSUE_TEMPLATE/<ім'я>`
# з `tools/inbox/forms/`. Issues не чіпає.
#
# Використання: tools/scripts/inbox-setup.sh   (INBOX_REPO — дефолт stjurik/hart-inbox)
# Вихід: 0 — гаразд; 1 — збій gh; 2 — немає джерела.
set -euo pipefail

INBOX="${INBOX_REPO:-stjurik/hart-inbox}"
SRC="$(cd "$(dirname "$0")/../inbox" 2>/dev/null && pwd)" || {
  echo "inbox-setup: немає tools/inbox" >&2
  exit 2
}

while IFS=$'\t' read -r name color desc; do
  [[ -z "$name" ]] && continue
  gh label create "$name" -R "$INBOX" --color "$color" --description "$desc" --force >/dev/null
  echo "мітка: $name"
done <"$SRC/labels.tsv"

for f in "$SRC"/forms/*.yml; do
  path=".github/ISSUE_TEMPLATE/$(basename "$f")"
  sha="$(gh api "repos/$INBOX/contents/$path" -q .sha 2>/dev/null || true)"
  args=(-X PUT "repos/$INBOX/contents/$path" -f "message=форма $(basename "$f") з flatcraft tools/inbox" -f "content=$(base64 -w0 "$f")")
  [[ -n "$sha" ]] && args+=(-f "sha=$sha")
  gh api "${args[@]}" >/dev/null
  echo "форма: $path"
done
