#!/usr/bin/env bash
# inbox-setup.test.sh — у hart-inbox пишуться лише мітки з labels.tsv і файли форм у
# .github/ISSUE_TEMPLATE/; повторний запуск оновлює файл за sha. gh — заглушка.
# Запуск: tools/scripts/inbox-setup.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/../inbox"
fail=0
check() { if eval "$2"; then echo "✓ $1"; else echo "✗ $1"; fail=1; fi; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
cat >"$T/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >>"$(dirname "$0")/../gh.log"
# Перший прогін: файлів ще немає (404); другий — є, sha відомий.
if [[ "$1 $2" == "api repos/stjurik/hart-inbox/contents/"* && "$*" != *"-X PUT"* ]]; then
  [[ -f "$(dirname "$0")/../second" ]] && { echo abc123; exit 0; }
  exit 1
fi
STUB
chmod +x "$T/bin/gh"

PATH="$T/bin:$PATH" bash "$HERE/inbox-setup.sh" >"$T/out.txt" 2>&1
rc=$?
check "вихід 0" "[[ $rc == 0 ]] || { cat '$T/out.txt'; false; }"
check "кожна мітка з labels.tsv створена" \
  "[[ \$(grep -c '^label create .* -R stjurik/hart-inbox --color [0-9a-f]\{6\} .*--force$' '$T/gh.log') == \$(grep -c . '$SRC/labels.tsv') ]]"
for m in нове оброблено 'в беклозі' 'потрібна відповідь' відхилено зауваження ідея; do
  check "мітка «$m» є в labels.tsv" "grep -q '^$m	' '$SRC/labels.tsv'"
done
check "кожна форма — PUT у .github/ISSUE_TEMPLATE/" \
  "[[ \$(grep -c '^api -X PUT repos/stjurik/hart-inbox/contents/.github/ISSUE_TEMPLATE/[a-z]*\.yml ' '$T/gh.log') == \$(ls '$SRC'/forms/*.yml | wc -l) ]]"
check "нічого, крім міток і файлів форм" \
  "! grep -vE '^label create |^api (-X PUT )?repos/stjurik/hart-inbox/contents/.github/ISSUE_TEMPLATE/' '$T/gh.log' | grep -q ."
check "форми ставлять мітки «нове» і тип" \
  "grep -q 'labels: \[\"зауваження\", \"нове\"\]' '$SRC/forms/zauvazhennia.yml' && grep -q 'labels: \[\"ідея\", \"нове\"\]' '$SRC/forms/ideia.yml'"
check "у зауваженні сторінка й опис — обов'язкові" \
  "[[ \$(grep -c 'required: true' '$SRC/forms/zauvazhennia.yml') == 2 ]]"
: >"$T/gh.log"
touch "$T/second"
PATH="$T/bin:$PATH" bash "$HERE/inbox-setup.sh" >/dev/null 2>&1
check "повторний запуск оновлює за sha" "grep -q 'PUT .* -f sha=abc123' '$T/gh.log'"

((fail)) && { echo "inbox-setup.test: є провали"; exit 1; }
echo "inbox-setup.test: усе зелене"
