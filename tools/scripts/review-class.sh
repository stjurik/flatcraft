#!/usr/bin/env bash
# review-class.sh — чи потрібна PR друга рецензія (контрприклади), за змінами файлів.
#
# ЧОМУ ЦЕ ІСНУЄ. Тижневий ліміт Opus в agy на 2026-09-27 — 15.5% (скріншот yurii).
# Рішення yurii того ж дня: дві рецензії — лише для ризикових PR, для решти повна
# рецензія — одна, від Gemini 3.8 Flash (CLAUDE.md §0 п.2). «Ризиковий» — п'ять
# категорій, названих yurii дослівно: дозволи й безпека; роль і демон A8; CI;
# експорт і валідатори §7; міграції. 2026-09-29 yurii додав ще дві («1а, 2а»): самі
# правила й контракт (CLAUDE.md, ADR, правила рецензії, журнал іспиту) — інакше PR,
# що послаблює вимогу другої рецензії, пройшов би з однією; і вся інфраструктура
# (`infra/**`) — у #139 саме там були бекапи, що ніколи не працювали.
# Якщо клас визначає судження оркестратора, то
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
# ЖУРНАЛ ІСПИТУ (`agy-stats.md`) — окремо. Його дописують майже в кожному PR (9 з 12
# останніх), а форматування таблиці при новому рядку перерівнює всі старі. Тож за
# назвою файла він зробив би ризиковими три чверті PR. Ризиково інше: змінити ЗМІСТ
# старих рядків чи правил у шапці — так модель можна «пропустити» через іспит заднім
# числом. Тому порівнюється зміст без вирівнювання: кожен старий рядок (база —
# merge-base з REVIEW_CLASS_BASE, дефолт origin/main) мусить лишитися в HEAD. Не
# вдалося звірити — ризиковий: сумнів іде проти PR.
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
  # Самі правила й контракт (рішення yurii 2026-09-29, «1а»). Журнал іспиту — не тут,
  # а у journal_rows_changed нижче: ризикова лише зміна старих рядків.
  'правила й контракт|CLAUDE.md'
  'правила й контракт|docs/03_DECISIONS.md'
  'правила й контракт|docs/promts/orchestrator-autonomy.md'
  'правила й контракт|docs/15_LLM_PROMPTS.md'
  'правила й контракт|docs/promts/ai-review-local.md'
  # Уся інфраструктура (рішення yurii 2026-09-29, «2а»). ОСТАННІМ рядком: вужчі
  # категорії вище (роль A8, фаєрвол, Discord) лишають свою назву.
  'інфраструктура|infra/*'
)

JOURNAL='docs/promts/inputs/agy-stats.md'
BASE="${REVIEW_CLASS_BASE:-origin/main}"
HEAD_REF="${REVIEW_CLASS_HEAD:-HEAD}"

# Зміст рядка без вирівнювання: клітинки таблиці обрізані від пробілів, роздільник
# таблиці пропущено, у решті рядків — лише хвостові пробіли. `\|` — символ у клітинці.
journal_norm() {
  sed 's/\\|/\x1f/g' | awk -F'|' '
    /^\|[ \t:-]*-[ \t:|-]*$/ { next }
    /^\|/ { out = ""; for (i = 2; i < NF; i++) { f = $i; gsub(/^[ \t]+|[ \t]+$/, "", f); out = out "|" f } print out; next }
    { sub(/[ \t]+$/, ""); if ($0 != "") print }'
}
journal_rows_changed() { # 0 — старий зміст змінено/видалено або звірити не вдалось; 1 — лише дописано
  local mb old new
  mb="$(git merge-base "$BASE" "$HEAD_REF" 2>/dev/null)" || return 0
  old="$(git show "$mb:$JOURNAL" 2>/dev/null)" || return 1 # журналу в базі не було — усе дописано
  new="$(git show "$HEAD_REF:$JOURNAL" 2>/dev/null)" || return 0 # журнал видалено
  [[ -n "$(LC_ALL=C comm -23 <(journal_norm <<<"$old" | LC_ALL=C sort) <(journal_norm <<<"$new" | LC_ALL=C sort))" ]]
}

hits=()
seen=0
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  seen=1
  if [[ "$f" == "$JOURNAL" ]]; then
    journal_rows_changed &&
      hits+=("  правила й контракт: $f — змінено зміст старих рядків журналу іспиту (або звірити не вдалося)")
    continue
  fi
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
