#!/usr/bin/env bash
# prove-red-before-green.sh — машинний доказ «тест падав ДО фікса» (ADR-035, ai-fix.yml).
#
# ЧОМУ ЦЕ ІСНУЄ. CLAUDE.md §0 п.6 і культура 2.10.e вимагають регресійний тест, який
# падає ДО фікса і проходить ПІСЛЯ. Досі це правило не перевіряв ніхто: Будівельник у CI
# не мав node_modules, тож «червоний до фікса» відтворював РУКАМИ рев'юер
# (docs/17 §9, docs/promts/ai-review-local.md крок 2-bis). Людина робила роботу машини.
#
# ЩО САМЕ ДОВОДИТЬ. Бере тестові файли, додані/змінені гілкою, накладає їх на стан
# BASE_REF (решта файлів гілки відкочується) і проганяє ЛИШЕ ці тести. Вони МУСЯТЬ
# впасти: зелений тест на базовому коді означає, що він не ловить баг, заради якого
# написаний, і як регресійний він нічого не вартий.
#
# Другу половину («зелений ПІСЛЯ») доводить звичайний CI на PR — дублювати її тут було б
# витратою хвилин на те, що вже перевірено.
#
# Використання:
#   git diff --name-only "$BASE_REF...HEAD" | tools/scripts/prove-red-before-green.sh
#
# Env:
#   PRVG_BASE_REF  база порівняння (дефолт origin/main)
#   PRVG_TS_CMD    шаблон запуску TS-тесту; {pkg} = ім'я workspace, {file} = шлях
#   PRVG_PY_CMD    шаблон запуску Python-тесту; {file} = шлях від кореня репо
set -euo pipefail

BASE_REF="${PRVG_BASE_REF:-origin/main}"
TS_CMD="${PRVG_TS_CMD:-pnpm --filter {pkg} exec vitest run --reporter=basic {file}}"
PY_CMD="${PRVG_PY_CMD:-uv run --directory workers/cad pytest {file}}"

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# Підсумок для вкладки Summary у GitHub Actions — щоб доказ був видимий у PR без
# розгортання логів. Поза CI (локальний прогін, тести) змінної немає — пишемо в stdout.
summary() {
  local title="$1" body="$2"
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    printf '### %s\n\n%s\n' "$title" "$body" >>"$GITHUB_STEP_SUMMARY"
  else
    printf '%s — %s\n' "$title" "$body"
  fi
}

# ── 1. Розбір списку змінених файлів ────────────────────────────────────────────
# Доказові — unit-тести, які виконуються без зовнішніх сервісів.
# Недоказові (свідомо): *.int.test.ts потребують Postgres, apps/web/tests/e2e/**
# потребують підняту збірку і БД — це робота ci.yml, не цього гейту.
provable=()
unprovable=()
changed=0
code_changed=0
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  changed=$((changed + 1))
  # Документація не має unit-тестів. Рахуємо окремо, щоб не вимагати регресійний
  # тест від фікса, який править лише текст — інакше агент напише порожній тест
  # заради проходження гейту, і гейт почне шкодити.
  case "$file" in
    *.md | docs/*) ;;
    *) code_changed=$((code_changed + 1)) ;;
  esac
  case "$file" in
    apps/web/tests/e2e/*) unprovable+=("$file") ;;
    *.int.test.ts | *.int.test.tsx) unprovable+=("$file") ;;
    *.test.ts | *.test.tsx | *.spec.ts | *.spec.tsx) provable+=("$file") ;;
    workers/cad/tests/test_*.py) provable+=("$file") ;;
    *) ;;
  esac
done

# Агент нічого не змінив — типово це шлях «заблокований» з ai-fix.yml (заборонений
# шлях або хибний план): PR не створюється, доводити нічого. Не плутати з «змінив
# код, але не написав тест» — то нижче і то провал.
if [[ "$changed" -eq 0 ]]; then
  echo "Змін проти $BASE_REF немає — доводити нічого (ймовірно, агент заблокований)."
  summary "➖ Red-before-green не застосовний" "Гілка не містить змін проти \`$BASE_REF\`."
  exit 0
fi

if [[ "$code_changed" -eq 0 && ${#provable[@]} -eq 0 && ${#unprovable[@]} -eq 0 ]]; then
  echo "Змінено лише документацію — регресійний тест не застосовний."
  summary "➖ Red-before-green не застосовний" "Гілка змінює лише документацію."
  exit 0
fi

if [[ ${#provable[@]} -eq 0 && ${#unprovable[@]} -eq 0 ]]; then
  echo "::error::Регресійного тесту немає. Фікс без тесту не зараховується (CLAUDE.md §0 п.6, культура 2.10.e)." >&2
  summary "❌ Регресійного тесту немає" "Гілка змінює код, але не додає жодного тесту."
  exit 1
fi

if [[ ${#provable[@]} -eq 0 ]]; then
  # Тести є, але всі — інтеграційні/e2e. Машинно довести не можемо; не блокуємо PR,
  # але й не мовчимо: рев'юер має перевірити «червоний до фікса» вручну.
  echo "::warning::Усі нові тести — інтеграційні або e2e (${unprovable[*]}). Red-before-green машинно НЕ доведено — перевір вручну (ai-review-local.md крок 2-bis)." >&2
  summary "⚠️ Red-before-green не доведено машинно" "Усі нові тести — int/e2e, вони потребують БД і збірки. Перевір вручну."
  exit 0
fi

# ── 2. Відкат робочого дерева до стану BASE_REF, зберігши нові тести ────────────
ORIG_SHA="$(git rev-parse HEAD)"
restore() {
  git reset -q --hard "$ORIG_SHA"
  git clean -qfd # node_modules/.venv у .gitignore — clean без -x їх не чіпає
}
trap restore EXIT

# Кожен НЕтестовий файл повертаємо у стан бази: доданий гілкою — видаляємо,
# змінений — відкочуємо. Тестові файли лишаються у версії гілки.
is_provable() {
  local needle="$1" f
  for f in "${provable[@]}"; do [[ "$f" == "$needle" ]] && return 0; done
  return 1
}

while IFS=$'\t' read -r status file; do
  [[ -z "$file" ]] && continue
  is_provable "$file" && continue
  if [[ "$status" == A ]]; then
    rm -f "$file"
  else
    git checkout -q "$BASE_REF" -- "$file" 2>/dev/null || true
  fi
done < <(git diff --no-renames --name-status "$BASE_REF...HEAD")

git reset -q # знімаємо staging після checkout -- , робоче дерево лишається

# ── 3. Прогін доказових тестів на базовому коді — ОЧІКУЄМО ПРОВАЛ ───────────────
# Найближчий package.json вгору по дереву → "<тека workspace>\t<ім'я>".
# Корінь репо перевіряємо теж, останнім: тест може лежати поза workspace'ом.
workspace_of() {
  local dir name; dir="$(dirname "$1")"
  while :; do
    if [[ -f "$dir/package.json" ]]; then
      name="$(node -p "require('./$dir/package.json').name || ''" 2>/dev/null)"
      if [[ -n "$name" ]]; then
        printf '%s\t%s' "$dir" "$name"
        return 0
      fi
    fi
    [[ "$dir" == "." || "$dir" == "/" ]] && return 1
    dir="$(dirname "$dir")"
  done
}

red_count=0
green_offenders=()
for file in "${provable[@]}"; do
  [[ -f "$file" ]] || continue
  if [[ "$file" == *.py ]]; then
    cmd="${PY_CMD//\{file\}/${file#workers/cad/}}"
  else
    ws="$(workspace_of "$file")" || {
      echo "::warning::не визначив workspace для $file — пропускаю" >&2
      continue
    }
    ws_dir="${ws%%$'\t'*}"
    pkg="${ws##*$'\t'}"
    # `pnpm --filter` виконує команду В ТЕЦІ workspace'а, тож шлях до тесту має бути
    # відносним до неї, а не до кореня репо.
    relfile="$file"
    [[ "$ws_dir" != "." ]] && relfile="${file#"$ws_dir"/}"
    cmd="${TS_CMD//\{pkg\}/$pkg}"
    cmd="${cmd//\{file\}/$relfile}"
  fi

  echo "── прогін на базі ($BASE_REF): $file"
  if eval "$cmd"; then
    green_offenders+=("$file")
  else
    red_count=$((red_count + 1))
  fi
done

# ── 4. Вердикт ──────────────────────────────────────────────────────────────────
if [[ ${#green_offenders[@]} -gt 0 ]]; then
  echo "::error::Тест проходить на $BASE_REF, тобто не ловить баг, заради якого написаний: ${green_offenders[*]}" >&2
  summary "❌ Red-before-green НЕ доведено" \
    "Ці тести зелені на \`$BASE_REF\` — як регресійні вони порожні: ${green_offenders[*]}"
  exit 1
fi

if [[ "$red_count" -eq 0 ]]; then
  echo "::error::Жоден доказовий тест не вдалося запустити — доказу немає." >&2
  summary "❌ Red-before-green НЕ доведено" "Жоден доказовий тест не запустився."
  exit 1
fi

echo "OK: $red_count тест(и) падають на $BASE_REF і проходять на гілці (зелене — CI на PR)."
summary "✅ Red-before-green доведено" \
  "$red_count тест(и) падають на \`$BASE_REF\`. Зелене після фікса підтверджує job \`test\` у ci.yml."
