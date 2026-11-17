#!/usr/bin/env bash
# check-forbidden-paths.sh — ADR-035, ai-fix.yml verification-step.
#
# Читає список змінених файлів зі stdin (один шлях на рядок — саме такий
# формат дає `git diff --name-only`) і валить job (exit 1), якщо ХОЧА Б один
# зачіпає заборонену для ai-fix зону (packages/db/migrations, infra/,
# .github/, CLAUDE.md, docs/03_DECISIONS.md, docs/12_TEMPLATE_CONTRACT.md,
# packages/db/schema.ts, bend-матриця, DXF/PDF-снапшоти).
#
# Друга лінія оборони поверх `settings` permissions.deny у claude-code-action
# (яка блокує запис МЕХАНІЧНО) — цей скрипт ловить те, що deny-rule могла
# пропустити (напр. якщо агент створив файл іншим шляхом).
#
# Використання:
#   git diff --name-only origin/main...HEAD | tools/scripts/check-forbidden-paths.sh
set -euo pipefail

# Каталоги — з `(/|$)`: git показує субмодуль (gitlink) на місці каталогу
# рядком БЕЗ кінцевого «/», і шаблон `^infra/` його б не впізнав.
FORBIDDEN_PATTERNS=(
  '^packages/db/src/migrations(/|$)'
  '^infra(/|$)'
  '^\.github(/|$)'
  '^CLAUDE\.md$'
  '^docs/03_DECISIONS\.md$'
  '^docs/12_TEMPLATE_CONTRACT\.md$'
  '^packages/db/src/schema\.ts$'
  # Bend-матриця — єдине джерело істини для гибки (CLAUDE.md §6.1, §13).
  '^packages/cad-engine/data/bend-machine-esi\.yaml$'
  '^workers/cad/tests/snapshots(/|$)'
  # Скрипти, які роль A8 ставить на хост і виконує від root чи agent поза
  # контейнером: обгортка git (a8-git-lib.sh), дієслова черги, requeue, логіка
  # тіку, ssh-обгортки — і сам цей backstop (#302 D, рецензія #299). Агент, що
  # змінив би їх у своєму PR, змінив би межу, яка його ж стримує. Шаблон — на
  # весь префікс a8-: новий скрипт ролі потрапляє сюди сам; що кожен скрипт,
  # який роль копіює з tools/scripts, тут є, тримає інваріант 18 check-ansible-a8.sh.
  '^tools/scripts/a8-[^/]*$'
  '^tools/scripts/check-forbidden-paths(\.test)?\.sh$'
)

violations=()
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
    if [[ "$file" =~ $pattern ]]; then
      violations+=("$file")
      break
    fi
  done
done

if [[ ${#violations[@]} -gt 0 ]]; then
  echo "::error::ai-fix зачепив заборонені шляхи (ADR-035): ${violations[*]}"
  printf '  ✗ %s\n' "${violations[@]}" >&2
  exit 1
fi

echo "OK: жодного забороненого шляху не зачеплено."
