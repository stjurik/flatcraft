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

# ─── 1. По справжньому файлу з кожної категорії — ризиковий ─────────────────
# Кожен файл — разом зі звичайним файлом коду: файли правил поодинці дають виняток
# «правила-текст» (розділ 5f), а тут перевіряється, що категорія з RULES діє.
while IFS='|' read -r cat path; do
  expect "$cat: $path" 0 "$path"$'\napps/web/src/x.tsx\n' "клас: ризиковий" "$cat: $path"
done <<'EOF'
дозволи й безпека|.claude/settings.orchestrator.json
дозволи й безпека|tools/agy/permissions.json
дозволи й безпека|tools/scripts/install-orchestrator-profile.sh
дозволи й безпека|tools/scripts/check-forbidden-paths.test.sh
дозволи й безпека|tools/scripts/check-leak.sh
дозволи й безпека|tools/scripts/safe-publish.sh
дозволи й безпека|tools/scripts/claude-review-session.sh
дозволи й безпека|tools/scripts/probe-profile-rules.sh
дозволи й безпека|tools/scripts/guard-destructive.sh
дозволи й безпека|tools/scripts/guard-destructive.test.sh
дозволи й безпека|tools/scripts/review-class.sh
дозволи й безпека|tools/scripts/journal-rules.sh
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
CI|tools/scripts/check-journals.sh
CI|tools/scripts/check-journals.test.sh
експорт і валідатори §7|workers/cad/flatcraft_cad/export/dxf.py
експорт і валідатори §7|workers/cad/flatcraft_cad/validate/profile.py
експорт і валідатори §7|workers/cad/tests/snapshots/l_bracket.dxf
експорт і валідатори §7|packages/cad-engine/src/validators/profile.ts
експорт і валідатори §7|packages/cad-engine/data/bend-machine-esi.yaml
експорт і валідатори §7|apps/api/src/routes/exports.ts
міграції|packages/db/src/migrations/0007_x.sql
міграції|packages/db/src/schema.ts
правила й контракт|CLAUDE.md
правила й контракт|docs/03_DECISIONS.md
правила й контракт|docs/promts/orchestrator-autonomy.md
правила й контракт|docs/15_LLM_PROMPTS.md
правила й контракт|docs/promts/ai-review-local.md
правила й контракт|docs/20_OPEN_DECISIONS.md
правила й контракт|tools/scripts/agy-stats-summary.sh
інфраструктура|infra/ansible/roles/base/tasks/main.yml
інфраструктура|infra/ansible/roles/backups/tasks/main.yml
інфраструктура|infra/ansible/site.yml
інфраструктура|infra/compose/Caddyfile
інфраструктура|infra/docker/api.Dockerfile
інфраструктура|infra/discord/README.md
EOF

# ─── 2. Звичайні зміни — одна рецензія ─────────────────────────────────────
expect "документи, промпти, UI, звіти A8 — звичайний" 0 \
  $'docs/02_ROADMAP.md\ndocs/promts/master-a8-transition.md\napps/web/src/components/Wizard.tsx\ntools/scripts/a8-metrics.sh\ntools/scripts/a8-report.sh\nworkers/cad/tests/test_export.py\n' \
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
expect "docs/13 і AGENTS.md — звичайні" 0 $'docs/13_PROGRESS_LOG.md\nAGENTS.md\n' "клас: звичайний"
# Вужча категорія інфраструктури лишає свою назву — «інфраструктура» лише для решти.
expect "роль A8 — «роль і демон A8», не «інфраструктура»" 0 $'infra/ansible/roles/a8/tasks/main.yml\n' \
  "роль і демон A8: infra/ansible/roles/a8/tasks/main.yml"

# ─── 5. Перейменування з ризикового шляху — ризиковий ──────────────────────
# `--no-renames` дає і старий шлях (видалення), і новий; старий ловиться.
expect "перенесення файла з .claude/ — ризиковий за старим шляхом" 0 \
  $'.claude/settings.a8.json\ndocs/old-settings.json\n' "клас: ризиковий" ".claude/settings.a8.json"

# ─── 5b. Журнал іспиту: дописати рядок — звичайно, решта — ризиково ────────
# Тимчасовий git: база з журналом і гілки з різними змінами. Скрипт звіряє
# merge-base(REVIEW_CLASS_BASE, REVIEW_CLASS_HEAD) з REVIEW_CLASS_HEAD.
J=docs/promts/inputs/agy-stats.md
G="$(mktemp -d)"
git -C "$G" init -q
GIT=(git -C "$G" -c user.name=t -c user.email=t@t)
mkdir -p "$G/docs/promts/inputs"
cat >"$G/$J" <<'JEOF'
# журнал

> Вердикт: частка викликів із вигадкою **не нижче 50%** — модель іде з ролі.

| Дата | Задача | Модель agy | Вигадок |
| ---- | ------ | ---------- | ------- |
| 2026-09-24 | рецензія #1 \| diff | Gemini 3.8 Flash (High) | **0** |
| 2026-09-25 | рецензія #2 | Claude Opus 4.6 (Thinking) | **1** |
JEOF
"${GIT[@]}" add -A && "${GIT[@]}" commit -qm base && "${GIT[@]}" branch -q base
branch() { # branch <назва> <perl-вираз над журналом> | branch <назва> --rm
  "${GIT[@]}" switch -q -c "$1" base
  if [[ "$2" == --rm ]]; then "${GIT[@]}" rm -q "$J"; else perl -0pi -e "$2" "$G/$J"; fi
  "${GIT[@]}" commit -qam "$1"
}
branch append 's/\z/| 2026-09-29 | рецензія #3 | claude-sonnet-5-5 (окрема сесія) | **0** |\n/'
branch realign 's/\| 2026-09-24 \|/|   2026-09-24   |/; s/\| Дата \|/|   Дата   |/; s/\z/| 2026-09-29 | рецензія #3 | Gemini 3.8 Flash (High) | **0** |\n/'
branch edit-row 's/\*\*1\*\*/**0**/'
branch edit-rule 's/не нижче 50%/не нижче 80%/'
branch edit-escaped 's/рецензія #1 \\\| diff/рецензія #1 \\| інше/'
branch removed --rm
# Нове правило не переписує старе, а дописується — старі рядки всі на місці.
branch add-rule 's/(> Вердикт[^\n]*\n)/$1>\n> Виклики з позначкою «пробний» у вікно не йдуть.\n/'
branch add-note 's/\z/\nПримітка: рецензію #2 не рахувати.\n/'
# Контрприклади повторної рецензії #145 (окрема сесія, Flash): іспит — перші 10
# викликів за порядком у файлі, тож переставлення змінює іспит, хоча жоден рядок не
# зник; рядок-правило з `|` у шапці і новий рядок над старими — теж.
branch reorder 's/(\| 2026-09-24 [^\n]*\n)(\| 2026-09-25 [^\n]*\n)/$2$1/'
branch insert-above 's/(\| 2026-09-24 )/| 2026-09-23 | вставлено над старими | Gemini 3.8 Flash (High) | **0** |\n$1/'
branch pipe-rule 's/(> Вердикт[^\n]*\n)/$1| Правило: виклики «пробний» у вікно не йдуть |\n/'
branch pipe-tail 's/\z/| Правило: рецензію #2 не рахувати |\n/'
branch second-table 's/\z/\n| Модель | Поріг |\n| --- | --- |\n| Flash | 80% |\n/'
"${GIT[@]}" switch -q --orphan fresh && mkdir -p "$G/docs/promts/inputs" && echo "| 2026-09-29 | x | y | **0** |" >"$G/$J" &&
  "${GIT[@]}" add -A && "${GIT[@]}" commit -qm fresh
# Журнал лише з рядків викликів, без шапки: переставлення тут ловить саме звірка
# порядку — без неї «дописаним» став би весь файл, а він цілком із рядків викликів.
"${GIT[@]}" switch -q --orphan rows-only && mkdir -p "$G/docs/promts/inputs" &&
  printf '%s\n' '| 2026-09-24 | a | Flash | **0** |' '| 2026-09-25 | b | Opus | **1** |' >"$G/$J" &&
  "${GIT[@]}" add -A && "${GIT[@]}" commit -qm rows-only
"${GIT[@]}" switch -q -c rows-swapped rows-only &&
  printf '%s\n' '| 2026-09-25 | b | Opus | **1** |' '| 2026-09-24 | a | Flash | **0** |' >"$G/$J" &&
  "${GIT[@]}" commit -qam rows-swapped
journal_case() { # journal_case <назва> <гілка> <база> <очікуваний клас>
  local out
  out="$(cd "$G" && printf '%s\n' "$J" | REVIEW_CLASS_BASE="$3" REVIEW_CLASS_HEAD="$2" bash "$SCRIPT" 2>&1)"
  [[ "$out" == "клас: $4"* ]] && ok "журнал: $1 — $4" || bad "журнал: $1 — очікував «$4»: $out"
}
journal_case "дописано рядок" append base звичайний
journal_case "дописано рядок і перевирівняно старі" realign base звичайний
journal_case "змінено вигадки в старому рядку" edit-row base ризиковий
journal_case "змінено правило в шапці (50% → 80%)" edit-rule base ризиковий
journal_case "змінено клітинку з \\| усередині" edit-escaped base ризиковий
journal_case "журнал видалено" removed base ризиковий
journal_case "дописано нове правило в шапку" add-rule base ризиковий
journal_case "дописано примітку під таблицею" add-note base ризиковий
journal_case "переставлено два старі рядки" reorder base ризиковий
journal_case "новий рядок вставлено над старими" insert-above base ризиковий
journal_case "рядок-правило з | у шапці" pipe-rule base ризиковий
journal_case "рядок-правило з | у кінці, без дати" pipe-tail base ризиковий
journal_case "друга таблиця в кінці" second-table base ризиковий
journal_case "лише рядки викликів, переставлено" rows-swapped rows-only ризиковий
journal_case "журналу в базі не було" fresh fresh звичайний
journal_case "базу не знайдено — сумнів проти PR" append немає-такої-гілки ризиковий
out="$(cd "$G" && printf '%s\n' "$J" | REVIEW_CLASS_BASE=base REVIEW_CLASS_HEAD=edit-row bash "$SCRIPT")"
[[ "$out" == *"правила й контракт: $J — старий зміст змінено, переставлено чи видалено"* ]] &&
  ok "журнал: у виводі — категорія і причина" || bad "журнал: без причини: $out"
rm -rf "$G"

# ─── 5c. Покази квоти agy-quota.md — те саме правило «лише дописати» ──────
Q=docs/promts/inputs/agy-quota.md
G="$(mktemp -d)"
git -C "$G" init -q
GIT=(git -C "$G" -c user.name=t -c user.email=t@t)
mkdir -p "$G/docs/promts/inputs"
printf '%s\n' '# покази' '' '| Показ, UTC | Група | Залишок, % | Скидання, UTC | Джерело |' '| --- | --- | --- | --- | --- |' \
  '| 2026-09-29 07:09 | Claude and GPT | 0.00 | 2026-09-30 19:21 | скріншот |' >"$G/$Q"
"${GIT[@]}" add -A && "${GIT[@]}" commit -qm base && "${GIT[@]}" branch -q base
qbranch() { # qbranch <назва> <perl-вираз над показами>
  "${GIT[@]}" switch -q -c "$1" base
  perl -0pi -e "$2" "$G/$Q"
  "${GIT[@]}" commit -qam "$1"
}
qbranch q-append 's/\z/| 2026-10-01 09:00 | Claude and GPT | 100 | 2026-10-07 19:21 | скріншот |\n/'
qbranch q-edit 's/\| 0\.00 \|/| 100 |/'
qbranch q-note 's/\z/\nПокази до 01.10 не рахувати.\n/'
quota_case() { # quota_case <назва> <гілка> <очікуваний клас>
  local out
  out="$(cd "$G" && printf '%s\n' "$Q" | REVIEW_CLASS_BASE=base REVIEW_CLASS_HEAD="$2" bash "$SCRIPT" 2>&1)"
  [[ "$out" == "клас: $3"* ]] && ok "покази: $1 — $3" || bad "покази: $1 — очікував «$3»: $out"
}
quota_case "дописано новий показ" q-append звичайний
quota_case "змінено старий показ (0% → 100%)" q-edit ризиковий
quota_case "дописано примітку" q-note ризиковий
rm -rf "$G"

# ─── 5d. Шлях з кирилицею: git без core.quotePath=false бере його в лапки ───
# Давня знахідка Flash №8 першої рецензії #145, не закрита до повторної.
expect "кирилиця в лапках (вісімкові коди) — розкодовано, роль A8" 0 \
  $'"infra/ansible/roles/a8/\\321\\204\\320\\260\\320\\271\\320\\273.yml"\n' \
  "роль і демон A8: infra/ansible/roles/a8/файл.yml"
expect "кирилиця без лапок — як є" 0 $'infra/ansible/roles/a8/файл.yml\n' "роль і демон A8: infra/ansible/roles/a8/файл.yml"
expect "кирилиця в лапках у docs — звичайний" 0 $'"docs/\\320\\277.md"\n' "клас: звичайний"
expect "інше екранування в лапках — не розпізнано, ризиковий" 0 $'"docs/a\\"b.md"\n' "шлях не розпізнано"

# ─── 5e. Тека журналу agy-stats/ — файл на PR (рішення yurii 2026-10-11, #228) ─
D=docs/promts/inputs/agy-stats
G="$(mktemp -d)"
git -C "$G" init -q
GIT=(git -C "$G" -c user.name=t -c user.email=t@t)
mkdir -p "$G/$D"
TH='| Дата | Задача | Модель agy | Вигадок |
| ---- | ------ | ---------- | ------- |'
printf '%s\n' "$TH" '| 2026-10-10 | рецензія #1 | Gemini 3.8 Flash (High) | **0** |' '| 2026-10-10 | рецензія #2 | Claude Sonnet 5.5 (High) | **1** |' >"$G/$D/feat-a.md"
printf '%s\n' '# журнал' '' "$TH" '| 2026-09-24 | рецензія #0 | Gemini 3.8 Flash (High) | **0** |' >"$G/$J"
"${GIT[@]}" add -A && "${GIT[@]}" commit -qm base && "${GIT[@]}" branch -q base
dbranch() { # dbranch <назва> <команда над робочим деревом> — гілка від base з однією зміною
  "${GIT[@]}" switch -q -c "$1" base
  (cd "$G" && eval "$2")
  "${GIT[@]}" add -A && "${GIT[@]}" commit -qm "$1"
}
dbranch d-append "printf '%s\n' '| 2026-10-11 | рецензія #3 | Gemini 3.8 Flash (High) | **0** |' >>$D/feat-a.md"
dbranch d-new "printf '%s\n' \"\$TH\" '| 2026-10-11 | рецензія #9 | Gemini 3.8 Flash (High) | **0** |' >$D/feat-b.md"
dbranch d-new-prose "printf '%s\n' \"\$TH\" '| 2026-10-11 | рецензія #9 | Gemini 3.8 Flash (High) | **0** |' 'Виклики Sonnet до 10.10 не рахувати.' >$D/feat-b.md"
dbranch d-new-pipe-rule "printf '%s\n' \"\$TH\" '| Правило: виклики Sonnet не рахувати |' >$D/feat-b.md"
dbranch d-edit "perl -pi -e 's/\*\*1\*\*/**0**/' $D/feat-a.md"
dbranch d-head "perl -pi -e 's/\| Вигадок \|/| Вигадок (будь-які) |/' $D/feat-a.md"
dbranch d-rm "git rm -q $D/feat-a.md"
dbranch d-reorder "perl -0pi -e 's/(\| 2026-10-10 \| рецензія #1[^\n]*\n)(\| 2026-10-10 \| рецензія #2[^\n]*\n)/\$2\$1/' $D/feat-a.md"
dbranch d-nested "mkdir -p $D/sub && printf '%s\n' \"\$TH\" '| 2026-10-11 | x | Gemini 3.8 Flash (High) | **0** |' >$D/sub/feat-c.md"
dbranch d-txt "printf '%s\n' \"\$TH\" '| 2026-10-11 | x | Gemini 3.8 Flash (High) | **0** |' >$D/feat-c.txt"
dbranch t-claude-append "echo 'нове правило' >>CLAUDE.md && printf '%s\n' '| 2026-10-11 | рецензія #3 | Gemini 3.8 Flash (High) | **0** |' >>$D/feat-a.md"
dbranch t-claude-edit "echo 'нове правило' >>CLAUDE.md && perl -pi -e 's/\*\*1\*\*/**0**/' $D/feat-a.md"
dir_case() { # dir_case <назва> <гілка> <очікуваний клас> [підрядок]
  local out
  out="$(cd "$G" && "${GIT[@]}" diff --name-only --no-renames base..."$2" | REVIEW_CLASS_BASE=base REVIEW_CLASS_HEAD="$2" bash "$SCRIPT" 2>&1)"
  if [[ "$out" == "клас: $3"* && "$out" == *"${4:-}"* ]]; then ok "тека журналу: $1 — $3"; else bad "тека журналу: $1 — очікував «$3» ${4:+і «$4»}: $out"; fi
}
dir_case "дописано рядок у файл із бази" d-append звичайний
dir_case "новий файл лише з таблиці" d-new звичайний
dir_case "новий файл з абзацом-правилом" d-new-prose ризиковий "$D/feat-b.md"
dir_case "новий файл з рядком-правилом з |" d-new-pipe-rule ризиковий "$D/feat-b.md"
dir_case "змінено вигадки в старому рядку" d-edit ризиковий "$D/feat-a.md"
dir_case "змінено шапку" d-head ризиковий "$D/feat-a.md"
dir_case "файл видалено" d-rm ризиковий "$D/feat-a.md"
dir_case "переставлено старі рядки" d-reorder ризиковий "$D/feat-a.md"
dir_case "файл у підтеці (підрахунок не читає)" d-nested ризиковий "$D/sub/feat-c.md"
dir_case "файл не .md (підрахунок не читає)" d-txt ризиковий "$D/feat-c.txt"
out="$(cd "$G" && printf '%s\n' "$D/feat-b.md" | REVIEW_CLASS_BASE=немає-такої-гілки REVIEW_CLASS_HEAD=d-new bash "$SCRIPT" 2>&1)"
[[ "$out" == "клас: ризиковий"* ]] && ok "тека журналу: без бази — ризиковий" || bad "тека журналу: без бази — очікував ризиковий: $out"

# ─── 5f. Лише текст правил — клас «правила-текст» (рішення yurii 2026-10-11) ──
expect "лише CLAUDE.md — правила-текст" 0 $'CLAUDE.md\n' "клас: правила-текст" "без контрприкладів" "текст правил: CLAUDE.md"
expect "CLAUDE.md, ADR, процес, docs/15–17, docs/20 — правила-текст" 0 \
  $'CLAUDE.md\ndocs/03_DECISIONS.md\ndocs/promts/orchestrator-autonomy.md\ndocs/promts/ai-review-local.md\ndocs/15_LLM_PROMPTS.md\ndocs/16_AUTONOMOUS_RUNS.md\ndocs/17_AI_BUGFIX_FLOW.md\ndocs/20_OPEN_DECISIONS.md\n' \
  "клас: правила-текст" "текст правил: docs/16_AUTONOMOUS_RUNS.md" "текст правил: docs/promts/ai-review-local.md"
expect "лише docs/16 (поза RULES) — теж правила-текст" 0 $'docs/16_AUTONOMOUS_RUNS.md\n' "клас: правила-текст"
expect "CLAUDE.md + код — ризиковий" 0 $'CLAUDE.md\napps/web/src/x.tsx\n' "клас: ризиковий" "правила й контракт: CLAUDE.md"
expect "CLAUDE.md + тест — ризиковий" 0 $'CLAUDE.md\nworkers/cad/tests/test_x.py\n' "клас: ризиковий" "правила й контракт: CLAUDE.md"
expect "CLAUDE.md + tools/ — ризиковий" 0 $'CLAUDE.md\ntools/scripts/a8-report.sh\n' "клас: ризиковий" "правила й контракт: CLAUDE.md"
expect "CLAUDE.md + .github/ — ризиковий" 0 $'CLAUDE.md\n.github/workflows/ci.yml\n' "клас: ризиковий" "CI: .github/workflows/ci.yml" "правила й контракт: CLAUDE.md"
expect "CLAUDE.md + infra/ — ризиковий" 0 $'CLAUDE.md\ninfra/compose/Caddyfile\n' "клас: ризиковий" "інфраструктура: infra/compose/Caddyfile"
expect "CLAUDE.md + .claude/ — ризиковий" 0 $'CLAUDE.md\n.claude/settings.json\n' "клас: ризиковий" "дозволи й безпека: .claude/settings.json"
expect "CLAUDE.md + docs/promts/inputs/ (дані, не правила) — ризиковий" 0 $'CLAUDE.md\ndocs/promts/inputs/notes.md\n' "клас: ризиковий"
expect "CLAUDE.md + підтека docs/promts/ — ризиковий" 0 $'CLAUDE.md\ndocs/promts/sub/x.md\n' "клас: ризиковий"
expect "CLAUDE.md + README — ризиковий" 0 $'CLAUDE.md\nREADME.md\n' "клас: ризиковий"
expect "docs/16 + README — звичайний (як і раніше)" 0 $'docs/16_AUTONOMOUS_RUNS.md\nREADME.md\n' "клас: звичайний"
dir_case "CLAUDE.md + дописаний рядок журналу теки — правила-текст" t-claude-append правила-текст "текст правил: CLAUDE.md"
dir_case "CLAUDE.md + змінений старий рядок журналу — ризиковий" t-claude-edit ризиковий "правила й контракт: CLAUDE.md"
rm -rf "$G"

# ─── 6. Порожній вхід — відмова, а не «звичайний» ──────────────────────────
expect "порожній вхід — exit 2" 2 "" "порожній список"
expect "лише порожні рядки — exit 2" 2 $'\n\n' "порожній список"

# ─── 6b. Без бібліотеки журналу — відмова, а не клас без перевірки журналу ──
X="$(mktemp -d)"
cp "$SCRIPT" "$X/review-class.sh"
out="$(printf 'docs/a.md\n' | bash "$X/review-class.sh" 2>&1)"
rc=$?
rm -rf "$X"
if [[ $rc == 2 && "$out" == *"немає"*"journal-rules.sh"* ]]; then
  ok "без journal-rules.sh — відмова, exit 2"
else
  bad "без journal-rules.sh — очікував exit 2 і «немає …journal-rules.sh», отримав $rc: $out"
fi

# ─── 7. Мутації: кожна категорія й відмова тримаються тестом ────────────────
if [[ -z "${REVIEW_CLASS_UNDER_TEST:-}" && $fail == 0 ]]; then
  M="$(mktemp -d)"
  trap 'rm -rf "$M"' EXIT
  src="$(<"$SCRIPT")"
  # Правило «журнал лише дописується» живе в journal-rules.sh, який скрипт підключає
  # поруч із собою (спільне з check-journals.sh, issue #169). Тож мутант — це тека з
  # копією скрипта і копією бібліотеки, де змінено ОДНУ з двох.
  lib="$HERE/journal-rules.sh"
  libsrc="$(<"$lib")"
  mutate() { # mutate <назва> <було> <стало> [lib] — «було» мусить стояти в скрипті (або в lib) рівно раз
    local name="$1" from="$2" to="$3" which="${4:-script}" body rest d="$M/$((++n))"
    body="$src"
    [[ "$which" == lib ]] && body="$libsrc"
    rest="${body#*"$from"}"
    if [[ "$rest" == "$body" || "$rest" == *"$from"* ]]; then
      bad "мутант «$name»: текст не знайдено рівно один раз — мутація застаріла"
      return
    fi
    mkdir -p "$d"
    cp "$SCRIPT" "$d/review-class.sh"
    cp "$lib" "$d/journal-rules.sh"
    if [[ "$which" == lib ]]; then
      printf '%s\n' "${body/"$from"/"$to"}" >"$d/journal-rules.sh"
    else
      printf '%s\n' "${body/"$from"/"$to"}" >"$d/review-class.sh"
    fi
    if REVIEW_CLASS_UNDER_TEST="$d/review-class.sh" bash "$HERE/$(basename "$0")" >"$d/out" 2>&1; then
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
  mutate "порожній вхід — звичайний" 'нічого класифікувати" >&2
  exit 2' 'нічого класифікувати" >&2
  exit 0'
  mutate "шаблон як рядок, а не glob" '[[ "$f" == ${r#*|} ]]' '[[ "$f" == "${r#*|}" ]]'
  mutate "infra/** не ризикова" "  'інфраструктура|infra/*'" ''
  mutate "CLAUDE.md не ризиковий" "  'правила й контракт|CLAUDE.md'" ''
  mutate "журнал не перевіряється" '    append_only_violated "$f" "$re" &&' '    false &&'
  mutate "без бази — «звичайний»" 'mb="$(git merge-base "$BASE" "$HEAD_REF" 2>/dev/null)" || return 0' 'mb="$(git merge-base "$BASE" "$HEAD_REF" 2>/dev/null)" || return 1' lib
  mutate "вирівнювання — теж зміна" 'gsub(/^[ \t]+|[ \t]+$/, "", f); ' '' lib
  mutate "дописане поза рядками викликів — «звичайний»" '[[ -z "$(grep -Ev -- "$row_re" <<<"$rest")" ]] && return 1' 'return 1' lib
  mutate "порядок не звіряється" \
    '[[ "$(head -n "$n" <<<"$new")" == "$old" ]] || return 0' \
    '[[ -z "$(LC_ALL=C comm -23 <(sort <<<"$old") <(sort <<<"$new"))" ]] || return 0' lib
  mutate "рядок виклику — будь-який рядок з |" "JOURNAL_ROW_RE='^\\|[0-9]{4}-[0-9]{2}-[0-9]{2}\\|'" "JOURNAL_ROW_RE='^\\|'" lib
  mutate "покази квоти не перевіряються" '[[ "$f" == "$JOURNAL" || "$f" == "$QUOTA" ]]' '[[ "$f" == "$JOURNAL" ]]'
  mutate "docs/20 не ризиковий" "  'правила й контракт|docs/20_OPEN_DECISIONS.md'" ''
  mutate "шлях у лапках не розкодовується" 'if [[ "$f" == \"*\" ]]; then' 'if false; then'
  mutate "agy-stats-summary не ризиковий" "  'правила й контракт|tools/scripts/agy-stats-summary*'" ''
  mutate "видалений журнал — «звичайний»" 'new="$(git show "$HEAD_REF:$file" 2>/dev/null)" || return 0' 'new="$(git show "$HEAD_REF:$file" 2>/dev/null)" || return 1' lib
  mutate "спільна бібліотека журналу не ризикова" "  'дозволи й безпека|tools/scripts/journal-rules*'" ''
  mutate "check-journals не ризиковий" "  'CI|tools/scripts/check-journals*'" ''
  mutate "тека журналу не перевіряється" '    journal_dir_file_violated "$f" &&' '    false &&'
  mutate "новий файл теки — будь-який зміст" 'grep -Ev -- "$JOURNAL_ROW_RE|^\|Дата\|"' 'grep -Ev -- "."' lib
  mutate "файл теки поза верхнім рівнем чи не .md — як звичайний" \
    '[[ "$file" == "$JOURNAL_DIR"/*.md && "${file#"$JOURNAL_DIR"/}" != */* ]] || return 0' \
    '[[ "$file" == "$JOURNAL_DIR"/*.md && "${file#"$JOURNAL_DIR"/}" != */* ]] || true' lib
  mutate "зміна файла теки з бази — не звіряється" '    append_only_violated "$file" "$JOURNAL_ROW_RE"
    return' '    return 1' lib
  mutate "тека журналу без бази — «звичайний»" 'fork="$(git merge-base "$BASE" "$HEAD_REF" 2>/dev/null)" || return 0' 'fork="$(git merge-base "$BASE" "$HEAD_REF" 2>/dev/null)" || return 1' lib
  mutate "виняток правил діє і в змішаному PR" '${#texts[@]} && !other))' '${#texts[@]}))'
  mutate "inputs/ — теж текст правил" "  '^docs/promts/[^/]+\\.md\$'" "  '^docs/promts/.+\\.md\$'"
  mutate "docs/16 не текст правил" "  '^docs/1[5-7]_[^/]+\\.md\$'" "  '^docs/1[57]_[^/]+\\.md\$'"
  mutate "CLAUDE.md не текст правил" "  '^CLAUDE\\.md\$'" ''
  mutate "правила-текст замість ризикового, коли журнал зіпсовано" '((!${#hits[@]} && ' '(('
  mutate "бібліотеки немає — не відмова" '  exit 2
}
# shellcheck source' '  exit 0
}
# shellcheck source'
fi

if [[ $fail == 1 ]]; then
  echo "FAIL"
  exit 1
fi
echo "Усі тести пройдено."
