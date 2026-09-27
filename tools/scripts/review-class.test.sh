#!/usr/bin/env bash
# review-class.test.sh — клас PR для рецензії: по файлу з кожної категорії, звичайні
# зміни, змішаний PR, перейменування, порожній вхід; мутації — кожна категорія
# тримається тестом.
# Запуск: tools/scripts/review-class.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${REVIEW_CLASS_UNDER_TEST:-$HERE/review-class.sh}"
fail=0
ok() { echo "✓ $1"; }
bad() {
  echo "✗ $1"
  fail=1
  [[ -z "${REVIEW_CLASS_UNDER_TEST:-}" ]] || exit 1
}

# expect <назва> <очікуваний-exit> <вхід> <підрядок>...
expect() {
  local name="$1" want="$2" input="$3" out rc needle
  shift 3
  out="$(printf '%s' "$input" | bash "$SCRIPT" 2>&1)"
  rc=$?
  if [[ $rc != "$want" ]]; then
    bad "$name — очікував exit $want, отримав $rc: $out"
    return
  fi
  for needle in "$@"; do
    [[ "$out" == *"$needle"* ]] || {
      bad "$name — у виводі немає «$needle»: $out"
      return
    }
  done
  ok "$name"
}

# ─── 1. По справжньому файлу з кожної з п'яти категорій — ризиковий ─────────
while IFS='|' read -r cat path; do
  expect "$cat: $path" 0 "$path"$'\n' "клас: ризиковий" "$cat: $path"
done <<'EOF'
дозволи й безпека|.claude/settings.orchestrator.json
дозволи й безпека|tools/agy/permissions.json
дозволи й безпека|tools/scripts/install-orchestrator-profile.sh
дозволи й безпека|tools/scripts/check-forbidden-paths.test.sh
дозволи й безпека|tools/scripts/claude-review-session.sh
дозволи й безпека|tools/scripts/review-class.sh
дозволи й безпека|tools/scripts/agy-opus-budget.sh
дозволи й безпека|infra/ansible/roles/firewall/tasks/main.yml
дозволи й безпека|infra/discord/config/roles.ts
дозволи й безпека|infra/discord/lib/permissions.ts
дозволи й безпека|infra/discord/lib/apply.ts
дозволи й безпека|apps/api/src/plugins/rate-limit.ts
дозволи й безпека|apps/api/src/lib/sentry-pii.ts
дозволи й безпека|apps/api/src/routes/auth.ts
роль і демон A8|infra/ansible/a8.yml
роль і демон A8|infra/ansible/roles/a8/tasks/main.yml
роль і демон A8|tools/scripts/a8-tick-logic.sh
роль і демон A8|tools/scripts/a8-pr-fence.sh
роль і демон A8|tools/scripts/autorun.sh
CI|.github/workflows/ci.yml
CI|lefthook.yml
CI|tools/scripts/prove-red-before-green.sh
експорт і валідатори §7|workers/cad/flatcraft_cad/export/dxf.py
експорт і валідатори §7|workers/cad/flatcraft_cad/validate/profile.py
експорт і валідатори §7|workers/cad/tests/snapshots/l_bracket.dxf
експорт і валідатори §7|packages/cad-engine/src/validators/profile.ts
експорт і валідатори §7|packages/cad-engine/data/bend-machine-esi.yaml
експорт і валідатори §7|apps/api/src/routes/exports.ts
міграції|packages/db/src/migrations/0007_x.sql
міграції|packages/db/src/schema.ts
EOF

# ─── 2. Звичайні зміни — одна рецензія ─────────────────────────────────────
expect "документи, промпти, UI, звіти A8 — звичайний" 0 \
  $'docs/02_ROADMAP.md\ndocs/promts/orchestrator-autonomy.md\napps/web/src/components/Wizard.tsx\ntools/scripts/a8-metrics.sh\ntools/scripts/a8-report.sh\nworkers/cad/tests/test_export.py\n' \
  "клас: звичайний"
expect "звичайний не називає жодного файла ризиковим" 0 $'README.md\n' "клас: звичайний"
out="$(printf 'README.md\n' | bash "$SCRIPT")"
[[ "$(wc -l <<<"$out")" == 1 ]] && ok "звичайний — рівно один рядок виводу" || bad "звичайний друкує зайве: $out"

# ─── 3. Змішаний PR — ризиковий, названо лише ризикові файли ───────────────
out="$(printf 'docs/x.md\n.github/workflows/ci.yml\napps/web/a.tsx\npackages/db/src/schema.ts\n' | bash "$SCRIPT")"
if [[ "$out" == "клас: ризиковий"* && "$out" == *"CI: .github/workflows/ci.yml"* &&
  "$out" == *"міграції: packages/db/src/schema.ts"* && "$out" != *"docs/x.md"* && "$out" != *"apps/web/a.tsx"* ]]; then
  ok "змішаний PR — ризиковий, у переліку лише ризикові файли"
else
  bad "змішаний PR класифіковано неправильно: $out"
fi

# ─── 4. Шаблон не ловить сусідні шляхи ─────────────────────────────────────
expect "workers/cad/tests (не снапшоти) — звичайний" 0 $'workers/cad/tests/test_validate.py\n' "клас: звичайний"
expect "packages/db/src/seed.ts — звичайний" 0 $'packages/db/src/seed.ts\n' "клас: звичайний"
expect "docs про .github — звичайний" 0 $'docs/github-notes.md\n' "клас: звичайний"
expect "infra/discord/README.md — звичайний" 0 $'infra/discord/README.md\n' "клас: звичайний"

# ─── 5. Перейменування з ризикового шляху — ризиковий ──────────────────────
# `--no-renames` дає і старий шлях (видалення), і новий; старий ловиться.
expect "перенесення файла з .claude/ — ризиковий за старим шляхом" 0 \
  $'.claude/settings.a8.json\ndocs/old-settings.json\n' "клас: ризиковий" ".claude/settings.a8.json"

# ─── 6. Порожній вхід — відмова, а не «звичайний» ──────────────────────────
expect "порожній вхід — exit 2" 2 "" "порожній список"
expect "лише порожні рядки — exit 2" 2 $'\n\n' "порожній список"

# ─── 7. Мутації: кожна категорія й відмова тримаються тестом ────────────────
if [[ -z "${REVIEW_CLASS_UNDER_TEST:-}" && $fail == 0 ]]; then
  M="$(mktemp -d)"
  trap 'rm -rf "$M"' EXIT
  src="$(<"$SCRIPT")"
  mutate() { # mutate <назва> <було> <стало> — «було» мусить стояти в скрипті рівно раз
    local name="$1" from="$2" to="$3" rest m="$M/$((++n)).sh"
    rest="${src#*"$from"}"
    if [[ "$rest" == "$src" || "$rest" == *"$from"* ]]; then
      bad "мутант «$name»: текст не знайдено рівно один раз — мутація застаріла"
      return
    fi
    printf '%s\n' "${src/"$from"/"$to"}" >"$m"
    if REVIEW_CLASS_UNDER_TEST="$m" bash "$HERE/$(basename "$0")" >"$m.out" 2>&1; then
      bad "мутант ВИЖИВ: $name"
    else
      ok "мутанта вбито: $name"
    fi
  }
  n=0
  mutate "без категорії «CI» для .github" "  'CI|.github/*'" ''
  mutate "без міграцій" "  'міграції|packages/db/src/migrations/*'" ''
  mutate "без снапшотів експорту" "  'експорт і валідатори §7|workers/cad/tests/snapshots/*'" ''
  mutate "роль A8 не ризикова" "  'роль і демон A8|infra/ansible/roles/a8/*'" ''
  mutate "механізм рецензії не ризиковий" "  'дозволи й безпека|tools/scripts/review-class*'" ''
  mutate "порожній вхід — звичайний" "  exit 2" "  exit 0"
  mutate "шаблон як рядок, а не glob" '[[ "$f" == ${r#*|} ]]' '[[ "$f" == "${r#*|}" ]]'
fi

if [[ $fail == 1 ]]; then
  echo "FAIL"
  exit 1
fi
echo "Усі тести пройдено."
