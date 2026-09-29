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

# Інваріант 6 — обгортка контейнера питає guard'а `check-run`, а не `check`.
#
# ЧОМУ. `check` гейтить НАБІР задачі: kill switch + денний ліміт + пауза після
# трьох падінь. Обгортка ж стартує контейнер, і демон кличе її кілька разів на
# одну задачу (залежності, перевірка хука, агент, оракул приймання). Лічильник
# інкрементується після запуску агента, тож на останній дозволеній задачі дня
# `check` в обгортці відмовляв би кодом 11 УСІМ наступним викликам — і демон
# записував би це як червоний оракул, тобто звинувачував агента у вичерпаному
# ліміті. Прогін 2026-09-20 показав це як «падінь поспіль 2 з 3» у виводі
# ручного виклику обгортки; ціна помилки — задача, виконана правильно і
# відхилена машиною.
#
# Інваріант статичний, бо тестом його не дістати: a8-tick.test.sh підміняє
# обгортку заглушкою, і справжній шаблон там не виконується жодного разу.
RUNNER_TPL="$ROLE/templates/a8-run-agent.sh.j2"
if [[ -f "$RUNNER_TPL" ]]; then
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    violations+=("обгортка кличе 'a8-guard check' замість 'check-run' (ліміт задач відмовить оракулу кодом 11): $hit")
  done < <(grep -nE '^[^#]*a8-guard[[:space:]]+check([[:space:]]|$)' "$RUNNER_TPL" || true)
fi

# Інваріант 7 — verify.yml не судить про машину за змінною play'ю.
#
# ЧОМУ. Це третя редакція однієї й тієї самої вади за добу 2026-09-20:
#   1. V11 був `debug`, що друкував «креденшал встановлено», прочитавши змінну,
#      яку йому передали — одразу після червоного застосування, де ключ НЕ
#      встановився;
#   2. V11 навчили читати файл, але ГІЛКУВАВСЯ він і далі по
#      `a8_push_credential_kind`. `--tags verify` без `-e` брав дефолт і
#      повідомляв «КРЕДЕНШАЛА НА PUSH НЕМАЄ», тоді як у `a8.env` на машині
#      стояло `deploy_key` і ключ лежав на місці.
# Спільне в обох: перевірка описувала намір оператора, а видавала за стан
# машини. Найдорожчий клас у цьому проєкті — не «не працює», а «звітує, що
# працює».
#
# Правило: у verify.yml імені `a8_push_credential_kind` немає взагалі — ані в
# умовах, ані в текстах повідомлень. Вид креденшала здобувається читанням
# `a8.env` з машини (факт `a8_v_push_kind`). Заборона на згадку в тексті теж
# навмисна: повідомлення, що цитує змінну play'ю, читається як факт про машину.
VERIFY_TASKS="$TASKS/verify.yml"
if [[ -f "$VERIFY_TASKS" ]]; then
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    violations+=("verify.yml згадує a8_push_credential_kind — перевірка мусить читати стан З МАШИНИ (a8_v_push_kind): $hit")
  done < <(grep -n 'a8_push_credential_kind' "$VERIFY_TASKS" || true)
fi

# Інваріант 8 — булеву змінну ролі не можна вживати в умові без `| bool`.
#
# ЧОМУ. `-e a8_egress_enforce=true` з командного рядка передає РЯДОК, а не
# булеан. Далі поведінка залежить від версії ansible-core, і обидві погані:
#
#   ansible-core 2.19+ : `when: a8_egress_enforce` → помилка
#       «Conditional result (True) was derived from value of type 'str'»
#       (спостережено на A8 2026-09-21, застосування впало посередині);
#   ansible-core 2.16  : помилки НЕМАЄ, рядок "false" істинний, і задача
#       виконується. Виміряно локально тим самим днем:
#           -e flag=false →  OLD_FIRED, OLD_STATE=started
#                            NEW_STATE=stopped   (з `| bool`)
#
# Друга гілка страшніша: `-e a8_tick_timer_enabled=false` не вимкнув би
# таймер, а ЗАПУСТИВ його, мовчки. Прапорець, що робить протилежне до
# написаного, — найдорожчий клас у цьому проєкті.
#
# Правило: ім'я булевої змінної (тієї, що в defaults оголошена як true/false)
# в умові мусить мати `| bool`. У текстах повідомлень — можна й навіть краще
# без нього: там показують те, що передали.
BOOL_DEFAULTS="$ROLE/defaults/main.yml"
if [[ -f "$BOOL_DEFAULTS" && -d "$TASKS" ]]; then
  while IFS= read -r var; do
    [[ -z "$var" ]] && continue
    while IFS= read -r hit; do
      [[ -z "$hit" ]] && continue
      line="${hit#*:}"
      line="${line#*:}"
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      # `| bool` одразу після імені — інваріант виконано.
      if [[ "$line" =~ $var[[:space:]]*\|[[:space:]]*bool ]]; then
        continue
      fi
      violations+=("булева змінна '$var' в умові без '| bool' (рядок із -e зламає або інвертує): $hit")
    done < <(
      {
        grep -rnE "when:.*\\b$var\\b" "$TASKS" || true
        grep -rnE "^[[:space:]]*-[[:space:]]+(not[[:space:]]+)?\\(?$var\\)?[[:space:]]*$" "$TASKS" || true
        grep -rnE "if[[:space:]]+$var\\b" "$TASKS" || true
        # ШАБЛОНИ теж. `{% if a8_egress_enforce %}` у .j2 має ту саму ваду:
        # рядок "false" у Jinja істинний, тож при `-e …=false` відрендерився б
        # код, що ПОВЕРТАЄ правила примусу кожні 30 хв. Перша редакція
        # інваріанта дивилась лише в tasks/ і цю міну не бачила.
        grep -rnE "\\{%-? *if +$var\\b" "$ROLE/templates" 2>/dev/null || true
      }
    )
    # `grep -oE … -P` — два матчери одночасно, і grep на це відповідає
    # «conflicting matchers specified». Список змінних виходив порожній, тобто
    # інваріант «проходив», не виконавшись жодного разу. Спіймано власним
    # прогоном 2026-09-21 — і це рівно той клас, який цей файл ловить у ролі.
  done < <(sed -nE 's/^(a8_[a-z_]+): *(true|false) *(#.*)?$/\1/p' "$BOOL_DEFAULTS")
fi

# Інваріант 9 — образ агента несе всі системні бібліотеки runtime-стадії воркера.
#
# ЧОМУ. `uv sync` ставить Python-пакети, але не .so, яких потребує cadquery-ocp.
# Образ агента їх не мав, і оракул воркера на A8 давав rc=2 (handoff 2026-09-23
# §2 п.1): агент не міг довести жодної задачі в workers/cad. Живу поведінку
# доводить V18 у verify.yml, але лише після застосування ролі на машині. Тут —
# те, що CI може довести до merge: перелік у образі агента не відстає від
# еталона. Еталоном є сам cad-worker.Dockerfile, а не список, переписаний сюди:
# інакше нова бібліотека воркера лишилась би непоміченою.
#
# Порожній або відсутній еталон — теж порушення. Якщо файла немає або розбір
# нічого не знайшов (стадію перейменовано, формат змінився), інваріант інакше
# «проходив» би, не виконавшись, — той самий клас, що з grep в інваріанті 8.
# Перша редакція мовчки пропускала відсутні файли; знайшов рецензент (agy,
# Gemini 3.8 Flash, PR #142).
CAD_DOCKERFILE="$ROOT/infra/docker/cad-worker.Dockerfile"
AGENT_DOCKERFILE="$ROLE/files/agent.Dockerfile"
# apt_packages <файл> <регекс рядка FROM стадії> — пакети КОЖНОЇ інструкції
# `apt-get install` у цій стадії: від `install` до найближчого `&&`. Архітектура
# (`імʼя:amd64`) і пін версії (`імʼя=версія`) відкидаються, ім'я лишається.
apt_packages() {
  awk -v stage="$2" '
    $0 ~ stage { in_stage = 1; next }
    in_stage && /^FROM / { exit }
    in_stage && /apt-get install/ { grab = 1; sub(/.*apt-get install/, "") }
    grab {
      n = split($0, t, /[ \t\\]+/)
      for (i = 1; i <= n; i++) {
        if (t[i] == "&&") { grab = 0; break }
        if (t[i] ~ /^[a-z0-9][a-z0-9.+-]+(:[a-z0-9-]+)?(=[^ ]*)?$/) { sub(/[:=].*/, "", t[i]); print t[i] }
      }
    }' "$1" | sort -u
}
if [[ ! -f "$CAD_DOCKERFILE" || ! -f "$AGENT_DOCKERFILE" ]]; then
  violations+=("немає $CAD_DOCKERFILE або $AGENT_DOCKERFILE — паритет образу агента не перевірено")
else
  cad_pkgs="$(apt_packages "$CAD_DOCKERFILE" '^FROM .* AS runner$')"
  agent_pkgs="$(apt_packages "$AGENT_DOCKERFILE" '^FROM node:')"
  if [[ -z "$cad_pkgs" ]]; then
    violations+=("не знайдено жодного пакета в runtime-стадії (FROM … AS runner) $CAD_DOCKERFILE — паритет образу агента не перевірено")
  elif [[ -z "$agent_pkgs" ]]; then
    violations+=("в $AGENT_DOCKERFILE не знайдено apt-get install у стадії FROM node: — стадію перейменовано або бібліотек немає")
  else
    missing="$(comm -23 <(printf '%s\n' "$cad_pkgs") <(printf '%s\n' "$agent_pkgs") | tr '\n' ' ')"
    if [[ -n "${missing// /}" ]]; then
      violations+=("в образі агента ($AGENT_DOCKERFILE) бракує бібліотек runtime-стадії воркера: ${missing% } — оракул workers/cad на A8 впаде (rc=2, handoff 2026-09-23 §2 п.1)")
    fi
  fi
fi

# Інваріант 10 — образ збирається в мережі хоста, агент працює без неї.
#
# ЧОМУ. Egress-allowlist — це DROP у ланцюзі DOCKER-USER для всього, що йде з
# мосту docker0 не до адрес набору. BuildKit у dockerd виконує RUN-кроки збірки
# на тому самому мості, тож фільтр, що охороняє агента, різав і збірку образу:
# 2026-09-28 `apt-get update` з agent.Dockerfile не дістав deb.debian.org
# (connection timed out), образу не стало, і впали всі перевірки, що запускають
# контейнер (V6a у контролі й після застосування). Збірку робить роль від root
# з Dockerfile'а в git, а не агент; allowlist охороняє агента під час роботи.
#
# Три частини, і дві останні важливіші за першу:
#   а) кожен `docker build` у задачах ролі (з підтеками) несе `--network host`,
#      і це ОСТАННЄ значення `--network` у команді: повторений прапорець бере
#      останнє (`--network host --network bridge` — це bridge);
#   б) у шаблонах і файлах ролі — насамперед в обгортці a8-run-agent, єдиному місці, де
#      описано `docker run`, — немає `--network`/`--net` з БУДЬ-яким значенням.
#      Не лише `host`: мережа з `docker network create` має власний міст br-…,
#      а правила примусу стоять на одному мості, тож агент на ній вийшов би
#      з-під фільтра так само, як із `host`. І обгортку ставить саме цей
#      шаблон — інакше перевірка шаблону нічого б не доводила;
#   в) міст фільтра (`a8_egress_bridge`) — той самий, куди docker кладе
#      контейнер без `--network`: docker0, якщо daemon.json не задає "bridge".
#      Інакше агент без жодного прапорця опинився б поза фільтром.
# Дірки в а), б) і в) знайшли рецензенти PR #147. agy, Gemini 3.8 Flash: останнє
# значення, підтеки tasks/, `--net""work`, "bridge" у daemon.json, обгортка не з
# шаблону. Окрема сесія Claude: дві збірки в блоці `|`, підтеки templates/,
# host_vars.
# Жодного `docker build` у задачах, обгортки немає або в ній немає `docker run` —
# теж порушення: інакше інваріант «проходив» би, не виконавшись (той самий клас,
# що в інваріантах 8 і 9). Збірку модулем замість команди доведеться описати
# тут заново — це свідомо; `docker compose build` прапорця `--network` не має,
# тож теж червоніє.
#
# Задачу читаємо цілою, від `- name:` до наступного: рядкова форма (`command: >-`)
# і argv-форма (`- docker` / `- build` / `- --network` / `- host`) після
# склеювання рядків дають той самий текст. Збірка — `docker … build`, де між ними
# будь-які слова без `:` (`buildx`, `image`, `compose -f x.yml`); двокрапка —
# це вже наступний ключ задачі. Не рахуються коментарі й сама назва
# задачі: «Build … with --network host» у назві прапорцем не є. Команди в одній
# задачі ділимо на `&&`, `||`, `; ` і на рядки блоку `|` (там кожен рядок —
# окрема команда, на відміну від `>-`) — прапорець мусить стояти в команді
# збірки, а не в сусідній. Лапки навколо значення (`--network "host"`) не розпізнаються —
# це хибне порушення, безпечний бік; пишіть без лапок.
task_files=()
if [[ -d "$TASKS" ]]; then
  while IFS= read -r f; do task_files+=("$f"); done < <(find "$TASKS" -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)
fi
build_report="BUILDS 0 RUNNERS 0"
if [[ ${#task_files[@]} -gt 0 ]]; then
  build_report="$(awk '
    function check(seg,   rest, val) {
      if (seg !~ / docker( [^ :]+)* build( |$)/) return
      builds++
      sub(/.* docker( [^ :]+)* build( |$)/, " ", seg)
      val = ""
      rest = seg
      while (match(rest, / --network[ =][^ ]*/)) {
        val = substr(rest, RSTART, RLENGTH)
        rest = substr(rest, RSTART + RLENGTH)
      }
      sub(/^ --network[ =]/, "", val)
      if (val != "host") print "NOHOST " file ":" start
    }
    function flush(   n, i, segs) {
      inlit = 0
      if (text ~ / dest: \/usr\/local\/bin\/a8-run-agent( |$)/) {
        runners++
        if (text !~ / src: a8-run-agent\.sh\.j2( |$)/) print "RUNNERSRC " file ":" start
      }
      n = split(text, segs, /&&|\|\||; |;$/)
      for (i = 1; i <= n; i++) check(" " segs[i])
      text = ""
    }
    FNR == 1 { flush() }
    /^[ \t]*- name:/ { flush(); file = FILENAME; start = FNR; next }
    /^[ \t]*#/ { next }
    {
      match($0, /^[ \t]*/); ind = RLENGTH
      if (inlit && ind <= litind && $0 !~ /^[ \t]*$/) inlit = 0
      line = $0; sub(/^[ \t]*(-[ \t]+)?/, "", line); gsub(/[ \t]+/, " ", line)
      text = text (inlit ? " ; " : " ") line
      if ($0 ~ /:[ \t]*\|[-+]?[ \t]*$/) { inlit = 1; litind = ind }
    }
    END { flush(); print "BUILDS " builds + 0 " RUNNERS " runners + 0 }
  ' "${task_files[@]}")"
fi
while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  violations+=("docker build без --network host останнім значенням (увімкнений примус egress відріже apt-get у збірці, образу не буде; пишіть --network host без лапок): ${hit#NOHOST }")
done < <(grep '^NOHOST ' <<<"$build_report" || true)
while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  violations+=("обгортку ставить не шаблон a8-run-agent.sh.j2 — перевірка шаблону нічого не доводить: ${hit#RUNNERSRC }")
done < <(grep '^RUNNERSRC ' <<<"$build_report" || true)
if [[ "$build_report" == *"BUILDS 0 "* ]]; then
  violations+=("у $TASKS немає жодного 'docker build' — мережу збірки образу агента не перевірено")
fi
if [[ "$build_report" == *"RUNNERS 0"* ]]; then
  violations+=("у $TASKS немає задачі з 'dest: /usr/local/bin/a8-run-agent' — не видно, звідки береться обгортка")
fi
if [[ ! -f "$RUNNER_TPL" ]]; then
  violations+=("немає обгортки $RUNNER_TPL — мережу контейнера агента не перевірено")
elif ! grep -qE '^[^#]*docker[[:space:]]+run([[:space:]]|$)' "$RUNNER_TPL"; then
  violations+=("в обгортці $RUNNER_TPL не знайдено 'docker run' — мережу контейнера агента не перевірено")
fi
# Шукаємо в усьому, що роль кладе на хост: templates/ і files/ з підтеками
# (Ansible бере `src: helpers/x.sh.j2`). Підтеки знайшла окрема сесія Claude,
# PR #147.
if [[ -d "$ROLE/templates" || -d "$ROLE/files" ]]; then
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    violations+=("шаблон чи файл ролі задає мережу контейнера (агент вийде з-під egress-фільтра): $hit")
  done < <(
    # Знімаємо лише те, що точно не дійде до docker: рядок-коментар, `` `# …` ``
    # посеред команди і Jinja-коментар `{# … #}` в одному рядку. Коментар у
    # кінці рядка коду НЕ знімаємо: ` #` усередині лапок коментарем не є, і
    # зрізання ховало б прапорець після нього. Потім прибираємо лапки й `\`:
    # bash склеює `--net""work` і `--net\work` у `--network`.
    find "$ROLE/templates" "$ROLE/files" -type f 2>/dev/null | sort | while IFS= read -r f; do
      sed -E -e 's/^[[:space:]]*#.*$//' -e 's/`#[^`]*`//g' -e 's/\{#.*#\}//g' -e "s/[\"'\\\\]//g" "$f" |
        grep -nE -e '--net(work)?([[:space:]=]|$)' | sed "s|^|$f:|" || true
    done
  )
fi
DAEMON_TPL="$ROLE/templates/daemon.json.j2"
docker_bridge="docker0"
if [[ -f "$DAEMON_TPL" ]] && grep -q '"bridge"' "$DAEMON_TPL"; then
  docker_bridge="$(sed -nE 's/.*"bridge"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' "$DAEMON_TPL" | tail -1)"
  docker_bridge="${docker_bridge:-<не розібрано>}"
fi
# Міст фільтра задається де завгодно з вищим за defaults пріоритетом:
# group_vars/*, host_vars/** (окрема сесія Claude, PR #147, знайшла host_vars).
# Тому звіряємо КОЖНЕ присвоєння, а не «останнє за пріоритетом»: розходження в
# будь-якому з них — розходження на якомусь хості. Vault-файли пропускаємо —
# вони зашифровані; інвентар і `-e` статично не видно.
ANSIBLE_DIR="$ROOT/infra/ansible"
egress_sources=()
while IFS= read -r f; do egress_sources+=("$f"); done < <(
  {
    [[ -f "$ROLE/defaults/main.yml" ]] && echo "$ROLE/defaults/main.yml"
    find "$ANSIBLE_DIR/group_vars" "$ANSIBLE_DIR/host_vars" -type f \( -name '*.yml' -o -name '*.yaml' \) \
      ! -name '*vault*' 2>/dev/null | sort
  }
)
egress_bridges=""
if [[ ${#egress_sources[@]} -gt 0 ]]; then
  egress_bridges="$(grep -H -E '^a8_egress_bridge:' "${egress_sources[@]}" || true)"
fi
if [[ -z "$egress_bridges" ]]; then
  violations+=("a8_egress_bridge не знайдено ні в defaults, ні в group_vars/host_vars — не видно, на якому мості стоїть egress-фільтр")
fi
while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  # `'docker0'` і `"docker0"` — те саме значення YAML, що й docker0.
  val="$(sed -nE "s/^[^:]*:a8_egress_bridge:[[:space:]]*[\"']?([^\"'#[:space:]]*)[\"']?.*/\1/p" <<<"$hit")"
  if [[ "$val" != "$docker_bridge" ]]; then
    violations+=("міст egress-фільтра ($val) не той, куди docker кладе контейнер без --network ($docker_bridge, daemon.json.j2) — агент поза фільтром: ${hit%%:a8_egress_bridge*}")
  fi
done <<<"$egress_bridges"

# Інваріант 11 — `uv sync` для агента ставить те саме, що CI.
#
# ЧОМУ. CI ставить `uv sync --extra dev` (.github/workflows/ci.yml): pytest, mypy
# і ruff живуть в extra `dev` (workers/cad/pyproject.toml). Тік, V18c і
# autorun.sh робили голий `uv sync`, тож у контейнері агента pytest не було.
# Застосування 2026-09-29: V18e — rc=2, «Failed to spawn: `pytest` … No such
# file or directory». З тієї самої причини впав би оракул кожної задачі в
# workers/cad і pre-commit на кожному Python-коміті (lefthook: `uv run ruff`,
# `uv run mypy`).
#
# Еталон — рядок `uv sync` у CI, а не список, переписаний сюди: нове extra в CI
# без правки ролі червонить інваріант. Немає еталона або жодного `uv sync` у
# ролі — теж порушення (той самий клас, що в інваріантах 8–10).
#
# Дірки першої редакції знайшов рецензент (agy, Gemini 3.8 Flash, PR #148):
# `--no-dev` поруч з `--extra dev`, `# --extra dev` у коментарі в кінці рядка,
# `--group` у CI, `\` і `run: |` у CI, handlers/ і files/, лапки навколо значення,
# друга згадка `uv sync` у тому самому рядку. Звідси правила нижче.
#
# Де шукаємо: усі файли ролі, крім .md (задачі, handlers, шаблони, files), і
# tools/scripts/autorun.sh — той самий крок для локального автономного прогону.
# У CI — будь-який рядок ci.yml, після склеювання продовжень `\`: і `run: uv sync`,
# і `cd … && uv sync` у блоці `run: |`.
#
# Що таке команда: кожне входження `uv sync` (і `uv --directory X sync`) у рядку
# окремо, якщо за ним іде прапорець, кінець рядка чи межа команди (`)`, лапка,
# `;`, `&`, `|`). Проза на кшталт «uv sync падає» чи «uv sync: пройшов» командою
# не є. Аргументи команди — до межі команди або ` #` (коментар у кінці рядка).
# Лапки навколо значення (`--extra "dev"`) знімаються. Цілі рядки-коментарі й
# `` `# …` `` посеред команди не рахуються.
#
# Що вимагаємо: кожне `--extra X` / `--group X` з CI — у кожній команді агента
# (або `--all-extras` / `--all-groups`); `--all-*` з CI — дослівно. І жодного
# прапорця, що звужує набір (`--no-dev`, `--only-dev`, `--no-default-groups`,
# `--no-group`, `--only-group`, `--no-extra`), якого немає в CI.
CI_WF="$ROOT/.github/workflows/ci.yml"
UV_CMD_RE='^([[:space:]]+-|[[:space:]]*$|[[:space:]]*[)'"'"'";&|])'
# uv_tails — stdin: рядки «N<TAB>текст»; stdout: «N<TAB>аргументи» кожної команди uv sync.
uv_tails() {
  local n l rest
  while IFS=$'\t' read -r n l; do
    l="$(sed -E -e "s/(--(extra|group)[= ])[\"']([^\"']+)[\"']/\\1\\3/g" \
      -e 's/uv[[:space:]]+--(directory|project)[= ][^[:space:]]+[[:space:]]+sync/uv sync/g' <<<"$l")"
    rest="$l"
    while [[ "$rest" == *"uv sync"* ]]; do
      rest="${rest#*uv sync}"
      [[ "$rest" =~ $UV_CMD_RE ]] || continue
      printf '%s\t%s\n' "$n" "$(sed -E "s/([[:space:]]#|[)'\";&|]).*//" <<<"$rest")"
    done
  done
}
# strip_comments <файл> — рядки «N<TAB>текст» без рядків-коментарів і `` `# …` ``.
strip_comments() {
  sed -E -e 's/^[[:space:]]*#.*$//' -e 's/`#[^`]*`//g' "$1" | awk '{ printf "%d\t%s\n", NR, $0 }'
}
UV_NARROW_RE='--no-dev|--only-dev|--no-default-groups|--no-group[= ][^[:space:]]+|--only-group[= ][^[:space:]]+|--no-extra[= ][^[:space:]]+'
ci_raw=""
if [[ -f "$CI_WF" ]]; then
  ci_raw="$(sed -e ':a' -e '/\\$/N; s/\\\n[[:space:]]*/ /; ta' "$CI_WF" | sed -E 's/^[[:space:]]*#.*$//' |
    awk '{ printf "%d\t%s\n", NR, $0 }' | { grep -E 'uv[[:space:]]' || true; } | uv_tails)"
  # `|| true` — не косметика: без збігів grep повертає 1, і під pipefail + set -e
  # скрипт помирав би мовчки з кодом 1, без жодного повідомлення. Спіймано тестом
  # u7, щойно він почав звіряти текст порушення, а не лише код.
fi
if [[ -z "$ci_raw" ]]; then
  violations+=("у $CI_WF немає команди 'uv sync …' — не видно, що ставить CI, паритет uv sync агента не перевірено")
else
  ci_tails="$(cut -f2 <<<"$ci_raw")"
  ci_reqs="$(grep -oE -- '--(extra|group)[= ][^[:space:]]+|--all-(extras|groups)' <<<"$ci_tails" | sed -E 's/^--(extra|group)=/--\1 /' | sort -u || true)"
  ci_narrow="$(grep -oE -- "$UV_NARROW_RE" <<<"$ci_tails" | sort -u || true)"
  uv_files=()
  while IFS= read -r f; do uv_files+=("$f"); done < <(
    {
      find "$ROLE" -type f ! -name '*.md' 2>/dev/null
      [[ -f "$ROOT/tools/scripts/autorun.sh" ]] && echo "$ROOT/tools/scripts/autorun.sh"
    } | sort
  )
  uv_hits=0
  for f in "${uv_files[@]}"; do
    while IFS=$'\t' read -r n cmd; do
      [[ -z "$n" ]] && continue
      uv_hits=$((uv_hits + 1))
      while IFS= read -r req; do
        [[ -z "$req" ]] && continue
        case "$req" in
          --all-extras | --all-groups)
            [[ "$cmd" =~ (^|[[:space:]])$req([[:space:]]|$) ]] && continue ;;
          --extra\ *)
            [[ "$cmd" =~ (^|[[:space:]])--all-extras([[:space:]]|$) ]] && continue
            [[ "$cmd" =~ (^|[[:space:]])--extra[[:space:]=]${req#--extra }([[:space:]]|$) ]] && continue ;;
          --group\ *)
            [[ "$cmd" =~ (^|[[:space:]])--all-groups([[:space:]]|$) ]] && continue
            [[ "$cmd" =~ (^|[[:space:]])--group[[:space:]=]${req#--group }([[:space:]]|$) ]] && continue ;;
        esac
        violations+=("uv sync без '$req', який ставить CI (без нього в контейнері немає pytest/mypy/ruff — оракул і pre-commit Python падають): $f:$n")
      done <<<"$ci_reqs"
      while IFS= read -r narrow; do
        [[ -z "$narrow" ]] && continue
        grep -qxF -- "$narrow" <<<"$ci_narrow" && continue
        violations+=("uv sync звужує набір прапорцем '$narrow', якого в CI немає (агентові бракуватиме того, що є в CI): $f:$n")
      done < <(grep -oE -- "$UV_NARROW_RE" <<<"$cmd" | sort -u || true)
    # Попередній фільтр: розбір іде по рядку з `sed` на кожен, тож без нього
    # один прогін на всій ролі тривав ~15 с.
    done < <(strip_comments "$f" | grep -E 'uv[[:space:]]' | uv_tails)
  done
  if ((uv_hits == 0)); then
    violations+=("у ролі A8 і autorun.sh не знайдено жодного 'uv sync' — паритет із CI не перевірено")
  fi
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

echo "✓ Інваріанти ролі A8: include_tasks з apply, pipefail під bash, контейнер через argv, зонд без shell-змінних і без login-shell, обгортка через a8-guard check-run, verify не судить про машину за змінною play'ю, булеві змінні в умовах через | bool, образ агента несе всі бібліотеки воркера, образ збирається з --network host, а агент запускається без --network, uv sync агента ставить те саме, що CI"
