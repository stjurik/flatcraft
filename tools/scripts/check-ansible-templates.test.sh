#!/usr/bin/env bash
# check-ansible-templates.test.sh — кожен шаблон Jinja в infra/ansible розбирається без помилок.
#
# Навіщо: `ansible-playbook --syntax-check` (job Ansible у CI) шаблонів НЕ рендерить, тож
# синтаксична помилка всередині .j2 спливає лише на живому сервері. Так 2026-09-25 переїзд
# staging зупинився на ролі monitoring: bash-вираз `${#масив[@]}` у monitor.sh.j2 Jinja
# прочитав як початок коментаря `{#` («Missing end of comment tag»).
#
# Тест лише розбирає шаблони (parse), не рендерить: змінні ролей тут не потрібні.
# Контроль: той самий розбір на рядку з `${#` мусить дати помилку — інакше тест нічого
# не доводить.
#
# Запуск: tools/scripts/check-ansible-templates.test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok() { echo "✓ $1"; }
bad() {
  echo "✗ $1"
  fail=1
}

if ! python3 -c 'import jinja2' 2>/dev/null; then
  echo "✗ немає python3-модуля jinja2 — перевірити шаблони неможливо"
  exit 1
fi

parse() { # parse <файл> → код 0, якщо Jinja розбирає; інакше друкує помилку
  python3 - "$1" <<'PY'
import sys, jinja2
path = sys.argv[1]
try:
    jinja2.Environment().parse(open(path, encoding="utf-8").read())
except jinja2.TemplateSyntaxError as e:
    print(f"{path}:{e.lineno}: {e.message}")
    sys.exit(1)
PY
}

# Контроль: розбір справді ловить `{#` із bash.
T="$(mktemp)"
trap 'rm -f "$T"' EXIT
printf 'if [ ${#A[@]} -gt 0 ]; then echo x; fi\n' >"$T"
if parse "$T" >/dev/null; then
  bad "контроль: розбір не помітив \`\${#\` — тест нічого не доводить"
else
  ok "контроль: \`\${#\` без екранування — помилка розбору"
fi

n=0
while IFS= read -r f; do
  n=$((n + 1))
  if out="$(parse "$f")"; then :; else bad "шаблон не розбирається: $out"; fi
done < <(find "$ROOT/infra/ansible" -name '*.j2' -type f | sort)
((n > 0)) && ok "розібрано шаблонів: $n" || bad "не знайдено жодного шаблону .j2"

if ((fail)); then
  echo "Провалено."
  exit 1
fi
echo "Усі тести пройдено."
