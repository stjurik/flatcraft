#!/usr/bin/env bash
# check-ansible-a8.sh — статичні інваріанти ролі A8 (infra/ansible/roles/a8).
#
# ЧОМУ ЦЕЙ СКРИПТ ІСНУЄ. Перше справжнє застосування ролі на A8 (2026-09-19)
# знайшло три вади ПОСПІЛЬ, і всі три — одного кореня: код був написаний,
# залінтований і змерджений, але жодного разу не виконувався проти живої
# машини. `ansible-lint` жодну з них не бачить: вони семантичні, не
# синтаксичні.
#
#   1. `include_tasks: verify.yml` з `tags: [verify, never]` БЕЗ `apply:`.
#      include динамічний, тож теги діяли лише на сам рядок include — задачі
#      всередині відфільтровувались усі до одної. `--tags verify` давав
#      `ok=2` (Gathering Facts + include) і не перевіряв НІЧОГО.
#   2. `set -o pipefail` у модулі `shell` без bash. /bin/sh в Ubuntu — dash:
#      `/bin/sh: 1: set: Illegal option -o pipefail`.
#   3. Зонд у контейнер рядковою формою `command:` замість `argv:`. Ansible
#      для become загортає команду в `sh -c` НА ХОСТІ, і той шар розкривав
#      `$HOME` і `$p` раніше, ніж вони доходили до `docker run`. V6a падала
#      хибно; V12a була б гіршою — вона б «проходила» з порожнім `$p`,
#      перевіряючи не ті шляхи й не помічаючи цього.
#
# Спільна риса всіх трьох: зелений лінт і мовчазна недієздатність. Саме цей
# клас CLAUDE.md §0 п.6 вимагає закривати механізмом, а не уважністю.
#
# Використання (без аргументів; шляхи — відносно кореня репозиторію):
#   tools/scripts/check-ansible-a8.sh
#   ROOT=/шлях/до/репо tools/scripts/check-ansible-a8.sh
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
PLAYBOOK="$ROOT/infra/ansible/a8.yml"
ROLE="$ROOT/infra/ansible/roles/a8"
TASKS="$ROLE/tasks"

violations=()

# Інваріант 1 — кожен `include_tasks` з тегами має `apply:`.
#
# Шукаємо рядки `include_tasks` у рядковій формі (`include_tasks: файл.yml`).
# Саме вона не вміє `apply:` — у неї немає місця, куди його покласти. Форма
# з відображенням (`include_tasks:` + `file:` + `apply:`) інваріант виконує.
if [[ -d "$TASKS" ]]; then
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    violations+=("include_tasks у рядковій формі (теги не дійдуть до задач): $hit")
  done < <(grep -rn -E '^\s*(ansible\.builtin\.)?include_tasks:\s*\S+\.yml\s*$' "$TASKS" || true)
fi

# Інваріант 2 — `set -o pipefail` вимагає bash.
#
# Або play задає `ansible_shell_executable: /bin/bash` (одне місце на всі
# задачі), або кожна задача з pipefail несе `executable:` сама. Перше — те,
# що зроблено; друге лишається допустимим, щоб інваріант не диктував стиль.
# Рахуємо через `grep -o | wc -l`, а не `grep -c` у конвеєрі: під
# `set -euo pipefail` grep без збігів повертає 1 і вбиває скрипт мовчки, тобто
# «нічого не знайдено» ставало б «перевірки не було». Прецедент — цей самий
# скрипт на першому прогоні тесту 2026-09-19.
count_matches() {
  local pattern="$1" path="$2"
  if [[ ! -e "$path" ]]; then
    echo 0
    return 0
  fi
  # `|| true` саме тут, ДО конвеєра: grep без збігів віддає 1, і під pipefail
  # цього досить, щоб функція впала, а скрипт мовчки завершився з exit 1.
  { grep -rhoE "$pattern" "$path" 2>/dev/null || true; } | wc -l | tr -d ' '
}

pipefail_count="$(count_matches 'set -o pipefail' "$TASKS")"
if [[ "$pipefail_count" -gt 0 ]]; then
  play_sets_bash=0
  if [[ -f "$PLAYBOOK" ]] && grep -qE '^[[:space:]]*ansible_shell_executable:[[:space:]]*/bin/bash[[:space:]]*$' "$PLAYBOOK"; then
    play_sets_bash=1
  fi
  executable_count="$(count_matches '^[[:space:]]*executable:[[:space:]]*/bin/bash[[:space:]]*$' "$TASKS")"
  if [[ "$play_sets_bash" -eq 0 && "$executable_count" -lt "$pipefail_count" ]]; then
    violations+=("$pipefail_count задач із 'set -o pipefail', але play не задає ansible_shell_executable: /bin/bash, і лише $executable_count задач мають власний executable. /bin/sh в Ubuntu — dash, pipefail він не знає")
  fi
fi

# Інваріант 3 — виклик контейнера через обгортку йде формою `argv:`.
#
# Ловимо `a8-run-agent` у рядку, що є продовженням рядкової форми модуля
# (`command: >-` / `shell: >-` / просто рядок). В argv-формі шлях до обгортки
# стоїть окремим елементом списку, тобто рядком, що починається з `- `.
if [[ -d "$TASKS" ]]; then
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    line="${hit#*:}"
    line="${line#*:}"
    # Елемент списку argv — допустимо. Коментар — теж (пояснення, не код).
    # Явний `if`, а не `[[ … ]] && continue`: під `set -e` хибний тест у такій
    # формі повертає 1 і вбиває скрипт, перетворюючи «порушень немає» на
    # мовчазне падіння. Спіймано власним тестом 2026-09-19.
    if [[ "$line" =~ ^[[:space:]]*-[[:space:]] ]]; then
      continue
    fi
    if [[ "$line" =~ ^[[:space:]]*# ]]; then
      continue
    fi
    # Задачі, що обгортку ВСТАНОВЛЮЮТЬ (`src:`/`dest:` у template/copy), її не
    # викликають — для них інваріант не має сенсу.
    if [[ "$line" =~ ^[[:space:]]*(src|dest|path|creates|removes):[[:space:]] ]]; then
      continue
    fi
    # Проза, що ЦИТУЄ команду (напр. підказка в `fail_msg`), — не виклик.
    # Конвенція репозиторію: команда в тексті береться у зворотні лапки, а
    # справжній рядок argv або `command:` їх не містить ніколи. Спіймано на
    # власному хибному спрацюванні 2026-09-19, коли підказка V10b цитувала
    # `a8-run-agent … bash -c printenv`.
    if [[ "$line" == *'`'* ]]; then
      continue
    fi
    violations+=("виклик a8-run-agent НЕ через argv (хостовий sh -c розкриє \$-змінні до docker run): $hit")
  done < <(grep -rn -E 'a8-run-agent' "$TASKS" || true)
fi

# Інваріант 4 — у зонді, що йде в контейнер, немає shell-змінних.
#
# ЧОМУ. `$HOME` у зонді V6a розкривався десь між Ansible і `docker run`: під
# `agent` виходило `/home/agent` замість `/home/agent/container-home`, і зонд
# падав, хоча середовище було справне. Перехід на `argv:` цього НЕ виправив
# (2026-09-19, PR #120) — три незалежні виміри показали, що контейнер, bash і
# тека в порядку, ламався лише текст зонда. Висновок: не з'ясовувати, який шар
# винен, а не пускати змінну в текст узагалі. Потрібне значення вже знає
# Ansible — підставляй його Jinja-літералом; потрібне значення знає лише
# контейнер — читай його `printenv`, без `$`.
#
# Інваріант 3 цього не ловив: він перевіряє ФОРМУ виклику, а не вміст зонда.
# Вікно — від рядка з `a8-run-agent` до `register:`, яким тут закінчується
# кожна така задача.
if [[ -d "$TASKS" ]]; then
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    violations+=("shell-змінна в зонді до контейнера (значення може не доїхати): $hit")
  done < <(
    {
      find "$TASKS" -name '*.yml' -print0 2>/dev/null |
        xargs -0 awk '
          /^- name:/                        { inprobe = 0 }
          /a8-run-agent/ && $0 !~ /^[[:space:]]*#/ { inprobe = 1; next }
          inprobe && /^[[:space:]]*register:/ { inprobe = 0 }
          inprobe && /\$/ && $0 !~ /^[[:space:]]*#/ { print FILENAME ":" FNR ":" $0 }
        ' 2>/dev/null || true
    }
  )
fi

# Інваріант 5 — зонд у контейнер не викликає login-shell.
#
# ЧОМУ. `bash -lc` читає /etc/profile, а той ПЕРЕЗАДАЄ PATH: `-e PATH=…`, який
# передає a8-run-agent разом із `node_modules/.bin`, зникає цілком. Виміряно
# парою з контролем 2026-09-19, різниця в одному символі:
#   bash -lc printenv → PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/games:…
#   bash -c  printenv → PATH=/home/agent/hart/node_modules/.bin:/usr/local/sbin:…
# Через це V10 падала при справному середовищі: lefthook лежав на місці, а
# зонд дивився в інший PATH. Клас той самий, що й з `$` у зонді: текст зонда
# ламає вимір, а виглядає це як поломка середовища.
if [[ -d "$TASKS" ]]; then
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    violations+=("login-shell у зонді до контейнера (перезадасть PATH із /etc/profile): $hit")
  done < <(
    {
      find "$TASKS" -name '*.yml' -print0 2>/dev/null |
        xargs -0 awk '
          /^- name:/                        { inprobe = 0 }
          /a8-run-agent/ && $0 !~ /^[[:space:]]*#/ { inprobe = 1; next }
          inprobe && /^[[:space:]]*register:/ { inprobe = 0 }
          inprobe && /^[[:space:]]*-[[:space:]]*-[a-z]*l[a-z]*c?[[:space:]]*$/ && $0 !~ /^[[:space:]]*#/ { print FILENAME ":" FNR ":" $0 }
        ' 2>/dev/null || true
    }
  )
fi

if [[ ${#violations[@]} -gt 0 ]]; then
  echo "::error::Інваріанти ролі A8 порушено (${#violations[@]}):" >&2
  for v in "${violations[@]}"; do
    echo "  • $v" >&2
  done
  echo >&2
  echo "Пояснення кожного інваріанта — у шапці tools/scripts/check-ansible-a8.sh." >&2
  exit 1
fi

echo "✓ Інваріанти ролі A8: include_tasks з apply, pipefail під bash, контейнер через argv, зонд без shell-змінних і без login-shell"
