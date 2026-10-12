#!/usr/bin/env bash
# a8-requeue.sh — повернути впалі задачі черги A8 у чергу.
#
# ЧОМУ ЦЕЙ СКРИПТ ІСНУЄ. Задача, що впала, лишається в failed/ разом із гілкою
# ai/<id> і worktree. Покласти її файл назад у чергу мало: наступний тік бачить
# «гілка ai/<id> або … уже існує» (a8-tick, крок 3), записує ще один `failed` —
# і три такі поспіль ставлять чергу на паузу. 2026-10-12 yurii двічі за день
# робив усю цю послідовність руками: залишки першого прогону → «гілка вже
# існує» → знову пауза. Ручна дія, зроблена двічі, стає скриптом (CLAUDE.md §0
# п.5).
#
# ЩО РОБИТЬ. Для кожного id, окремо від інших, лише коли ВСІ перевірки пройшли:
#   1. у failed/ рівно один файл із полем .id == id;
#   2. у running/ і в корені черги задачі з цим id немає, і в корені немає файла
#      з такою самою назвою (mv мовчки затер би його);
#   3. origin/main свіжий (`git fetch` один раз на запуск — інакше перевірка
#      комітів нижче порівнює з минулим);
#   4. гілка ai/<id>, якщо є: 0 комітів понад origin/main, не заблокована
#      і не відкрита в іншому worktree;
#   5. worktree, якщо тека є: зареєстрований у головному клоні, лежить
#      усередині A8_WORKTREES_DIR (не симлінк), HEAD на ai/<id> або відокремлений
#      (інша гілка в теці — чиясь робота), `git status --porcelain` порожній,
#      0 комітів понад origin/main (відокремлений HEAD теж).
# Тоді: worktree remove --force, прибрати залишок теки, worktree prune, branch -D,
# файл задачі з failed/ у корінь черги, подія журналу `requeue`. Перевірка не
# пройшла — для цього id нічого не змінено, рядок `SKIP <id>: <причина>`.
#
# ЧОГО НЕ РОБИТЬ.
#   - Не чіпає гілку з комітами і брудний worktree: це чиясь робота, а не залишок.
#   - Не лікує причину падіння: повтор без виправлення причини впаде так само.
#   - Не запускає тік, не знімає STOP, не торкається done/ і rejected/.
#   - Не змінює вміст файла задачі і last-results (крім --reset-pause).
#   - Помилка rev-list = SKIP, а не «0 комітів»: тік у release_or_keep вважає
#     помилку нулем, а тут помилка при видаленні гілки коштувала б чужої роботи.
#
# LOCK. Перед усім — `flock -n` на tick.lock, той самий файл, що й у тіку. Тік
# працює (або інший requeue) — вихід 3, нічого не змінено. Lock тримається до
# кінця: тік не візьме задачу, яку ми щойно повернули, посеред наших дій.
#
# --reset-pause. Кожне падіння записане в last-results рядком `failed`, а в runs.log —
# рядком event=run з task і result=failed; три `failed` в кінці ставлять паузу
# (a8-guard check → 12). Знімаються ЛИШЕ ті кінцеві `failed`, які runs.log приписує
# задачам, повернутим у ЦЬОМУ запуску: від кінця runs.log (тільки event=run) рахуються
# запуски result=failed поспіль, поки task серед повернутих; перший інший запуск (ok,
# stopped, чужа задача) зупиняє лік. З кінця last-results прибирається
# min(лік, кінцевих `failed`) рядків. Тож повернення старої задачі X не знімає паузу,
# яку дали свіжі падіння A, B, C. Наслідок, який треба знати: повернеш лише C —
# знято один рядок, лишилось два, `a8-guard check` дає OK (2 < 3), але ще одне
# падіння знову ставить паузу. Немає runs.log чи рядок, на якому лік упирається,
# не розібрано — не знімається нічого, причина друкується. Копія —
# last-results.bak-<UTC-час>. Далі друкується результат `a8-guard check`. Без
# прапорця last-results не чіпається. Пауза лікується прибраним ОБЛІКОМ, не
# причиною: якщо задача впаде знову, лічильник порахує її знову.
#
# --dry-run: усі перевірки, жодних змін (`WOULD <id>`). Єдиний побічний ефект —
# fetch оновлює refs/remotes/origin/main; без нього перевірка комітів хибна.
#
# --remote <хост>. Запуск з машини розробника: скрипт копіює себе в /tmp на хост
# під унікальною назвою (mktemp), виконує `sudo -u agent bash …` через `ssh -t`
# (sudo питає пароль, потрібен термінал) і прибирає файл, навіть якщо запуск
# впав. Код виходу віддалено — той самий (255 від ssh → 2); збій самого sudo
# від SKIP за кодом не відрізнити, тому дивись вивід.
#
# ЧОГО НЕ ДОВОДИТЬ. Перевірка комітів — відносно origin/main на момент fetch.
# --reset-pause спирається на припущення, що тік пише last-results і runs.log парою
# (fail_task: record failed + finish failed); ротований runs.log.*.gz не читається —
# тоді знімається менше, ніколи не більше.
# Роботу, яку агент не закомітив і не лишив у worktree (нічого в статусі), не
# побачить ніхто. Лише текст id: скрипт не знає, ЧОМУ задача впала.
#
# Використання (id — поле .id задачі, не назва файла; на A8 від користувача agent):
#   a8-requeue.sh [--dry-run] [--reset-pause] <id>...
#   a8-requeue.sh --remote a8-ts [--dry-run] [--reset-pause] <id>...
# Змінні: A8_CONFIG (дефолт /etc/a8/a8.env), A8_JOURNAL (/usr/local/bin/a8-journal),
# A8_GUARD (/usr/local/bin/a8-guard) — точки підміни для тесту, як у тіку.
# Виходи: 0 — усі OK; 1 — хоч один SKIP; 2 — помилка використання, конфігу чи
# fetch; 3 — тік працює.
set -euo pipefail

CONFIG="${A8_CONFIG:-/etc/a8/a8.env}"
JOURNAL="${A8_JOURNAL:-/usr/local/bin/a8-journal}"
GUARD="${A8_GUARD:-/usr/local/bin/a8-guard}"

die() {
  echo "a8-requeue: $*" >&2
  exit 2
}

# ─── Аргументи ──────────────────────────────────────────────────────────────
dry=0
reset=0
remote=""
ids=()
while (($# > 0)); do
  case "$1" in
    --dry-run)
      dry=1
      shift
      ;;
    --reset-pause)
      reset=1
      shift
      ;;
    --remote)
      remote="${2:-}"
      [[ -n "$remote" ]] || die "--remote потребує ім'я хоста"
      shift 2
      ;;
    -h | --help)
      sed -n '2,/^set -/{/^set -/!p}' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    --)
      shift
      ids+=("$@")
      break
      ;;
    -*) die "невідомий аргумент '$1'" ;;
    *)
      ids+=("$1")
      shift
      ;;
  esac
done
((${#ids[@]} > 0)) || die "потрібен хоча б один id задачі (див. --help)"

# Той самий алфавіт, що в a8-tick-logic.sh (validate): id іде в ім'я гілки й шлях
# worktree, а нижче — під `rm -rf`. Перевіряємо ДО будь-якої дії й до ssh.
ID_RE='^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'
uniq_ids=()
declare -A seen=()
for id in "${ids[@]}"; do
  if [[ ! "$id" =~ $ID_RE || "$id" == *..* || "$id" == *.lock || "$id" == *. ]]; then
    die "id '$id' не схожий на id задачі (A-Za-z0-9._- , як у a8-tick-logic.sh)"
  fi
  # Двічі той самий id: другий SKIP-ував би «немає в failed/», а в --dry-run обидва
  # дали б WOULD і подвоїли б лік повернених.
  if [[ -z "${seen[$id]:-}" ]]; then
    seen[$id]=1
    uniq_ids+=("$id")
  fi
done

# ─── --remote: себе на хост, виконати від agent, прибрати ───────────────────
if [[ -n "$remote" ]]; then
  # Хост, що починається з `-`, ssh прочитав би як опцію (-oProxyCommand=…).
  [[ "$remote" =~ ^[A-Za-z0-9][A-Za-z0-9._@-]*$ ]] || die "підозріле ім'я хоста '$remote'"
  self="$(readlink -f "${BASH_SOURCE[0]}")"
  [[ -f "$self" ]] || die "не знайдено власний файл ($self)"

  rf=""
  cleanup_remote() {
    [[ -n "$rf" ]] || return 0
    ssh "$remote" "rm -f -- $rf" >/dev/null 2>&1 ||
      echo "a8-requeue: УВАГА: не прибрано $remote:$rf — видали руками" >&2
    return 0
  }
  trap cleanup_remote EXIT

  # Унікальна назва: передбачувана в загальній /tmp дозволила б підкласти файл,
  # який agent виконає. mktemp дає 0600 — agent (інший користувач) не прочитав би.
  # Банер чи рядок із ~/.bashrc на хості попадає в stdout перед відповіддю, тож береться
  # ОСТАННІЙ рядок, що схожий на назву (printf у віддаленій команді — останній).
  made_out="$(ssh "$remote" 'f=$(mktemp /tmp/a8-requeue.XXXXXX) && chmod 644 "$f" && printf "%s\n" "$f"')" ||
    die "не вдалося створити тимчасовий файл на $remote"
  made="$(printf '%s\n' "$made_out" | tr -d '\r' | grep -E '^/tmp/a8-requeue\.[A-Za-z0-9]{6}$' | tail -n 1 || true)"
  [[ -n "$made" ]] || die "хост не повернув назви тимчасового файла, схожої на /tmp/a8-requeue.XXXXXX: '$made_out'"
  rf="$made"
  scp -q -- "$self" "$remote:$rf" || die "scp на $remote не вдався"

  args=()
  ((dry)) && args+=(--dry-run)
  ((reset)) && args+=(--reset-pause)
  # `cd /tmp`: sudo лишає теку входу, яку agent читати не може (як у a8-report.sh).
  cmd="cd /tmp && sudo -u agent bash $rf"
  for a in "${args[@]}" "${uniq_ids[@]}"; do cmd+=" $(printf '%q' "$a")"; done
  rc=0
  ssh -t "$remote" "$cmd" || rc=$?
  ((rc == 255)) && die "ssh на $remote не з'єднався"
  exit "$rc"
fi

# ─── Конфіг і середовище (далі — виконання НА A8) ───────────────────────────
[[ -r "$CONFIG" ]] || die "немає $CONFIG — скрипт виконується на A8; з машини розробника: --remote <хост>"
# shellcheck disable=SC1090
source "$CONFIG" || die "не вдалося прочитати $CONFIG"
for v in A8_QUEUE_DIR A8_LOGS_DIR A8_REPO_DIR A8_WORKTREES_DIR; do
  [[ -n "${!v:-}" ]] || die "у $CONFIG немає $v"
done
for t in jq flock git realpath timeout awk; do
  command -v "$t" >/dev/null || die "немає команди $t"
done
Q="$A8_QUEUE_DIR"
STATE="$A8_LOGS_DIR/last-results"
[[ -d "$Q" ]] || die "немає теки черги $Q"
git -C "$A8_REPO_DIR" rev-parse --git-dir >/dev/null 2>&1 || die "$A8_REPO_DIR — не git-репозиторій"

# git без fd 9: фоновий `git gc --auto` після fetch успадкував би lock і тримав
# його після нашого виходу. `--no-replace-objects`: git replace у спільному
# репозиторії міг би сховати коміти гілки від rev-list (як у backstop тіку).
repo() { git --no-replace-objects -C "$A8_REPO_DIR" "$@" 9>&-; }
wtgit() { git --no-replace-objects -C "$wt" "$@" 9>&-; }

# ─── Lock: тік працює — нічого не змінюємо ──────────────────────────────────
if ! { exec 9>"$A8_LOGS_DIR/tick.lock"; } 2>/dev/null; then
  die "не відкрито $A8_LOGS_DIR/tick.lock"
fi
if ! flock -n 9; then
  echo "a8-requeue: тік (або інший requeue) працює — нічого не змінено" >&2
  exit 3
fi

# ─── Свіжий origin/main — один раз ──────────────────────────────────────────
# GIT_TERMINAL_PROMPT=0: під `ssh -t` є термінал, і git спитав би пароль замість
# того, щоб упасти. timeout: завислий fetch тримав би lock тіку без кінця.
export GIT_TERMINAL_PROMPT=0
if ! timeout 120 git -C "$A8_REPO_DIR" fetch --quiet origin main 9>&-; then
  die "git fetch origin main не вдався — без свіжого origin/main перевірка комітів хибна; нічого не змінено"
fi
repo rev-parse --verify --quiet refs/remotes/origin/main >/dev/null || die "після fetch немає origin/main"

# ─── Допоміжне ──────────────────────────────────────────────────────────────
# scan_dir <тека> <id> → MATCHES (файли з .id == id) і UNPARSED (скільки файлів не
# розібрано). Без підоболонки: лічильник мусить дожити до виклику.
MATCHES=()
UNPARSED=0
scan_dir() {
  MATCHES=()
  UNPARSED=0
  local f got
  for f in "$1"/*.json; do
    [[ -e "$f" ]] || continue
    if got="$(jq -r '.id // "" | tostring' "$f" 2>/dev/null)"; then
      if [[ "$got" == "$2" ]]; then MATCHES+=("$f"); fi
    else
      UNPARSED=$((UNPARSED + 1))
    fi
  done
  return 0
}

# inspect_worktrees <id> <реальний шлях worktree> → REG (шлях зареєстровано в
# головному клоні), LOCKED, ELSEWHERE (де ще, крім цього шляху, відкрита гілка;
# записи про вже неіснуючі теки не рахуються — їх прибере prune).
REG=0
LOCKED=0
ELSEWHERE=""
inspect_worktrees() {
  REG=0
  LOCKED=0
  ELSEWHERE=""
  local out line cur=""
  out="$(repo worktree list --porcelain)" || return 1
  while IFS= read -r line; do
    case "$line" in
      "worktree "*)
        cur="$(realpath -m -- "${line#worktree }")"
        if [[ "$cur" == "$2" ]]; then REG=1; fi
        ;;
      locked*)
        if [[ "$cur" == "$2" ]]; then LOCKED=1; fi
        ;;
      "branch refs/heads/ai/$1")
        if [[ "$cur" != "$2" && -e "$cur" ]]; then ELSEWHERE="$cur"; fi
        ;;
    esac
  done <<<"$out"
  return 0
}

# ─── Одна задача: 0 — OK/WOULD, 1 — SKIP ────────────────────────────────────
# Викликається в умові `if`, тож set -e тут не діє: кожну команду перевіряємо явно.
process_id() {
  local id="$1" branch="ai/$1" bref="refs/heads/ai/$1"
  local wt="$A8_WORKTREES_DIR/$1" wtr wdr taskfile destfile
  local has_branch=0 has_wt=0 rc n st top head_ref removed=""
  skip() {
    printf 'SKIP %s: %s\n' "$id" "$*"
    return 1
  }

  # 1. Рівно один файл у failed/.
  scan_dir "$Q/failed" "$id"
  if ((${#MATCHES[@]} == 0)); then
    if ((UNPARSED > 0)); then
      skip "у failed/ немає задачі з таким id ($UNPARSED файлів не розібрано як JSON)"
    else
      skip "у failed/ немає задачі з таким id"
    fi
    return 1
  fi
  if ((${#MATCHES[@]} > 1)); then
    skip "у failed/ ${#MATCHES[@]} файлів з таким id — не знаю, який повертати"
    return 1
  fi
  taskfile="${MATCHES[0]}"
  destfile="$Q/$(basename "$taskfile")"

  # 2. Ні в running/, ні в черзі. Файл, який не вдалося розібрати, міг бути саме ним.
  scan_dir "$Q/running" "$id"
  if ((${#MATCHES[@]} > 0)); then
    skip "задача з таким id зараз у running/"
    return 1
  fi
  if ((UNPARSED > 0)); then
    skip "у running/ є файл, який не розібрано як JSON — не можу переконатися, що це не ця задача"
    return 1
  fi
  scan_dir "$Q" "$id"
  if ((${#MATCHES[@]} > 0)); then
    skip "задача з таким id уже в черзі (${MATCHES[0]##*/})"
    return 1
  fi
  if ((UNPARSED > 0)); then
    skip "у черзі є файл, який не розібрано як JSON — не можу переконатися, що це не ця задача"
    return 1
  fi
  if [[ -e "$destfile" ]]; then
    skip "у черзі вже є файл ${destfile##*/} — перезапис затер би його"
    return 1
  fi

  # 4. Гілка: 0 комітів понад origin/main. Помилка — SKIP.
  rc=0
  repo show-ref --verify --quiet "$bref" || rc=$?
  case "$rc" in
    0) has_branch=1 ;;
    1) ;;
    *)
      skip "git show-ref не вдався (код $rc) — не можу перевірити гілку $branch"
      return 1
      ;;
  esac
  if ((has_branch)); then
    n="$(repo rev-list --count "refs/remotes/origin/main..$bref" 2>/dev/null)" ||
      {
        skip "git rev-list не вдався — не можу перевірити коміти гілки $branch"
        return 1
      }
    if [[ ! "$n" =~ ^[0-9]+$ ]]; then
      skip "git rev-list повернув '$n' замість числа — не можу перевірити гілку $branch"
      return 1
    fi
    if ((n != 0)); then
      skip "на гілці $branch $n комітів понад origin/main — це робота, а не залишок"
      return 1
    fi
  fi

  # 5. Worktree.
  wtr="$(realpath -m -- "$wt")"
  wdr="$(realpath -m -- "$A8_WORKTREES_DIR")"
  if [[ -L "$wt" ]]; then
    skip "$wt — символічне посилання, не чіпаю"
    return 1
  fi
  inspect_worktrees "$id" "$wtr" || {
    skip "git worktree list не вдався"
    return 1
  }
  if [[ -n "$ELSEWHERE" ]]; then
    skip "гілка $branch відкрита в іншому worktree ($ELSEWHERE)"
    return 1
  fi
  if [[ -e "$wt" ]]; then
    has_wt=1
    if [[ ! -d "$wt" || "$wtr" != "$wdr/$id" ]]; then
      skip "$wt не тека всередині $A8_WORKTREES_DIR"
      return 1
    fi
    if ((!REG)); then
      skip "$wt існує, але не зареєстрований як worktree цього репозиторію — не чіпаю"
      return 1
    fi
    if ((LOCKED)); then
      skip "worktree $wt заблоковано (git worktree lock)"
      return 1
    fi
    # Без цього `git -C` піднявся б до батьківського репозиторію і показав би його
    # чистий статус замість статусу теки.
    top="$(wtgit rev-parse --show-toplevel 2>/dev/null)" || top=""
    if [[ -z "$top" || "$(realpath -m -- "$top")" != "$wtr" ]]; then
      skip "$wt не є коренем git-worktree"
      return 1
    fi
    st="$(wtgit --no-optional-locks status --porcelain 2>/dev/null)" ||
      {
        skip "git status у $wt не вдався — не git чи пошкоджено"
        return 1
      }
    if [[ -n "$st" ]]; then
      skip "брудний worktree: $(grep -c '' <<<"$st") змін у git status --porcelain"
      return 1
    fi
    # У теці задачі чекаутили іншу гілку — це не залишок падіння, а чиясь робота.
    # `symbolic-ref -q`: 0 — HEAD на гілці, 1 — відокремлений, інше — помилка.
    rc=0
    head_ref="$(wtgit symbolic-ref -q HEAD 2>/dev/null)" || rc=$?
    case "$rc" in
      0)
        if [[ "$head_ref" != "$bref" ]]; then
          skip "у $wt відкрита інша гілка ($head_ref), а не $branch — не чіпаю"
          return 1
        fi
        ;;
      1) ;; # відокремлений HEAD: коміти на ньому ловить перевірка нижче
      *)
        skip "git symbolic-ref HEAD у $wt не вдався (код $rc)"
        return 1
        ;;
    esac
    # Коміт на відокремленому HEAD не видно ні в статусі, ні на гілці.
    n="$(wtgit rev-list --count refs/remotes/origin/main..HEAD 2>/dev/null)" ||
      {
        skip "git rev-list у $wt не вдався — не можу перевірити коміти"
        return 1
      }
    if [[ ! "$n" =~ ^[0-9]+$ ]]; then
      skip "git rev-list у $wt повернув '$n' замість числа"
      return 1
    fi
    if ((n != 0)); then
      skip "HEAD у $wt має $n комітів понад origin/main (відокремлений HEAD?) — це робота"
      return 1
    fi
  fi

  if ((dry)); then
    printf 'WOULD %s: %s → черга; прибрав би:%s%s\n' "$id" "${taskfile##*/}" \
      "$( ((has_branch)) && echo " гілку $branch")" "$( ((has_wt)) && echo " worktree")"
    return 0
  fi

  # 6. Дія. Збій посередині — стан частково прибрано, файл лишається в failed/:
  # повторний запуск пройде ті самі перевірки і доробить решту.
  if ((has_wt)); then
    # Невдачу самого remove не рахуємо: залишок теки прибирає наступний крок.
    repo worktree remove --force "$wt" >/dev/null 2>&1 || true
    if [[ -e "$wt" ]]; then
      rm -rf -- "$wt" 2>/dev/null || true
    fi
    if [[ -e "$wt" ]]; then
      skip "ЧАСТКОВО: не вдалося прибрати $wt (чиї файли?) — гілку й задачу не чіпав"
      return 1
    fi
    removed+=" worktree"
  fi
  repo worktree prune >/dev/null 2>&1 || {
    skip "ЧАСТКОВО: git worktree prune не вдався"
    return 1
  }
  if ((has_branch)); then
    repo branch -D "$branch" >/dev/null 2>&1 || {
      skip "ЧАСТКОВО: git branch -D $branch не вдався"
      return 1
    }
    removed=" гілку $branch$removed"
  fi
  mv -n -- "$taskfile" "$Q/" || {
    skip "ЧАСТКОВО: mv ${taskfile##*/} у чергу не вдався"
    return 1
  }
  if [[ -e "$taskfile" || ! -e "$destfile" ]]; then
    skip "ЧАСТКОВО: файл задачі не опинився в черзі"
    return 1
  fi
  # Подія — після змін: запис, що повернення відбулося, не має випереджати його.
  # Збій журналу не скасовує повернення (задача вже в черзі) і не стає SKIP, але
  # вихід буде 1: тиха відсутність запису гірша за гучну.
  if ! "$JOURNAL" event requeue "$id"; then
    echo "УВАГА $id: подію requeue в журнал не записано (a8-journal впав)" >&2
    journal_failed=1
  fi
  printf 'OK %s: %s → черга; прибрано:%s\n' "$id" "${taskfile##*/}" "${removed:- нічого (залишків не було)}"
  return 0
}

# ─── --reset-pause ──────────────────────────────────────────────────────────
# attributed_failures <id>... → ATTR: скільки останніх запусків поспіль (за runs.log, з
# кінця, лише event=run) — result=failed повернених id; ATTR_WHY — чому порахувати не
# вдалося (тоді ATTR=0 і нічого не знімається). Лік зупиняє перший інший запуск.
ATTR=0
ATTR_WHY=""
attributed_failures() {
  ATTR=0
  ATTR_WHY=""
  local runs="$A8_LOGS_DIR/runs.log" ids_json res bad
  if [[ ! -r "$runs" ]]; then
    ATTR_WHY="немає $runs — не знаю, чиї це падіння"
    return 0
  fi
  ids_json="$(printf '%s\n' "$@" | jq -R . | jq -s .)" || {
    ATTR_WHY="jq не склав список id"
    return 0
  }
  res="$(jq -R -s --argjson ids "$ids_json" '
    (split("\n") | map(select(length > 0)) | reverse) as $lines
    | reduce $lines[] as $l ({c: 0, done: false, bad: false};
        if .done then .
        else ($l | try fromjson catch null) as $o
          | if ($o | type) != "object" then .done = true | .bad = true
            elif ($o.event // "") != "run" then .
            elif ($o.result // "") == "failed" and (($o.task // "") as $t | $ids | any(. == $t)) then .c += 1
            else .done = true
            end
        end)' "$runs" 2>/dev/null)" || {
    ATTR_WHY="jq не розібрав $runs"
    return 0
  }
  bad="$(jq -r .bad <<<"$res")"
  if [[ "$bad" == true ]]; then
    ATTR_WHY="у кінці $runs є рядок, який не розібрано як JSON — не знаю, чиї це падіння"
    return 0
  fi
  ATTR="$(jq -r .c <<<"$res")"
  return 0
}

# reset_pause <id>... — прибрати з кінця last-results кінцеві `failed`, які runs.log
# приписує поверненим id (див. шапку). Нормалізація — як в a8-guard: пробіли й \r у
# кінці рядка ([[:space:]]), порожні рядки не рахуються (інакше рядок «failed\r»
# гвардія вважала б падінням, а ми — ні).
reset_pause() {
  local tmp removed bak
  if (($# == 0)); then
    echo "reset-pause: жодної задачі не повернуто — last-results не чіпаю"
  elif [[ ! -f "$STATE" ]]; then
    echo "reset-pause: немає $STATE — прибирати нічого"
  else
    attributed_failures "$@"
    if [[ -n "$ATTR_WHY" ]]; then
      echo "reset-pause: $ATTR_WHY — last-results не чіпаю"
    elif ((ATTR == 0)); then
      echo "reset-pause: runs.log не приписує поверненим задачам жодного з останніх падінь — last-results не чіпаю"
    else
      tmp="$(mktemp "$A8_LOGS_DIR/.last-results.XXXXXX")"
      removed="$(awk -v k="$ATTR" -v out="$tmp" '
        { lines[NR] = $0 }
        END {
          i = NR; r = 0
          while (i >= 1) {
            s = lines[i]; sub(/[[:space:]]+$/, "", s)
            if (s == "") { drop[i] = 1; i--; continue }
            if (s == "failed" && r < k) { drop[i] = 1; r++; i--; continue }
            break
          }
          for (j = 1; j <= NR; j++) if (!(j in drop)) print lines[j] > out
          print r
        }' "$STATE")" || {
        rm -f -- "$tmp"
        die "не вдалося обробити $STATE"
      }
      if ((removed == 0)); then
        rm -f -- "$tmp"
        echo "reset-pause: у кінці last-results немає рядків failed — файл не чіпаю"
      elif ((dry)); then
        rm -f -- "$tmp"
        echo "WOULD reset-pause: runs.log приписує поверненим $ATTR останніх падінь; прибрав би $removed з $ATTR рядків failed з кінця last-results (копія була б last-results.bak-<UTC>)"
      else
        bak="$STATE.bak-$(date -u +%Y%m%dT%H%M%SZ)"
        if [[ -e "$bak" ]]; then
          rm -f -- "$tmp"
          die "копія $bak вже існує — last-results не змінено"
        fi
        cp -p -- "$STATE" "$bak" || {
          rm -f -- "$tmp"
          die "не вдалося зробити копію $bak — last-results не змінено"
        }
        chmod --reference="$STATE" -- "$tmp" 2>/dev/null || true
        mv -f -- "$tmp" "$STATE"
        echo "reset-pause: runs.log приписує поверненим $ATTR останніх падінь; прибрано $removed з $ATTR рядків failed з кінця last-results (копія: $bak)"
      fi
    fi
  fi
  local grc=0 gout
  gout="$("$GUARD" check 2>&1)" || grc=$?
  if ((dry)); then
    echo "a8-guard check (зараз, до змін) → код $grc: $gout"
  else
    echo "a8-guard check → код $grc: $gout"
  fi
}

# ─── Головний цикл ──────────────────────────────────────────────────────────
good=0
skipped=0
journal_failed=0
returned=()
for id in "${uniq_ids[@]}"; do
  if process_id "$id"; then
    good=$((good + 1))
    returned+=("$id")
  else
    skipped=$((skipped + 1))
  fi
done

if ((reset)); then
  reset_pause "${returned[@]}"
fi

if ((dry)); then
  echo "Разом: WOULD=$good, SKIP=$skipped (dry-run — нічого не змінено)"
else
  echo "Разом: OK=$good, SKIP=$skipped"
fi
((skipped == 0 && journal_failed == 0)) || exit 1
exit 0
