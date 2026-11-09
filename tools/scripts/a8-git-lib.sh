# shellcheck shell=bash
# a8-git-lib.sh — єдина обгортка git на хості для ВСІХ скриптів A8 (#276, #291).
#
# Раніше hgit жив лише в a8-tick.sh.j2, і решта git на хості від agent
# (a8-requeue.sh, a8-queue.sh, verify.yml) працювала в тому ж головному клоні
# БЕЗ цих перевірок і ключів (#291). Тепер усі вони сорсять цей файл і ходять
# у git через hgit / HGIT_SAFE — одна копія, а не копія в кожному скрипті.
#
# Сорситься ПІСЛЯ `source "$CONFIG"`: функції читають A8_REPO_DIR, A8_KILL_SWITCH
# у момент виклику. Необов'язкові змінні викликача (під `set -u` безпечні):
#   unsafe        — файл, куди писати причину відмови (finish тіку його читає);
#                   без нього причина йде лише в stderr.
#   id            — id задачі для тексту kill switch; типово «?».
#   git_snapshot  — знімок identity .git (нижче); порожній → перевірку пропущено.
#
# Тік працює на хості від agent, а через групу docker це root. Головний клон
# контейнер агента бачить на запис разом із .git: без цієї обгортки хук чи ключ
# конфігу, підкладений контейнером, виконався б тут, поза allowlist мережі.
#
# Захист у чотири шари, і кожен закриває те, чого не закриває інший:
#   1. a8-run-agent монтує саму `.git` (bind onto self) — тоді `rename(.git)` з
#      контейнера дає EBUSY, бо це точка монтування; `.git/config` і `.git/hooks`
#      (і `.git/worktrees`, якщо є) — поверх, лише для читання. Без шару 1
#      контейнер робив би `mv .git .git-old` і клав свій `.git` (перевірено
#      рецензією #290: без bind самого `.git` перейменування проходить, навіть
#      коли config/hooks — підмонтування; EBUSY дає лише bind на саму `.git`).
#   2. Перевірки git_unsafe_reason (fail closed). Файл, якого в клоні немає,
#      змонтувати наперед не можна, а git знайде його сам: `.git/commondir`
#      переводить git на чужу теку з чужими config і hooks (виміряно на git 2.43);
#      симлінк `.git`/`config`/`hooks`/`worktrees` — те саме; симлінк УСЕРЕДИНІ
#      `.git/worktrees/` — пастка для `git worktree prune` (#292); alternates,
#      grafts і shallow підміняють історію та об'єкти (refs/replace вимикає
#      GIT_NO_REPLACE_OBJECTS). ПЛЮС знімок identity: тік перед першим контейнером
#      запам'ятовує dev:inode `.git`, `.git/config`, `.git/hooks` і хеш `config`
#      (`snapshot_git`); якщо після контейнера щось із цього інше — fail closed.
#      Знімок ловить підміну `.git` навіть там, де шару 1 чомусь немає.
#   3. `-c` для кожного ключа, що виконує команду або підміняє, куди йде git,
#      і `core.commitGraph=false` — підроблений `.git/objects/info/commit-graph`
#      міг би збрехати `diff`/`rev-list` про дерево коміту (контрприклад Argon
#      CX2, #290); з вимкненим графом git читає самі об'єкти. Крім uploadpack і
#      receivepack: для них git бере ПЕРШЕ значення, тобто з конфігу репозиторію,
#      а `-c` лише друкує «more than one uploadpack given, using the first»
#      (виміряно на git 2.43). Їх фіксують опції самих команд:
#      `fetch --upload-pack=git-upload-pack`, `push --receive-pack=git-receive-pack`.
#   4. `-C "$A8_REPO_DIR"` вшито в обгортку: git ніколи не працює в теці worktree.
#      Контейнер міг переписати "$wt/.git" (файл `gitdir: …`) на власний gitdir зі
#      своїм конфігом, хуками й об'єктами. Посилання й об'єкти worktree і головного
#      клону спільні, тож усе потрібне є тут, за повними SHA. Операції над $wt
#      (status, HEAD, коміти) роблять `--work-tree="$wt"` + адмінка worktree в
#      головному клоні, а не `git -C "$wt"` (a8-requeue.sh).
#
# ЧОМУ ПЕРЕВІРКА НЕ МАЄ ГОНКИ. Тік викликає git лише тоді, коли контейнера немає.
# `docker run --rm` у a8-run-agent закінчується разом із процесом агента; а якщо
# агента вбито по таймауту чи на шляху зупинки, викликач спершу ПЕРЕКОНУЄТЬСЯ, що
# контейнер зник (`ensure_container_gone`), і лише тоді кличе git. Доти поміж
# перевіркою і git жоден процес контейнера не живе, щоб змінити `.git` (рецензія
# #290: раніше код `docker kill` проковтувався, і живий контейнер лишав вікно).
# Решта викликачів дотримує того самого через tick.lock (тік тримає його всю
# задачу, тож вільний lock = контейнера тіку немає): a8-requeue.sh бере його
# перед усім; a8-queue enqueue — лише на час show-ref, а коли тік зайнятий,
# читає ref-файли як дані, без git (#302 C); a8-report.sh кличе hgit лише
# під `flock -n` того самого lock (#302 F).
#
# МЕЖА. `include.path`, `includeIf` і `filter.<будь-що>.*` через `-c` не
# обнулити: файлові include розкриваються під час читання конфігу, а фільтр
# може мати будь-яке ім'я. Від них захищають шари 1 і 2 (config `:ro` + знімок),
# а не цей список. Порожній `diff.external` git не знімає, а пробує запустити «»
# і падає — тобто нічого не виконує; diff тіку все одно `--name-only`.
#
# Порушення пише причину в "$unsafe" (його читає finish) і повертає 125:
# git не запускається зовсім, задача стає failed з поясненням.
HGIT_SAFE=(
  -c core.hooksPath=/dev/null
  -c core.fsmonitor=false
  -c core.sshCommand=ssh
  -c core.askPass=
  -c credential.helper=
  -c diff.external=
  -c core.pager=cat
  -c core.editor=false
  -c core.gitProxy=
  -c protocol.ext.allow=never
  -c core.alternateRefsCommand=
  -c core.commitGraph=false
  -c gc.auto=0
  -c maintenance.auto=false
)
# gc.auto=0 + maintenance.auto=false — жоден git A8 не має права запускати
# фоновий `gc --auto`/maintenance (#292, рецензія #290 коло 3 п.1). Вимірено на
# git 2.43: `git worktree prune` (яке gc викликає) йде за симлінком, покладеним
# усередину `.git/worktrees/`, і стирає ВМІСТ теки-цілі симлінка. Саму пастку
# ловить git_unsafe_reason (нижче) ще до запуску git; ці ключі — другий шар:
# навіть якби якийсь виклик проскочив, авто-gc→prune не відпрацює.
# credential.helper — порожній, бо git A8 на помічника не покладається: fetch іде
# анонімно, push — через GIT_SSH_COMMAND (deploy_key) або GIT_ASKPASS
# (token_file). Помічник із конфігу репозиторію тут лише шкодив би.

# Знімок identity .git — dev:inode трьох шляхів і хеш config. `mv .git .git-old`
# міняє dev:inode `.git`; підміна config міняє хеш. Легка робота агента (коміт у
# worktree) цього не чіпає: config і hooks — `:ro`, а нові об'єкти/рефи inode
# самої теки `.git` не змінюють. Порожній рядок від stat/sha (шлях зник) теж не
# збігається зі знімком — отже теж fail closed.
git_snapshot=""
git_identity() {
  local g="$A8_REPO_DIR/.git"
  stat -c '%d:%i' "$g" "$g/config" "$g/hooks" 2>/dev/null
  sha256sum "$g/config" 2>/dev/null | cut -d' ' -f1
}
snapshot_git() { git_snapshot="$(git_identity)"; }

git_unsafe_reason() { # друкує причину, якщо .git головного клону довіряти не можна
  local g="$A8_REPO_DIR/.git" f sym="" symrc=0
  # Будь-який симлінк усередині .git (#302 A, рецензія #299). git на хості ПИШЕ
  # за симлінком: fetch перезаписує ціль FETCH_HEAD і дописує рядок у ціль
  # reflog (logs/…), а ціль може бути будь-яким файлом agent — last-results
  # guard'а (обхід паузи «3 падіння поспіль»), STOP, authorized_keys. Сам git
  # симлінків у .git не створює, тож легітимного симлінка тут немає. Пропускаємо
  # лише файли loose-об'єктів (objects/xx/…): їх тисячі, а git пише туди через
  # тимчасовий файл і rename, тож симлінк-файл там нічого не дасть; теки objects/xx,
  # pack/ і info/ — перевіряємо. Жорсткі посилання сюди не лягають: щоб їх зробити,
  # контейнер мусить бачити ціль, а журнали guard'а й ключі agent йому не змонтовано.
  if [[ -d "$g" && ! -L "$g" ]]; then
    sym="$(find "$g" -path "$g/objects/??/*" -prune -o -type l -print -quit 2>/dev/null)" || symrc=$?
  fi
  if [[ -L "$g" || ! -d "$g" ]]; then
    echo ".git — не тека або симлінк"
  elif [[ -e "$g/commondir" || -L "$g/commondir" ]]; then
    echo ".git/commondir існує — git узяв би config і hooks з іншої теки"
  elif [[ -L "$g/config" || ! -f "$g/config" ]]; then
    echo ".git/config — не звичайний файл або симлінк"
  elif [[ -L "$g/hooks" || ! -d "$g/hooks" ]]; then
    echo ".git/hooks — не тека або симлінк"
  elif [[ -L "$g/worktrees" ]]; then
    echo ".git/worktrees — симлінк (чужий gitdir через worktree add)"
  elif [[ -d "$g/worktrees" ]] && find "$g/worktrees" -maxdepth 1 -type l -print -quit 2>/dev/null | grep -q .; then
    # Симлінк УСЕРЕДИНІ .git/worktrees/ (не сама тека). Легітимний запис worktree
    # — завжди тека; симлінк кладе контейнер. git worktree prune (зокрема через
    # gc --auto після fetch) пішов би за ним і стер теку-ціль (#292, відтворено
    # на git 2.43). Законні записи (теку створює `worktree add` тіку) не чіпаємо.
    echo ".git/worktrees/ містить симлінк — git worktree prune стер би теку-ціль"
  elif ((symrc != 0)); then
    echo ".git не вдалося обійти (find rc=$symrc) — симлінки всередині не перевірено"
  elif [[ -n "$sym" ]]; then
    echo ".git містить симлінк ${sym#"$g"/} — git на хості писав би за ним у чужий файл (#302)"
  elif [[ -n "$git_snapshot" && "$(git_identity)" != "$git_snapshot" ]]; then
    echo ".git, .git/config чи .git/hooks змінили identity після контейнера"
  else
    for f in objects/info/alternates info/grafts shallow; do
      if [[ -e "$g/$f" || -L "$g/$f" ]]; then
        echo ".git/$f існує — підміняє історію чи об'єкти"
        return 0
      fi
    done
  fi
}
hgit() {
  local why
  why="$(git_unsafe_reason)"
  if [[ -n "$why" ]]; then
    [[ -s "${unsafe:-/dev/null}" ]] || printf '%s\n' "$why" >"${unsafe:-/dev/null}"
    # Зміна identity `.git` ПІСЛЯ знімка — це підміна контейнером, не просто
    # зламаний клон: STOP усієї черги (рецензія #290 коло 2), інакше підмінена
    # `.git` без bind-монтування дожила б до наступного тіку. Решта причин
    # (симлінк, commondir…) може бути й на першому тіку до будь-якого контейнера
    # — там лише fail цієї задачі. noclobber: причину людини не затираємо.
    if [[ "$why" == *"змінили identity"* ]]; then
      (
        set -o noclobber
        printf '.git головного клону підмінено під час задачі %s (%s): %s. git на хості зупинено. Ліки: перевірити %s, відновити клон, зняти %s.\n' \
          "${id:-?}" "$(date -u +%FT%TZ)" "$why" "$A8_REPO_DIR" "$A8_KILL_SWITCH" >"$A8_KILL_SWITCH"
      ) 2>/dev/null
    fi
    echo "a8-git: небезпечний .git: $why — git не запущено" >&2
    return 125
  fi
  # HGIT_TIMEOUT (секунди) — для мережевих операцій (fetch у a8-requeue.sh):
  # завислий git інакше тримав би tick.lock без кінця. Гейт і ключі ті самі;
  # timeout лише обмежує час. Обидва рядки несуть GIT_NO_REPLACE_OBJECTS,
  # HGIT_SAFE і -C — інваріант 16c звіряє кожен.
  if [[ -n "${HGIT_TIMEOUT:-}" ]]; then
    GIT_NO_REPLACE_OBJECTS=1 timeout "$HGIT_TIMEOUT" git "${HGIT_SAFE[@]}" -C "$A8_REPO_DIR" "$@"
  else
    GIT_NO_REPLACE_OBJECTS=1 git "${HGIT_SAFE[@]}" -C "$A8_REPO_DIR" "$@"
  fi
}

# ─── Неіндексоване поза правилами ігнору бази (#302 B, рецензія #299) ────────
# Перевірка «дерево worktree == дерево коміту» (тік #294, a8-requeue) будує
# дерево через `add -A`, а той бере правила ігнору З САМОГО worktree: вкладений
# `.gitignore` з `*`, `.git/info/exclude` головного клону (записуваний з
# контейнера), core.excludesFile. Агент кладе `sub/conftest.py` поруч із
# `sub/.gitignore` → `add -A` його не бачить, дерево == $tip, а оракул файл
# бачить і виконує (відтворено прогоном на git 2.43, рецензія #299 B).
#
# Тому неіндексоване рахуємо ще раз — з правилами, яких агент змінити не може:
# з усіх `.gitignore` коміту, який дає викликач (тік — база задачі, requeue —
# свіжий origin/main), без --exclude-standard (тобто без info/exclude,
# core.excludesFile і `.gitignore` з диска). Правило вкладеного `.gitignore`
# теки D переписується від кореня: шаблон без «/» усередині — `D/**/шаблон`
# (діє на будь-якій глибині під D), з «/» — `D/шаблон` (від D), «!» лишається.

# trusted_ignore_rules <коміт> <файл правил> — пише правила ігнору коміту у файл
# (формат --exclude-from). Ненуль — не вдалося прочитати коміт (fail closed).
trusted_ignore_rules() {
  local c="$1" out="$2" p d
  : >"$out" || return 1
  if ! hgit ls-tree -r -z --name-only "$c" >"$out.ls"; then
    rm -f "$out.ls"
    return 1
  fi
  while IFS= read -r -d '' p; do
    [[ "$p" == .gitignore || "$p" == */.gitignore ]] || continue
    d=""
    [[ "$p" == */* ]] && d="${p%/.gitignore}"
    if ! hgit cat-file blob "$c:$p" >"$out.one"; then
      rm -f "$out.ls" "$out.one"
      return 1
    fi
    awk -v d="$d" '
      { sub(/\r$/, "") }
      /^[[:space:]]*$/ || /^#/ { next }
      {
        l = $0
        while (l ~ / $/ && l !~ /\\ $/) sub(/ $/, "", l)
        n = ""
        if (substr(l, 1, 1) == "!") { n = "!"; l = substr(l, 2) }
        if (d == "") { print n l; next }
        core = l
        sub(/\/$/, "", core)
        if (index(core, "/") > 0) { sub(/^\//, "", l); print n d "/" l }
        else print n d "/**/" l
      }' "$out.one" >>"$out" || {
      rm -f "$out.ls" "$out.one"
      return 1
    }
  done <"$out.ls"
  rm -f "$out.ls" "$out.one"
}

# untracked_outside_rules <worktree> <індекс> <файл правил> <файл виводу> — пише
# (через NUL) неіндексовані файли worktree, яких не ігнорують правила з файла.
# Індекс — той самий тимчасовий, де вже є read-tree + add -A: усе, що агент не
# ховав, уже в ньому й сюди не потрапляє. Ненуль — git не відпрацював (fail closed).
untracked_outside_rules() {
  GIT_INDEX_FILE="$2" hgit --work-tree="$1" ls-files -o -z --exclude-from="$3" >"$4"
}

