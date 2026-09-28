#!/usr/bin/env bash
# review-class.sh — чи потрібна PR друга рецензія (контрприклади), за змінами файлів.
#
# ЧОМУ ЦЕ ІСНУЄ. Тижневий ліміт Opus в agy на 2026-09-27 — 15.5% (скріншот yurii).
# Рішення yurii того ж дня: дві рецензії — лише для ризикових PR, для решти повна
# рецензія — одна, від Gemini 3.8 Flash (CLAUDE.md §0 п.2). «Ризиковий» — п'ять
# категорій, названих yurii дослівно: дозволи й безпека; роль і демон A8; CI;
# експорт і валідатори §7; міграції. Якщо клас визначає судження оркестратора, то
# на кожному PR воно трохи інше, і правило перестає бути правилом. Тому клас дає
# перелік шляхів нижче, а зміна переліку — окремий, помітний рядок у PR.
#
# ЧОГО ЦЕ НЕ ДОВОДИТЬ. Клас рахується лише за шляхами. Новий файл поза переліком —
# «звичайний», навіть якщо за змістом він про безпеку. Такий файл додається в
# перелік тим самим PR, що його створює.
#
# Використання (перейменування — як видалення + додавання, щоб старий шлях теж
# рахувався):
#   git diff --name-only --no-renames origin/main...HEAD | bash tools/scripts/review-class.sh
#
# Вивід: перший рядок — `клас: ризиковий` або `клас: звичайний`; далі — категорія і
# шлях для кожного ризикового файла.
# exit 0 — класифіковано; exit 2 — порожній вхід (нічого класифікувати).
set -euo pipefail

# Категорія|шаблон. Шаблон — bash-glob, де `*` захоплює й `/`.
RULES=(
  # Дозволи агентів і межі, які вони тримають; безпека застосунку (CLAUDE.md §8).
  'дозволи й безпека|.claude/*'
  'дозволи й безпека|tools/agy/*'
  'дозволи й безпека|tools/scripts/install-*'
  'дозволи й безпека|tools/scripts/log-permission-request*'
  'дозволи й безпека|tools/scripts/check-forbidden-paths*'
  'дозволи й безпека|tools/scripts/check-deny-parity*'
  'дозволи й безпека|tools/scripts/check-agy-scope*'
  'дозволи й безпека|tools/scripts/agy-permissions-probe*'
  'дозволи й безпека|tools/scripts/measure-deny*'
  'дозволи й безпека|tools/scripts/measure-trust*'
  'дозволи й безпека|tools/scripts/trust-worktree*'
  'дозволи й безпека|tools/scripts/claude-review-session*'
  'дозволи й безпека|tools/scripts/probe-profile-rules*'
  # Сам механізм рецензії: PR, що його послаблює, не має проходити з однією рецензією.
  'дозволи й безпека|tools/scripts/review-class*'
  'дозволи й безпека|tools/scripts/agy-opus-budget*'
  'дозволи й безпека|infra/ansible/roles/firewall/*'
  # Дозволи ролей і каналів живої Discord-спільноти та код, що їх застосовує (ADR-023).
  # Знайдено першим пробним запуском claude-review-session.sh 2026-09-27.
  'дозволи й безпека|infra/discord/config/*'
  'дозволи й безпека|infra/discord/lib/permissions*'
  'дозволи й безпека|infra/discord/lib/apply*'
  'дозволи й безпека|apps/api/src/plugins/rate-limit*'
  'дозволи й безпека|apps/api/src/logger*'
  'дозволи й безпека|apps/api/src/lib/sentry-pii*'
  'дозволи й безпека|apps/api/src/lib/session-hash*'
  'дозволи й безпека|apps/api/src/*auth*'
  # Роль і демон A8: роль Ansible, тік і запобіжники самого тіку.
  'роль і демон A8|infra/ansible/a8.yml'
  'роль і демон A8|infra/ansible/inventory.a8.ini*'
  'роль і демон A8|infra/ansible/roles/a8/*'
  'роль і демон A8|tools/scripts/a8-tick*'
  'роль і демон A8|tools/scripts/a8-pr-fence*'
  'роль і демон A8|tools/scripts/a8-ro-shell*'
  'роль і демон A8|tools/scripts/autorun*'
  'роль і демон A8|tools/scripts/check-ansible-a8*'
  # CI: робочі процеси GitHub і локальні хуки, що стоять перед ними.
  'CI|.github/*'
  'CI|lefthook.yml'
  'CI|tools/scripts/prove-red-before-green*'
  # Експорт і валідатори §7: усе, що визначає файли, які отримає виробництво.
  'експорт і валідатори §7|workers/cad/flatcraft_cad/*'
  'експорт і валідатори §7|workers/cad/tests/snapshots/*'
  'експорт і валідатори §7|packages/cad-engine/src/validators/*'
  'експорт і валідатори §7|packages/cad-engine/src/generated/*'
  'експорт і валідатори §7|packages/cad-engine/data/*'
  'експорт і валідатори §7|apps/api/src/lib/validate-export*'
  'експорт і валідатори §7|apps/api/src/routes/exports*'
  # Міграції і схема, з якої drizzle-kit їх генерує.
  'міграції|packages/db/src/migrations/*'
  'міграції|packages/db/src/schema.ts'
)

hits=()
seen=0
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  seen=1
  for r in "${RULES[@]}"; do
    # shellcheck disable=SC2053 # шаблон навмисно без лапок — це glob
    if [[ "$f" == ${r#*|} ]]; then
      hits+=("  ${r%%|*}: $f")
      break
    fi
  done
done

if ((!seen)); then
  echo "відмова: порожній список змінених файлів — нічого класифікувати" >&2
  exit 2
fi
if ((${#hits[@]})); then
  echo "клас: ризиковий — рецензія Gemini 3.8 Flash + контрприклади (CLAUDE.md §0 п.2)"
  printf '%s\n' "${hits[@]}"
else
  echo "клас: звичайний — повна рецензія: одна, Gemini 3.8 Flash (CLAUDE.md §0 п.2)"
fi
