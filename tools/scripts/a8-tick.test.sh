#!/usr/bin/env bash
# a8-tick.test.sh — наскрізний доказ демона черги A8 (a8-tick) без A8.
#
# Що СПРАВЖНЄ: шаблон демона a8-tick.sh.j2, запобіжник a8-guard.sh.j2 і журнал
# a8-journal.sh.j2 (відрендерені з ролі), логіка a8-tick-logic.sh, git (локальний
# bare-репозиторій як origin), файлова черга.
# Що ПІДМІНЕНО: контейнер (a8-run-agent) і `docker kill`. Заглушка контейнера,
# як і справжня обгортка, СПЕРШУ викликає `a8-guard check` — інакше порядок
# «лічильник після запуску» був би недоведеним.
#
# Мутації в кінці: ламаємо демон по одному місцю — набір мусить почервоніти.
#
# Запуск: tools/scripts/a8-tick.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROLE="$HERE/../../infra/ansible/roles/a8/templates"
TICK_SRC="${A8_TICK_UNDER_TEST:-$ROLE/a8-tick.sh.j2}"
# «Зависання» заглушок — `sleep $HANG_S`, а не `sleep 30`: тривалість унікальна
# для прогону (PID), тож прибирання (pkill) зачіпає лише СВОЇ процеси. Із
# загальним `pkill -f "sleep 30"` паралельні прогони мутантів убивали «завислого
# агента» один одному — сценарій 20k закінчувався раніше, і мутанти виживали
# випадково (#243, червоний main 15.10).
HANG_S="30.$$"
fail=0
say() { [[ -z "${QUIET:-}" ]] && echo "$@"; return 0; }
ok() { say "✓ $1"; }
bad() {
  echo "✗ $1"
  fail=1
}

# render <шаблон> <вихід> — лише прості підстановки, яких вистачає цим шаблонам.
render() {
  sed -e "s|{{ ansible_managed }}|test render|" \
    -e "s|{{ a8_config_dir }}|$ETC|g" \
    -e "s|{{ a8_logs_dir }}|$LOGS|g" \
    -e "s|{{ a8_consecutive_failure_limit }}|3|g" "$1" >"$2"
  chmod +x "$2"
}

setup() { # setup [денний ліміт]
  ROOT="$(mktemp -d)"
  ETC="$ROOT/etc" LOGS="$ROOT/logs" QD="$ROOT/queue" BIN="$ROOT/bin"
  mkdir -p "$ETC" "$LOGS" "$QD" "$BIN" "$ROOT/wt"
  cat >"$ETC/a8.env" <<ENV
A8_KILL_SWITCH=$ROOT/STOP
A8_DAILY_TASK_LIMIT=${1:-5}
A8_CONSECUTIVE_FAILURE_LIMIT=3
A8_LOGS_DIR=$LOGS
A8_QUEUE_DIR=$QD
A8_REPO_DIR=$ROOT/repo
A8_WORKTREES_DIR=$ROOT/wt
A8_TASK_TIMEOUT=${TASK_TIMEOUT:-20}
A8_ORACLE_TIMEOUT=${ORACLE_TIMEOUT:-20}
A8_MAX_TURNS=10
A8_CONTAINER_IMAGE=hart-agent:test
A8_DEFAULT_MODEL=sonnet
A8_CLAUDE_TOKEN_FILE=$ROOT/token
A8_PUSH_CREDENTIAL_KIND=${PUSH_KIND:-none}
A8_PUSH_SSH_URL=$ROOT/origin.git
A8_SOURCES_ALLOWED="${SOURCES_ALLOWED:-human}"
ENV
  echo "tok" >"$ROOT/token"
  render "$TICK_SRC" "$BIN/a8-tick"
  render "$ROLE/a8-guard.sh.j2" "$BIN/a8-guard"
  render "$ROLE/a8-journal.sh.j2" "$BIN/a8-journal"

  # origin = bare-репо з одним комітом; головний клон — як /home/agent/hart.
  git init -q --bare -b main "$ROOT/origin.git"
  git clone -q "$ROOT/origin.git" "$ROOT/seed" 2>/dev/null
  # CLAUDE.md у базі — щоб було що перейменувати (сценарій 19c).
  echo contract >"$ROOT/seed/CLAUDE.md"
  git -C "$ROOT/seed" add CLAUDE.md
  git -C "$ROOT/seed" -c user.email=t@t -c user.name=t commit -q -m init
  git -C "$ROOT/seed" push -q origin main
  git clone -q "$ROOT/origin.git" "$ROOT/repo"

  # Підкладні команди контейнера-шкідника (#276, сценарії 23): кожна, якщо її
  # виконає git тіку (не «контейнер» — у нього A8_IN_CONTAINER), лишає маркер у
  # $ROOT/pwn. upload/receive-pack пропускають роботу далі, щоб fetch і push
  # самі по собі не падали.
  mkdir -p "$ROOT/pwn" "$ROOT/evil"
  for n in post-checkout pre-push fsmonitor ssh; do
    printf '#!/bin/sh\n[ -n "$A8_IN_CONTAINER" ] || touch "%s/%s"\nexit 0\n' "$ROOT/pwn" "$n" >"$ROOT/evil/$n"
  done
  printf '#!/bin/sh\n[ -n "$A8_IN_CONTAINER" ] || touch "%s/smudge"\ncat\n' "$ROOT/pwn" >"$ROOT/evil/smudge"
  printf '#!/bin/sh\n[ -n "$A8_IN_CONTAINER" ] || touch "%s/uploadpack"\nexec git upload-pack "$@"\n' "$ROOT/pwn" >"$ROOT/evil/up"
  printf '#!/bin/sh\n[ -n "$A8_IN_CONTAINER" ] || touch "%s/receivepack"\nexec git receive-pack "$@"\n' "$ROOT/pwn" >"$ROOT/evil/recv"
  chmod +x "$ROOT"/evil/*

  # Заглушка a8-run-agent. Поведінка — зі змінних AGENT_MODE / HOOK_RC.
  # Шлях журналу викликів ВШИТИЙ, а не зі змінної: A8_LOGS_DIR у середовище
  # заглушки не експортується, і перевірка «claude не викликано» мовчки
  # проходила б на відсутньому файлі (спіймано першим прогоном, docs/16 §8.1).
  cat >"$BIN/a8-run-agent" <<STUB
#!/usr/bin/env bash
CALLS="$LOGS/runner-calls"
STOPFILE="$ROOT/STOP"
AGENT_STARTED="$ROOT/agent-started"
HANG_S="$HANG_S"
PIDS="$LOGS"
REPO="$ROOT/repo"
ORIGIN="$ROOT/origin.git"
EVIL="$ROOT/evil"
TMPR="$ROOT"
STUB
  cat >>"$BIN/a8-run-agent" <<'STUB'
wt="$1"; shift
# Усе, що запущено звідси, — «контейнер». Підкладні команди сценаріїв 23 за
# цією змінною відрізняють контейнер від тіку: виконатись у контейнері їм не
# заборонено (там вони й так у владі агента), заборонено — на хості.
export A8_IN_CONTAINER=1
# Лок тіку (fd 9) заглушці ні до чого. «Довга сесія», убита спостерігачем,
# лишає осиротілий `sleep`, і з успадкованим fd 9 він тримав би лок — наступний
# тік отримав би busy. У справжньому контейнері процес обгортки вмирає разом
# із контейнером; тут «контейнер» і його sleep — різні процеси.
exec 9>&-
# `check-run`, як і справжня обгортка. Якби тут лишився `check`, тест зеленів
# би на демоні, який на останній задачі дня валить власний оракул кодом 11.
"$A8_GUARD" check-run >/dev/null 2>&1 || exit $?
echo "run-agent $*" >>"$CALLS"
# IMAGE_MISSING: образу немає — справжній `docker run` падає одразу (125).
if [[ -n "${IMAGE_MISSING:-}" ]]; then
  echo "Unable to find image 'hart-agent:test' locally" >&2
  exit 125
fi
# «Контейнер» — цей процес. PID за ім'ям контейнера: заглушка docker на
# `kill <ім'я>` убиває саме його, як справжній `docker kill` — свій контейнер.
[[ -n "${A8_CONTAINER_NAME:-}" ]] && echo $$ >"$PIDS/pid-$A8_CONTAINER_NAME"
# Маркер «контейнер існує» для docker inspect (#290, ensure_container_gone):
# живе, доки docker kill його не прибере (а з KILL_NEVER — не прибирає).
[[ -n "${A8_CONTAINER_NAME:-}" ]] && : >"$PIDS/alive-$A8_CONTAINER_NAME"
# STOP_DURING: людина створює STOP, поки йде цей етап; етап доходить до кінця,
# а наступний старт контейнера отримує 10 від check-run.
if [[ "$*" == *check-hook-loud* ]]; then
  [[ "${STOP_DURING:-}" == hook ]] && touch "$STOPFILE"
  exit "${HOOK_RC:-0}"
fi
if [[ "$*" == *"pnpm install"* ]]; then
  [[ "${STOP_DURING:-}" == pnpm ]] && touch "$STOPFILE"
  exit "${DEPS_RC:-0}"
fi
if [[ "$*" == *"uv sync"* ]]; then
  [[ "${STOP_DURING:-}" == uvsync ]] && touch "$STOPFILE"
  exit "${DEPS_RC:-0}"
fi
# Оракул приходить як `bash -c <текст>` і ВИКОНУЄТЬСЯ по-справжньому, у
# worktree. Заглушка, що відповідала б за нього кодом зі змінної, доводила б
# лише «рядок викликано»; нам потрібне «оракул червоніє на неправильній
# роботі», а це видно тільки на справжньому виконанні проти справжнього дерева.
if [[ "$1" == bash && "$2" == -c ]]; then
  (cd "$wt" && bash -c "$3")
  exit $?
fi
case "${AGENT_MODE:-commit}" in
  commit)
    git -C "$wt" -c user.email=a@a -c user.name=a commit -q --allow-empty -m work
    echo '{"type":"result","is_error":false,"result":"done"}' ;;
  work)
    # Робота, яку оракул може ПЕРЕВІРИТИ: без файла той самий оракул червоніє.
    echo MARKER >"$wt/result.txt"
    git -C "$wt" add result.txt
    git -C "$wt" -c user.email=a@a -c user.name=a commit -q -m work
    echo '{"type":"result","is_error":false,"result":"done"}' ;;
  stopafter)
    git -C "$wt" -c user.email=a@a -c user.name=a commit -q --allow-empty -m work
    touch "$STOPFILE"
    echo '{"type":"result","is_error":false,"result":"done"}' ;;
  forbidden | moveorigin | detach | replace)
    # Заборонений шлях через Bash — те, чого deny-правила Edit/Write не бачать.
    mkdir -p "$wt/infra" && echo x >"$wt/infra/x"
    git -C "$wt" add infra/x
    git -C "$wt" -c user.email=a@a -c user.name=a commit -q -m forbidden
    case "$AGENT_MODE" in
      moveorigin)
        # Чистий коміт зверху, а origin/main пересунуто на заборонений: diff від
        # origin/main бачить лише чистий коміт.
        git -C "$wt" -c user.email=a@a -c user.name=a commit -q --allow-empty -m clean
        git -C "$wt" update-ref refs/remotes/origin/main HEAD~1 ;;
      detach)
        # Гілка лишається на забороненому коміті, HEAD — на чистому поруч.
        git -C "$wt" checkout -q --detach HEAD~1
        git -C "$wt" -c user.email=a@a -c user.name=a commit -q --allow-empty -m clean ;;
      replace)
        # Для diff заборонений коміт підмінено чистим, push віддасть справжній.
        f="$(git -C "$wt" rev-parse HEAD)"
        c="$(git -C "$wt" -c user.email=a@a -c user.name=a commit-tree "HEAD~1^{tree}" -p HEAD~1 -m clean)"
        git -C "$wt" replace "$f" "$c" ;;
    esac
    echo '{"type":"result","is_error":false,"result":"done"}' ;;
  cyrillic | quote)
    # Не-ASCII або лапки в імені: `git diff --name-only` бере такий шлях у лапки
    # з вісімковими кодами ("infra/\321\202…"), і шаблон ^infra/ його не бачить.
    mkdir -p "$wt/infra"
    if [[ "$AGENT_MODE" == cyrillic ]]; then echo x >"$wt/infra/тест.sh"; else echo x >"$wt/infra/a\"b"; fi
    git -C "$wt" add -A infra
    git -C "$wt" -c user.email=a@a -c user.name=a commit -q -m odd-name
    echo '{"type":"result","is_error":false,"result":"done"}' ;;
  detachonly)
    # Коміт на відокремленому HEAD, гілка лишилась на базі: пушити нічого.
    git -C "$wt" checkout -q --detach
    git -C "$wt" -c user.email=a@a -c user.name=a commit -q --allow-empty -m detached
    echo '{"type":"result","is_error":false,"result":"done"}' ;;
  rename)
    git -C "$wt" mv CLAUDE.md notes.md
    git -C "$wt" -c user.email=a@a -c user.name=a commit -q -m rename
    echo '{"type":"result","is_error":false,"result":"done"}' ;;
  sleepstop)
    # Довга сесія: агент закомітив, людина створила STOP, сесія триває далі.
    # Без спостерігача тік чекав би кінця сесії (A8_TASK_TIMEOUT).
    git -C "$wt" -c user.email=a@a -c user.name=a commit -q --allow-empty -m work
    touch "$STOPFILE"
    sleep "$HANG_S" ;;
  sleepstop0)
    # Те саме, але комітів ще немає.
    touch "$STOPFILE"
    sleep "$HANG_S" ;;
  oom) exit 137 ;;
  authstop)
    # 401, а людина саме створила STOP.
    touch "$STOPFILE"
    echo '{"type":"result","is_error":true,"num_turns":1,"result":"Failed to authenticate. API Error: 401 Invalid bearer token"}'
    exit 1 ;;
  evil-*)
    # #276: контейнер-шкідник. Агент робить звичайну роботу і підкладає в .git
    # головного клону те, що git ТІКУ на хості виконав би або чим підмінив би
    # дані. Записи в .git/config і .git/hooks — імітація виходу за межу
    # монтування :ro (тут монтувань немає). Кожен підкладений хук чи команда,
    # якщо спрацює, лишає маркер у $TMPR/pwn — тест вимагає їх 0.
    ci() { git -C "$wt" -c user.email=a@a -c user.name=a commit -q "$@"; }
    case "$AGENT_MODE" in
      evil-hooks)
        ci --allow-empty -m work
        for h in post-checkout pre-push; do cp "$EVIL/$h" "$REPO/.git/hooks/$h"; done ;;
      evil-config)
        ci --allow-empty -m work
        git -C "$REPO" config core.fsmonitor "$EVIL/fsmonitor"
        git -C "$REPO" config core.sshCommand "$EVIL/ssh" ;;
      evil-pack)
        ci --allow-empty -m work
        git -C "$REPO" config remote.origin.uploadpack "$EVIL/up"
        git -C "$REPO" config remote.origin.receivepack "$EVIL/recv" ;;
      evil-commondir | evil-symlink)
        # Чужий .git: копія справжнього з власним конфігом (alias, фільтр на всі
        # файли, receivepack) і хуками.
        ci --allow-empty -m work
        e="$TMPR/evilgit"
        cp -r "$REPO/.git" "$e"
        git --git-dir="$e" config alias.pwn "![ -n \"\$A8_IN_CONTAINER\" ] || touch $TMPR/pwn/alias"
        git --git-dir="$e" config filter.x.smudge "$EVIL/smudge"
        git --git-dir="$e" config remote.origin.receivepack "$EVIL/recv"
        mkdir -p "$e/info" && echo '* filter=x' >"$e/info/attributes"
        for h in post-checkout pre-push; do cp "$EVIL/$h" "$e/hooks/$h"; done
        if [[ "$AGENT_MODE" == evil-commondir ]]; then
          echo "$e" >"$REPO/.git/commondir"
        else
          mv "$REPO/.git" "$TMPR/realgit" && ln -s "$e" "$REPO/.git"
        fi ;;
      evil-mvgit)
        # Підміна всієї .git новою текою (новий inode) — як mv .git .git-old +
        # свій .git (рецензія #290, п.1). Структурно .git валідна, тож
        # git_unsafe_reason-перевірки симлінків/commondir проходять; ловить лише
        # знімок identity (dev:inode .git + хеш config), зроблений до контейнера.
        # Живий фільтр у підміненій .git: якби наступний тік її успадкував,
        # smudge виконався б на хості. Знімок ловить підміну на першому тіку й
        # ставить STOP (рецензія #290 коло 2) — тож наступний тік задачу не бере,
        # і маркер smudge не з'являється.
        ci --allow-empty -m work
        d="$REPO/.git"
        mv "$d" "$d.old"
        mkdir "$d"
        cp -a "$d.old/." "$d/"
        git --git-dir="$d" config filter.x.smudge "$EVIL/smudge"
        mkdir -p "$d/info" && echo '* filter=x' >"$d/info/attributes" ;;
      evil-commitgraph)
        # Підроблений .git/objects/info/commit-graph (контрприклад Argon CX2):
        # коміт додає заборонений infra/x, але в CDAT графа OID кореневого дерева
        # tip підмінено на дерево бази. `diff --name-only base tip` з увімкненим
        # графом бере дерево з CDAT → infra/x НЕ видно (backstop обходиться).
        # Ловить лише -c core.commitGraph=false (git читає сам об'єкт коміту).
        # Знімок identity не чіпається: файл у objects/info/, не config/.git-inode.
        mkdir -p "$wt/infra" && echo x >"$wt/infra/x" && git -C "$wt" add infra/x
        ci -m forbidden
        btree="$(git -C "$REPO" rev-parse "refs/remotes/origin/main^{tree}")"
        ttree="$(git -C "$wt" rev-parse "HEAD^{tree}")"
        git -C "$REPO" commit-graph write --reachable >/dev/null 2>&1
        # commit-graph write створює файл 0444; контейнер володіє .git/objects і
        # знімає захист запису перед підробкою (інакше patch падає PermissionError).
        chmod u+w "$REPO/.git/objects/info/commit-graph"
        python3 -c 'import sys,hashlib
p,t,b=sys.argv[1],bytes.fromhex(sys.argv[2]),bytes.fromhex(sys.argv[3])
d=bytearray(open(p,"rb").read()); body=d[:-20]; i=body.find(t)
assert i!=-1 and body.find(t,i+20)==-1
body[i:i+20]=b; open(p,"wb").write(bytes(body)+hashlib.sha1(bytes(body)).digest())' \
          "$REPO/.git/objects/info/commit-graph" "$ttree" "$btree" ;;
      evil-wtsymlink)
        # .git/worktrees → симлінк на чужий gitdir (контрприклад Argon CX1).
        ci --allow-empty -m work
        e="$TMPR/evilwt"
        mkdir -p "$e"
        [[ -d "$REPO/.git/worktrees" ]] && mv "$REPO/.git/worktrees" "$e/worktrees" || mkdir -p "$e/worktrees"
        ln -s "$e/worktrees" "$REPO/.git/worktrees" ;;
      evil-alternates)
        ci --allow-empty -m work
        mkdir -p "$TMPR/alt/objects"
        echo "$TMPR/alt/objects" >"$REPO/.git/objects/info/alternates" ;;
      evil-grafts)
        ci --allow-empty -m work
        git -C "$wt" rev-parse HEAD >"$REPO/.git/info/grafts" ;;
      evil-shallow)
        ci --allow-empty -m work
        git -C "$wt" rev-parse HEAD >"$REPO/.git/shallow" ;;
      evil-wtdiff | evil-wtpush)
        # "$wt/.git" → власний gitdir: об'єкти — через alternates зі справжніх,
        # конфіг із receivepack і origin, хук pre-push.
        if [[ "$AGENT_MODE" == evil-wtdiff ]]; then
          mkdir -p "$wt/infra" && echo x >"$wt/infra/x" && git -C "$wt" add infra/x
          ci -m forbidden
        else
          ci --allow-empty -m work
        fi
        f="$(git -C "$wt" rev-parse HEAD)"
        fg="$TMPR/fakegit"
        git init -q --bare "$fg"
        echo "$REPO/.git/objects" >"$fg/objects/info/alternates"
        git --git-dir="$fg" update-ref "refs/heads/ai/$(basename "$wt")" "$f"
        git --git-dir="$fg" symbolic-ref HEAD "refs/heads/ai/$(basename "$wt")"
        git --git-dir="$fg" config core.bare false
        git --git-dir="$fg" config remote.origin.url "$ORIGIN"
        git --git-dir="$fg" config remote.origin.receivepack "$EVIL/recv"
        cp "$EVIL/pre-push" "$fg/hooks/pre-push"
        if [[ "$AGENT_MODE" == evil-wtdiff ]]; then
          # Під SHA забороненого коміту — чистий коміт (дерево бази): git не
          # перераховує хеш об'єкта, читаючи його для diff.
          c="$(git --git-dir="$fg" -c user.email=a@a -c user.name=a commit-tree "HEAD~1^{tree}" -p HEAD~1 -m clean)"
          mkdir -p "$fg/objects/${f:0:2}"
          cp "$fg/objects/${c:0:2}/${c:2}" "$fg/objects/${f:0:2}/${f:2}"
        fi
        echo "gitdir: $fg" >"$wt/.git" ;;
      evil-tag)
        # Неоднозначне `origin/main`: тег і гілка з цим іменем на коміті з
        # забороненим файлом поверх бази.
        ci --allow-empty -m work
        x="$(echo x | git -C "$REPO" hash-object -w --stdin)"
        t="$(printf '100644 blob %s\tx\n' "$x" | git -C "$REPO" mktree)"
        t="$(printf '040000 tree %s\tinfra\n100644 blob %s\tCLAUDE.md\n' "$t" \
          "$(git -C "$REPO" rev-parse refs/remotes/origin/main:CLAUDE.md)" | git -C "$REPO" mktree)"
        m="$(git -C "$REPO" -c user.email=a@a -c user.name=a commit-tree "$t" -p refs/remotes/origin/main -m evil)"
        git -C "$REPO" update-ref refs/tags/origin/main "$m"
        git -C "$REPO" update-ref refs/heads/origin/main "$m" ;;
      evil-moveorigin401)
        # Гілка з роботою, origin/main пересунуто на неї, і 401: «0 комітів від
        # origin/main» стерло б гілку й повернуло задачу в чергу.
        ci --allow-empty -m work
        git -C "$wt" update-ref refs/remotes/origin/main HEAD
        echo '{"type":"result","is_error":true,"num_turns":1,"result":"Failed to authenticate. API Error: 401 Invalid bearer token"}'
        exit 1 ;;
      evil-delbranch)
        # Коміт є, гілки вже немає: rev-list падає. Помилка — не «0 комітів».
        ci --allow-empty -m work
        git -C "$wt" checkout -q --detach
        git -C "$wt" update-ref -d "refs/heads/ai/$(basename "$wt")"
        exit 12 ;;
    esac
    echo '{"type":"result","is_error":false,"result":"done"}' ;;
  nocommit) echo '{"type":"result","is_error":false,"result":"nothing"}' ;;
  fail) echo '{"type":"result","is_error":true,"result":"boom"}'; exit 1 ;;
  auth) echo '{"type":"result","is_error":true,"num_turns":1,"result":"Failed to authenticate. API Error: 401 Invalid bearer token"}'; exit 1 ;;
  paused) exit 12 ;;
  hang)
    # Мітка «агент стартував»: watch_start іде перед запуском агента, тож мітка
    # означає, що спостерігач уже живий (сценарій 20k чекає її, а не годинник).
    : >"$AGENT_STARTED"
    sleep "$HANG_S" ;;
esac
STUB
  chmod +x "$BIN/a8-run-agent"
  # Заглушка docker: журнал викликів; `kill <ім'я>` убиває процес «контейнера»
  # з цим ім'ям (KILL → 137, як у справжнього). DOCKER_RM_STOP — людина встигла
  # прибрати STOP, поки тік дочитував код виходу: лишається лише мітка.
  cat >"$BIN/docker" <<STUB
#!/usr/bin/env bash
echo "docker \$*" >>"$LOGS/docker-calls"
# DOCKER_KILL_FAIL_ONCE: перший kill б'є в порожнечу — контейнера ще немає.
if [[ "\$1" == kill && -n "\${DOCKER_KILL_FAIL_ONCE:-}" && ! -e "$LOGS/kill-failed-once" ]]; then
  : >"$LOGS/kill-failed-once"
  exit 1
fi
# IMAGE_MISSING: образу немає (issue #117) — так відповідає \`docker image inspect\`
# (виміряно на docker 29.8.2: rc=1, текст нижче).
# DOCKER_DOWN: демон не відповідає (текст виміряно в цій сесії, docker CLI 29.8.2
# без демона). IMAGE_HANG: inspect висить.
if [[ "\$1" == image && "\$2" == inspect && -n "\${DOCKER_DOWN:-}" ]]; then
  echo "failed to connect to the docker API at unix:///var/run/docker.sock; check if the path is correct and if the daemon is running" >&2
  exit 1
fi
if [[ "\$1" == image && "\$2" == inspect && -n "\${IMAGE_HANG:-}" ]]; then
  exec sleep $HANG_S
fi
# STOP_DURING=inspect: людина створює STOP на ДРУГОМУ inspect тіку (крок 2a,
# уже після запобіжників); перший — рання проба серії.
if [[ "\$1" == image && "\$2" == inspect && "\${STOP_DURING:-}" == inspect ]] &&
  (( \$(grep -c 'image inspect' "$LOGS/docker-calls") >= 2 )); then
  echo "причина людини" >"$ROOT/STOP"
fi
# DURING_INSPECT_CMD: щось відбувається, поки тік пробує образ (крок 2a) — між
# вибором кандидата і взяттям задачі (контрприклад Argon 5б, PR #272).
if [[ "\$1" == image && "\$2" == inspect && -n "\${DURING_INSPECT_CMD:-}" ]]; then
  bash -c "\$DURING_INSPECT_CMD"
fi
if [[ "\$1" == image && "\$2" == inspect && -n "\${IMAGE_MISSING:-}" ]]; then
  echo "Error response from daemon: No such image: \$3" >&2
  exit 1
fi
# inspect <контейнер> (не image): існує, доки є маркер alive-. Так
# ensure_container_gone (#290) бачить, що --rm контейнер зник після kill.
if [[ "\$1" == inspect ]]; then
  [[ -e "$LOGS/alive-\$2" ]] && exit 0 || exit 1
fi
if [[ "\$1" == kill ]]; then
  # KILL_NEVER: kill «успішний», та контейнер лишається — імітує, що не зупинився.
  if [[ -z "\${KILL_NEVER:-}" ]]; then
    [[ -f "$LOGS/pid-\$2" ]] && kill -9 "\$(cat "$LOGS/pid-\$2")" 2>/dev/null
    rm -f "$LOGS/alive-\$2"
  fi
  [[ -n "\${DOCKER_RM_STOP:-}" ]] && rm -f "$ROOT/STOP"
fi
exit 0
STUB
  chmod +x "$BIN/docker"

  # Спостерігач у тесті дивиться раз на секунду, а не раз на 5 с (A8).
  export A8_WATCH_INTERVAL_S="${WATCH_S:-1}"
  export A8_CONFIG="$ETC/a8.env" A8_TICK_LOGIC="$HERE/a8-tick-logic.sh"
  export A8_GUARD="$BIN/a8-guard" A8_RUNNER="$BIN/a8-run-agent"
  export A8_JOURNAL="$BIN/a8-journal" A8_DOCKER="$BIN/docker"
  export A8_FORBIDDEN_CHECK="$HERE/check-forbidden-paths.sh"
}
teardown() {
  # Процеси сценарію, яких тік не дочекався (убитий тік, «довга сесія»):
  # у їхньому рядку запуску є $ROOT, а в інших сценаріях — ні.
  pkill -9 -f "$ROOT/" 2>/dev/null
  rm -rf "$ROOT"
}
# Живі процеси тіку — сам тік і його спостерігач (підоболонка має той самий
# рядок запуску). Після виходу тіку їх бути не повинно.
tick_procs() { pgrep -f "$BIN/a8-tick" 2>/dev/null | wc -l; }

enqueue() { # enqueue <файл> <json>
  printf '%s\n' "$2" >"$QD/$1.json"
}
# Оракул за замовчуванням тривіально зелений: сценарії, що перевіряють ІНШЕ,
# не мають падати на ньому. Хто перевіряє сам оракул — задає його явно.
valid() { with_oracle "$1" true; }
with_oracle() { # with_oracle <id> <текст оракула>
  jq -nc --arg id "$1" --arg o "$2" \
    '{id:$id, source:"human", origin:"direction", oracle:$o, prompt:("do "+$id)}'
}
tick() { bash "$BIN/a8-tick" >>"$LOGS/tick.out" 2>&1; }
# collating_locale — локаль, у якій «001_a» сортується РАНІШЕ за «001-z» (у C — навпаки):
# так видно, чи тік сортує в C, а не в локалі машини. Немає такої — сценарій 22d
# і його мутант не ганяються, і це друкується (не «зелено»).
collating_locale() {
  local l
  for l in en_US.UTF-8 en_US.utf8 uk_UA.UTF-8 de_DE.UTF-8; do
    [[ "$(printf '001-z\n001_a\n' | LC_ALL="$l" sort 2>/dev/null | head -n 1)" == 001_a ]] && {
      echo "$l"
      return 0
    }
  done
  return 1
}
tick_rc() {
  local rc=0
  bash "$BIN/a8-tick" >>"$LOGS/tick.out" 2>&1 || rc=$?
  echo "$rc"
}
last() { tail -n 1 "$LOGS/runs.log"; }
jl() { jq -r "$1" <<<"$(last)"; }

run_scenarios() {
  # 1. Kill switch → окремий стан, задача лишається в черзі.
  setup
  enqueue 001-a "$(valid a)"
  touch "$ROOT/STOP"
  tick
  [[ "$(jl .event)" == kill_switch && -e "$QD/001-a.json" ]] && ok "kill switch → event kill_switch, задача ціла в черзі" ||
    bad "kill switch: $(last)"
  teardown

  # 2. Денний ліміт → інший стан, не злитий із паузою.
  setup 1
  echo 1 >"$LOGS/counter-$(date -u +%Y-%m-%d)"
  enqueue 001-a "$(valid a)"
  tick
  [[ "$(jl .event)" == daily_limit ]] && ok "денний ліміт → event daily_limit (не paused)" || bad "ліміт: $(last)"
  teardown

  # 3. Невалідний запис: відмова з назвою ПОЛЯ, валідний за ним — виконується.
  setup
  enqueue 001-bad '{"id":"bad","source":"human","origin":"direction","prompt":"p"}'
  enqueue 002-ext '{"id":"ext","source":"external","origin":"feedback","oracle":"x","prompt":"p"}'
  enqueue 003-good "$(valid good)"
  tick
  r1="$(grep '"event":"reject"' "$LOGS/runs.log" | head -1)"
  r2="$(grep '"event":"reject"' "$LOGS/runs.log" | sed -n 2p)"
  [[ "$(jq -c .fields <<<"$r1")" == '["oracle:missing"]' && -e "$QD/rejected/001-bad.json" ]] &&
    ok "без oracle → reject з fields [oracle:missing], файл у rejected/" || bad "reject oracle: $r1"
  [[ "$(jq -c .fields <<<"$r2")" == '["source:not-allowed"]' ]] &&
    ok "external у режимі (а) → reject з fields [source:not-allowed] — інше «ні»" || bad "reject external: $r2"
  [[ "$(jl .task)" == good ]] && ok "після відмов узято наступну валідну задачу" || bad "не взято good: $(last)"
  teardown

  # 3b. Режим OQ-34 береться з КОНФІГУ, а не лише з дефолту логіки: інакше
  # змінна ролі a8_sources_allowed була б мертвою. Контроль до сценарію 3.
  SOURCES_ALLOWED="human external" setup
  enqueue 001-ext '{"id":"ext","source":"external","origin":"feedback","oracle":"x","prompt":"p"}'
  tick
  [[ "$(jl .task)" == ext && "$(jl .event)" == run ]] &&
    ok "конфіг дозволяє external → задачу взято (налаштування ролі живе)" || bad "config sources: $(last)"
  teardown

  # 4. Успіх без креденшала → no-credential, не «ok»; журнал має всі поля.
  setup
  enqueue 001-a "$(valid a)"
  tick
  [[ "$(jl .result)" == no-credential && -e "$QD/done/001-a.json" ]] &&
    ok "агент ok, креденшала немає → result no-credential, задача в done/" || bad "no-cred: $(last)"
  [[ "$(jl '[.branch,.worktree,.oracle,.origin,.exit_class,.model]|map(length>0)|all')" == true && "$(jl .branch)" == ai/a ]] &&
    ok "журнал: branch, worktree, oracle, origin, exit_class, model заповнені" || bad "поля: $(last)"
  git -C "$ROOT/repo" rev-parse --verify -q refs/heads/ai/a >/dev/null &&
    ok "гілка ai/a створена від origin/main" || bad "немає гілки ai/a"
  teardown

  # 5. Ліміт 1: єдина задача дня мусить ВИКОНАТИСЬ (лічильник — після запуску).
  setup 1
  enqueue 001-a "$(valid a)"
  tick
  [[ "$(jl .result)" == no-credential ]] &&
    ok "ліміт 1 → остання задача дня виконується, обгортка не відмовляє кодом 11" || bad "ліміт 1: $(last)"
  teardown

  # 5b. Кожна взята задача рахується РІВНО ОДИН раз — і успішна, і та, що
  # упала на залежностях. Це те, що лишилось правдою після розділення дієслів
  # guard'а: ПОРЯДОК лічильника на поведінку більше не впливає, а от КІЛЬКІСТЬ
  # впливає — без неї денний ліміт обходиться.
  setup
  enqueue 001-a "$(valid a)"
  tick
  cnt="$(cat "$LOGS/counter-$(date -u +%Y-%m-%d)" 2>/dev/null)"
  [[ "$cnt" == 1 ]] && ok "успішна задача порахована рівно один раз" || bad "лічильник після успіху: '${cnt:-немає файла}'"
  teardown
  # Контроль: задача, що не дійшла до агента, теж мусить рахуватись — інакше
  # черга з падінням на залежностях крутилась би цілий день без ліміту.
  setup
  enqueue 001-a "$(valid a)"
  DEPS_RC=1 tick
  cnt="$(cat "$LOGS/counter-$(date -u +%Y-%m-%d)" 2>/dev/null)"
  [[ "$cnt" == 1 ]] && ok "падіння на залежностях теж порахане (ліміт не обходиться)" || bad "лічильник після deps: '${cnt:-немає файла}'"
  teardown

  # 6. 401 → STOP усієї черги, задача повертається, падіння НЕ рахується.
  setup
  enqueue 001-a "$(valid a)"
  AGENT_MODE=auth tick
  [[ "$(jl .result)" == auth_stop && -s "$ROOT/STOP" && -e "$QD/001-a.json" ]] &&
    ok "401 → auth_stop, kill switch створено з причиною, задача повернута в чергу" || bad "401: $(last)"
  grep -q failed "$LOGS/last-results" 2>/dev/null && bad "401 записано як failed" ||
    ok "401 не зараховано в падіння поспіль"
  AGENT_MODE=auth tick
  [[ "$(jl .event)" == kill_switch ]] && ok "наступний тік після 401 — не retry, а kill_switch" || bad "retry після 401: $(last)"
  # Людина перелогінилась і зняла STOP: повернута задача мусить ВИКОНАТИСЬ, а не
  # упасти на «гілка вже існує» (знайдено незалежним рев'ю №2).
  rm -f "$ROOT/STOP"
  tick
  [[ "$(jl .result)" == no-credential && "$(jl .task)" == a ]] &&
    ok "після зняття STOP повернута задача виконується (порожню гілку прибрано)" || bad "requeue після 401: $(last)"
  teardown

  # 6b. Запобіжник спрацював в обгортці (код 12) → stopped, задача в черзі,
  # і наступний тік її виконує.
  setup
  enqueue 001-a "$(valid a)"
  AGENT_MODE=paused tick
  [[ "$(jl .result)" == stopped && "$(jl .detail)" == paused && -e "$QD/001-a.json" ]] &&
    ok "обгортка повернула 12 → stopped paused, задача в черзі, не failed" || bad "stopped: $(last)"
  grep -q failed "$LOGS/last-results" 2>/dev/null && bad "stopped записано як failed" || ok "stopped не зараховано в падіння"
  tick
  [[ "$(jl .result)" == no-credential ]] && ok "після stopped задача виконується наступним тіком" || bad "requeue після stopped: $(last)"
  teardown

  # 7. Пауза рівно на третьому падінні; четвертий тік — paused.
  setup
  for i in 1 2 3 4; do enqueue "00$i" "$(valid "f$i")"; done
  AGENT_MODE=fail tick
  AGENT_MODE=fail tick
  grep -q '"event":"paused"' "$LOGS/runs.log" && bad "пауза вже після двох" || ok "два падіння — паузи ще немає"
  AGENT_MODE=fail tick
  [[ "$(jl .event)" == paused ]] && ok "третє падіння → event paused" || bad "третє: $(last)"
  AGENT_MODE=fail tick
  [[ "$(jl .event)" == paused && -e "$QD/004.json" ]] && ok "четвертий тік: guard → paused, задача не взята" || bad "четвертий: $(last)"
  teardown

  # 7b. Guard звітує падіння ПОСПІЛЬ, а не «скільки failed у вікні».
  # Рішення в обох редакціях однакове; різниться ЧИСЛО, яке читає людина.
  # `failed failed ok` — стан, на якому стара редакція друкувала 2 при нулі
  # падінь поспіль; саме його yurii побачив 2026-09-20 після успішного прогону.
  setup
  printf 'failed\nfailed\nok\n' >"$LOGS/last-results"
  [[ "$("$BIN/a8-guard" check)" == *"падінь поспіль 0 з 3"* ]] &&
    ok "після успіху guard звітує 0 падінь поспіль (вікно давало б 2)" ||
    bad "звіт guard після успіху: $("$BIN/a8-guard" check)"
  # Контроль: без нього перевірка не відрізняє «рахує» від «завжди друкує 0».
  printf 'ok\nfailed\nfailed\n' >"$LOGS/last-results"
  [[ "$("$BIN/a8-guard" check)" == *"падінь поспіль 2 з 3"* ]] &&
    ok "два падіння в хвості → guard звітує 2" || bad "звіт guard: $("$BIN/a8-guard" check)"
  teardown

  # 7c. Контракт двох дієслів: check гейтить НАБІР задачі, check-run — лише
  # виконання. Без цього поділу оракул останньої задачі дня падав би кодом 11.
  setup 1
  echo 1 >"$LOGS/counter-$(date -u +%Y-%m-%d)"
  "$BIN/a8-guard" check >/dev/null 2>&1
  c_limit=$?
  "$BIN/a8-guard" check-run >/dev/null 2>&1
  r_limit=$?
  printf 'failed\nfailed\nfailed\n' >"$LOGS/last-results"
  "$BIN/a8-guard" check-run >/dev/null 2>&1
  r_paused=$?
  touch "$ROOT/STOP"
  "$BIN/a8-guard" check-run >/dev/null 2>&1
  r_stop=$?
  [[ "$c_limit" == 11 && "$r_limit" == 0 && "$r_paused" == 0 ]] &&
    ok "вичерпаний ліміт і пауза зупиняють check (11), але не check-run (0)" ||
    bad "дієслова guard: check=$c_limit check-run=$r_limit paused=$r_paused"
  [[ "$r_stop" == 10 ]] &&
    ok "kill switch зупиняє і check-run (10) — єдиний запобіжник на межі контейнера" ||
    bad "check-run при kill switch: $r_stop"
  teardown

  # 8. Агент «ok», але комітів немає → failed no-commits.
  setup
  enqueue 001-a "$(valid a)"
  AGENT_MODE=nocommit tick
  [[ "$(jl .detail)" == no-commits && "$(jl .result)" == failed ]] && ok "rc 0 без комітів → failed no-commits" || bad "no-commits: $(last)"
  teardown

  # 9. Сирота в running/ → failed orphan.
  setup
  mkdir -p "$QD/running"
  valid orph >"$QD/running/000-orph.json"
  tick
  o="$(grep '"detail":"orphan"' "$LOGS/runs.log")"
  [[ -n "$o" && -e "$QD/failed/000-orph.json" ]] && ok "сирота з обірваного тіку → failed orphan, файл у failed/" || bad "orphan: $(tail -3 "$LOGS/runs.log")"
  [[ "$(tail -n 1 "$LOGS/last-results" 2>/dev/null)" == failed ]] &&
    ok "сирота записана в last-results як failed (рахується до паузи)" || bad "orphan last-results: $(cat "$LOGS/last-results" 2>/dev/null)"
  grep -q 'docker kill a8-orph' "$LOGS/docker-calls" 2>/dev/null &&
    ok "сирота → контейнер a8-orph убито (міг працювати без нагляду)" || bad "orphan kill: $(cat "$LOGS/docker-calls" 2>/dev/null)"
  grep -q 'docker kill .*a8-orph-oracle' "$LOGS/docker-calls" 2>/dev/null &&
    ok "сирота → і контейнер оракула a8-orph-oracle убито" || bad "orphan oracle kill: $(cat "$LOGS/docker-calls" 2>/dev/null)"
  teardown

  # 9b. Класифікатор упав → failed, НЕ push і НЕ done (fail closed).
  setup
  enqueue 001-a "$(valid a)"
  cat >"$BIN/logic-broken-classify" <<EOF
#!/usr/bin/env bash
[[ "\$1" == classify ]] && exit 1
exec bash "$HERE/a8-tick-logic.sh" "\$@"
EOF
  A8_TICK_LOGIC="$BIN/logic-broken-classify" tick
  [[ "$(jl .result)" == failed && "$(jl .detail)" == classifier:* && ! -e "$QD/done/001-a.json" ]] &&
    ok "класифікатор упав → failed classifier, не done" || bad "classifier fail-open: $(last)"
  teardown

  # 10. Декоративний pre-commit → агент НЕ запускається.
  setup
  enqueue 001-a "$(valid a)"
  HOOK_RC=1 tick
  # Контроль: файл викликів ІСНУЄ (виклик check-hook-loud записано) — інакше
  # «claude не викликано» було б правдою з неправильної причини.
  [[ "$(jl .detail)" == hooks-decorative ]] && grep -q 'check-hook-loud' "$LOGS/runner-calls" &&
    ! grep -q 'claude' "$LOGS/runner-calls" &&
    ok "check-hook-loud ≠ 0 → failed hooks-decorative, claude не викликано" || bad "hooks: $(last)"
  teardown

  # 10b. Залежності не встановились → агент не запускається.
  setup
  enqueue 001-a "$(valid a)"
  DEPS_RC=1 tick
  [[ "$(jl .detail)" == deps ]] && grep -q 'pnpm install' "$LOGS/runner-calls" && ! grep -q 'claude' "$LOGS/runner-calls" &&
    ok "pnpm install/uv sync упали → failed deps, claude не викликано" || bad "deps: $(last)"
  teardown

  # 11. Таймаут → failed timeout І контейнер убито.
  TASK_TIMEOUT=1 setup
  enqueue 001-a "$(valid a)"
  AGENT_MODE=hang tick
  [[ "$(jl .detail)" == timeout ]] && grep -q 'docker kill a8-a' "$LOGS/docker-calls" 2>/dev/null &&
    ok "таймаут → failed timeout і docker kill a8-a" || bad "timeout: $(last); docker: $(cat "$LOGS/docker-calls" 2>/dev/null)"
  teardown

  # 12. Гілка з таким id уже є → не перезаписуємо.
  setup
  git -C "$ROOT/repo" branch ai/a origin/main
  enqueue 001-a "$(valid a)"
  tick
  [[ "$(jl .result)" == failed && "$(jl .detail)" == *"уже існує"* ]] && ok "наявна гілка ai/a → failed, не перезапис" || bad "branch exists: $(last)"
  teardown

  # 13. Два тіки одночасно: другий не бере задачу.
  setup
  enqueue 001-a "$(valid a)"
  flock "$LOGS/tick.lock" sleep 5 &
  holder=$!
  sleep 0.5
  tick
  [[ "$(jl .event)" == busy && -e "$QD/001-a.json" ]] && ok "lock зайнятий → event busy, задача не взята" || bad "flock: $(last)"
  wait "$holder"
  teardown

  # 14. worktree не створився → merge-base guard ловить до запуску агента.
  setup
  enqueue 001-a "$(valid a)"
  chmod 555 "$ROOT/wt"
  tick
  chmod 755 "$ROOT/wt"
  [[ "$(jl .detail)" == "worktree не на origin/main" ]] && ! grep -q claude "$LOGS/runner-calls" 2>/dev/null &&
    ok "worktree не на origin/main → failed до запуску агента" || bad "merge-base guard: $(last)"
  teardown

  # 15. fetch упав → failed git fetch.
  setup
  enqueue 001-a "$(valid a)"
  mv "$ROOT/origin.git" "$ROOT/origin.gone"
  tick
  [[ "$(jl .detail)" == "git fetch" ]] && ok "git fetch упав → failed git fetch" || bad "fetch: $(last)"
  mv "$ROOT/origin.gone" "$ROOT/origin.git"
  teardown

  # 16. guard повернув невідомий код → guard_error і НЕНУЛЬОВИЙ вихід тіку.
  setup
  printf '#!/usr/bin/env bash\nexit 1\n' >"$BIN/guard-broken"
  chmod +x "$BIN/guard-broken"
  enqueue 001-a "$(valid a)"
  rc="$(A8_GUARD="$BIN/guard-broken" tick_rc)"
  [[ "$rc" == 1 && "$(jl .event)" == guard_error ]] && ok "guard → 1 → event guard_error, тік виходить з 1" || bad "guard_error: rc=$rc $(last)"
  teardown

  # 17. Push — гілки коду, не механіка креденшала (його не існує).
  PUSH_KIND=token_file setup
  enqueue 001-a "$(valid a)"
  tick
  [[ "$(jl .result)" == ok && "$(jl .detail)" == pushed ]] && git -C "$ROOT/origin.git" rev-parse -q --verify refs/heads/ai/a >/dev/null &&
    ok "token_file: push у origin → ok pushed, гілка ai/a на origin" || bad "push token_file: $(last)"
  teardown
  PUSH_KIND=deploy_key setup
  enqueue 001-a "$(valid a)"
  tick
  [[ "$(jl .result)" == ok ]] && git -C "$ROOT/origin.git" rev-parse -q --verify refs/heads/ai/a >/dev/null &&
    ok "deploy_key: push на A8_PUSH_SSH_URL → ok" || bad "push deploy_key: $(last)"
  teardown
  PUSH_KIND=token_file setup
  enqueue 001-a "$(valid a)"
  chmod -R a-w "$ROOT/origin.git"
  tick
  chmod -R u+w "$ROOT/origin.git"
  [[ "$(jl .result)" == failed && "$(jl .detail)" == push ]] && ok "push відхилено → failed push, не ok" || bad "push fail: $(last)"
  teardown
  PUSH_KIND=weird setup
  enqueue 001-a "$(valid a)"
  tick
  [[ "$(jl .result)" == failed ]] && ok "невідомий A8_PUSH_CREDENTIAL_KIND → failed" || bad "unknown kind: $(last)"
  teardown

  # ─── 18. Оракул приймання ────────────────────────────────────────────────
  # Головна пара сценаріїв: ОДИН І ТОЙ САМИЙ оракул на двох різних результатах
  # агента. Якщо вердикт не розходиться — оракул нічого не доводить (docs/02
  # п.4: він мусить червоніти на НЕПРАВИЛЬНОМУ результаті, а не лише на
  # відсутньому). Перевіряти «оракул викликано» замість цього означало б
  # повторити помилку 2026-09-20.
  PUSH_KIND=token_file setup
  enqueue 001-a "$(with_oracle a 'grep -q MARKER result.txt')"
  AGENT_MODE=work tick
  [[ "$(jl .result)" == ok && "$(jl .oracle_rc)" == 0 ]] &&
    git -C "$ROOT/origin.git" rev-parse -q --verify refs/heads/ai/a >/dev/null &&
    ok "агент зробив роботу → оракул зелений (oracle_rc 0), гілка на origin" || bad "оракул на правильній роботі: $(last)"
  teardown

  PUSH_KIND=token_file setup
  enqueue 001-a "$(with_oracle a 'grep -q MARKER result.txt')"
  AGENT_MODE=commit tick
  [[ "$(jl .result)" == failed && "$(jl .detail)" == oracle* && "$(jl .oracle_rc)" != 0 ]] &&
    ok "той самий оракул на порожньому коміті → failed oracle" || bad "оракул на неправильній роботі: $(last)"
  git -C "$ROOT/origin.git" rev-parse -q --verify refs/heads/ai/a >/dev/null &&
    bad "червоний оракул: гілку все одно запушено на origin" ||
    ok "червоний оракул → на origin не запушено нічого"
  git -C "$ROOT/repo" rev-parse --verify -q refs/heads/ai/a >/dev/null && [[ -d "$ROOT/wt/a" ]] &&
    ok "червоний оракул: гілка і worktree збережені як доказ для людини" || bad "доказ прибрано"
  teardown

  # 18b. Задача, що впала ДО оракула, мусить відрізнятись у журналі від
  # прийнятої машиною: oracle_rc = «-», а не 0.
  setup
  enqueue 001-a "$(valid a)"
  AGENT_MODE=nocommit tick
  [[ "$(jl .oracle_rc)" == "-" ]] &&
    ok "падіння до оракула → oracle_rc «-» (не плутається із зеленим 0)" || bad "oracle_rc: $(last)"
  teardown

  # 18c. МЕЖА, заради якої розділялись дієслова guard'а: остання дозволена
  # задача дня. Лічильник уже інкрементовано, і зі старим `check` в обгортці
  # оракул отримував би 11 — тобто демон валив би задачу, яку агент виконав.
  PUSH_KIND=token_file setup 1
  enqueue 001-a "$(with_oracle a 'grep -q MARKER result.txt')"
  AGENT_MODE=work tick
  [[ "$(jl .result)" == ok && "$(jl .oracle_rc)" == 0 ]] &&
    ok "ліміт 1: оракул останньої задачі дня проганяється і зеленіє" || bad "оракул на межі ліміту: $(last)"
  teardown

  # 18d. STOP наприкінці сесії агента: без перевірки після агента його побачила
  # б лише обгортка оракула (код 10), і демон записав би «червоний оракул» —
  # звинуватив би агента в рішенні людини.
  PUSH_KIND=token_file setup
  enqueue 001-a "$(valid a)"
  AGENT_MODE=stopafter tick
  [[ "$(jl .result)" == stopped && "$(jl .detail)" == *"kill switch"* ]] &&
    ok "STOP наприкінці сесії агента → stopped, а не failed oracle" || bad "STOP наприкінці сесії: $(last)"
  grep -q failed "$LOGS/last-results" 2>/dev/null &&
    bad "зупинка людиною зарахована в падіння поспіль" || ok "зупинка людиною не зарахована в падіння"
  teardown

  # ─── 19. Backstop заборонених шляхів ─────────────────────────────────────
  # CLAUDE.md §6.1: «deny-правила + backstop-скрипт». Deny-правила ловлять
  # Edit/Write, а не Bash — тож кожен сценарій пише заборонене саме через
  # git/bash. Оракул скрізь ЗЕЛЕНИЙ і креденшал є: зупинити push мусить
  # backstop, а не щось інше.
  forbidden_case() { # forbidden_case <режим> <опис>
    PUSH_KIND=token_file setup
    enqueue 001-a "$(valid a)"
    AGENT_MODE="$1" tick
    if [[ "$(jl .result)" == failed && "$(jl .detail)" == forbidden-paths* ]] &&
      ! git -C "$ROOT/origin.git" rev-parse -q --verify refs/heads/ai/a >/dev/null; then
      ok "$2 → failed forbidden-paths, на origin нічого"
    else
      bad "$2: $(last); origin ai/a: $(git -C "$ROOT/origin.git" rev-parse -q --verify refs/heads/ai/a || echo немає)"
    fi
    teardown
  }
  # 19a. Базовий випадок.
  forbidden_case forbidden "агент записав infra/x через bash"
  # 19b. Контроль: чиста робота backstop проходить.
  PUSH_KIND=token_file setup
  enqueue 001-a "$(with_oracle a 'grep -q MARKER result.txt')"
  AGENT_MODE=work tick
  [[ "$(jl .result)" == ok && "$(jl .detail)" == pushed ]] &&
    ok "чиста робота → backstop пропускає, push ok" || bad "backstop на чистій роботі: $(last)"
  teardown
  # 19c. Перейменування: без --no-renames diff показав би лише notes.md.
  forbidden_case rename "CLAUDE.md перейменовано в notes.md"
  # 19d. Diff від SHA бази, а не від origin/main, який агент може пересунути.
  forbidden_case moveorigin "origin/main пересунуто на заборонений коміт"
  # 19e. Перевіряється те, що пушиться (гілка), а не HEAD.
  forbidden_case detach "гілка на забороненому, HEAD — на чистому"
  # 19f. `git replace` підміняє вміст для diff, але не для push.
  forbidden_case replace "заборонений коміт підмінено через git replace"
  # 19h. Кирилиця й лапки в імені — `git diff` без -z бере шлях у лапки.
  forbidden_case cyrillic "infra/тест.sh (кирилиця в імені)"
  forbidden_case quote "infra/a\"b (лапки в імені)"
  # 19i. «Є коміти» рахується від бази до гілки, а не від origin/main до HEAD:
  # коміт на відокремленому HEAD інакше дав би push гілки без змін як «ok».
  PUSH_KIND=token_file setup
  enqueue 001-a "$(valid a)"
  AGENT_MODE=detachonly tick
  if [[ "$(jl .result)" == failed && "$(jl .detail)" == no-commits ]] &&
    ! git -C "$ROOT/origin.git" rev-parse -q --verify refs/heads/ai/a >/dev/null; then
    ok "коміт лише на відокремленому HEAD → failed no-commits, нічого не запушено"
  else
    bad "коміт на відокремленому HEAD: $(last)"
  fi
  teardown
  # 19j. Скрипта backstop немає (роль не доставила) → fail closed, з поясненням.
  PUSH_KIND=token_file setup
  enqueue 001-a "$(with_oracle a 'grep -q MARKER result.txt')"
  A8_FORBIDDEN_CHECK="$ROOT/немає.sh" AGENT_MODE=work tick
  if [[ "$(jl .result)" == failed && "$(jl .detail)" == "forbidden-paths: перевірку не виконано"* ]] &&
    ! git -C "$ROOT/origin.git" rev-parse -q --verify refs/heads/ai/a >/dev/null; then
    ok "скрипта backstop немає → failed «перевірку не виконано», нічого не запушено"
  else
    bad "backstop без скрипта: $(last)"
  fi
  teardown
  # 19g. Оракул виконує код агента й може зсунути гілку ПІСЛЯ перевірки.
  # Пушиться рівно той SHA, що пройшов backstop.
  PUSH_KIND=token_file setup
  enqueue 001-a "$(with_oracle a 'grep -q MARKER result.txt && mkdir -p infra && echo x >infra/x && git add infra/x && git -c user.email=o@o -c user.name=o commit -q -m sneaky')"
  AGENT_MODE=work tick
  if [[ "$(jl .result)" == ok ]] && git -C "$ROOT/origin.git" rev-parse -q --verify refs/heads/ai/a >/dev/null &&
    [[ -z "$(git -C "$ROOT/origin.git" ls-tree -r --name-only ai/a -- infra)" ]]; then
    ok "оракул зсунув гілку після backstop → запушено перевірений SHA, без infra/"
  else
    bad "зсув гілки після backstop: $(last); infra на origin: $(git -C "$ROOT/origin.git" ls-tree -r --name-only ai/a -- infra 2>&1)"
  fi
  teardown

  # ─── 20. Kill switch посеред задачі ──────────────────────────────────────
  # Зупинка — рішення людини: ні запису падіння, ні +1 до «трьох поспіль».
  # Без комітів задача повертається в чергу, з комітами — лишається у failed/.
  no_failures() { ! grep -q failed "$LOGS/last-results" 2>/dev/null; }
  requeued() { # requeued <опис>
    if [[ "$(jl .result)" == stopped && "$(jl .detail)" == "kill switch "* && -e "$QD/001-a.json" ]] && no_failures &&
      ! git -C "$ROOT/repo" rev-parse -q --verify refs/heads/ai/a >/dev/null && [[ ! -e "$ROOT/wt/a" ]]; then
      ok "$1 → stopped, задача в черзі, падінь 0, порожні гілку й worktree прибрано"
    else
      bad "$1: $(last); last-results: $(cat "$LOGS/last-results" 2>/dev/null)"
    fi
  }
  kept() { # kept <опис> — з комітами: failed/ з позначкою, гілка на місці, падінь 0
    if [[ "$(jl .result)" == stopped && "$(jl .detail)" == *"гілка має коміти"* && -e "$QD/failed/001-a.json" ]] &&
      no_failures && git -C "$ROOT/repo" rev-parse -q --verify refs/heads/ai/a >/dev/null; then
      ok "$1 → stopped, задача у failed/ з позначкою, гілка з комітами на місці, падінь 0"
    else
      bad "$1: $(last); last-results: $(cat "$LOGS/last-results" 2>/dev/null)"
    fi
  }

  # 20a–c. STOP на залежностях і хуку: наступний старт контейнера отримує 10.
  # Агент не запускався — денний ліміт не витрачено; назва етапу — чесна.
  for case in "pnpm:під час залежностей" "uvsync:під час перевірки хука" "hook:перед агентом"; do
    stage="${case%%:*}" want="kill switch ${case#*:}"
    setup
    enqueue 001-a "$(valid a)"
    STOP_DURING="$stage" tick
    requeued "STOP під час $stage"
    grep -q 'run-agent claude' "$LOGS/runner-calls" 2>/dev/null && bad "STOP під час $stage: агента все одно запущено" ||
      ok "STOP під час $stage: агента не запущено"
    [[ "$(jl .detail)" == "$want" && ! -s "$LOGS/counter-$(date -u +%Y-%m-%d)" ]] &&
      ok "STOP під час $stage: деталь «$want», денний ліміт не витрачено" ||
      bad "STOP під час $stage: деталь «$(jl .detail)», лічильник «$(cat "$LOGS/counter-$(date -u +%Y-%m-%d)" 2>/dev/null)»"
    teardown
  done

  # 20d. Код 10 на залежностях, а STOP уже прибрали: це однаково обгортка.
  setup
  enqueue 001-a "$(valid a)"
  DEPS_RC=10 tick
  requeued "код 10 на залежностях без STOP"
  [[ ! -s "$LOGS/counter-$(date -u +%Y-%m-%d)" ]] && ok "код 10 на залежностях: денний ліміт не витрачено" ||
    bad "код 10 на залежностях: лічильник $(cat "$LOGS/counter-$(date -u +%Y-%m-%d)")"
  teardown

  # 20e. STOP посеред довгої сесії агента з комітами: спостерігач помічає його
  # за секунди й зупиняє саме контейнер агента, а не чекає A8_TASK_TIMEOUT (20 с).
  setup
  enqueue 001-a "$(valid a)"
  t0="$(date +%s)"
  AGENT_MODE=sleepstop tick
  dt=$(($(date +%s) - t0))
  kept "STOP посеред сесії агента (коміти є)"
  ev="$(grep '"event":"kill_switch"' "$LOGS/runs.log" | head -1)"
  [[ "$(jq -r .detail <<<"$ev")" == *"під час агента"*"a8-a" ]] && grep -qx 'docker kill a8-a' "$LOGS/docker-calls" &&
    ok "спостерігач: подія kill_switch «STOP помічено під час агента», docker kill a8-a" ||
    bad "спостерігач агента: подія «$ev»; docker: $(cat "$LOGS/docker-calls" 2>/dev/null)"
  ((dt < 10)) && ok "зупинка за ${dt} с, а не за A8_TASK_TIMEOUT" || bad "зупинка за ${dt} с — спостерігач не спрацював"
  (($(tick_procs) == 0)) && ok "після зупинки жодного процесу тіку (спостерігача) не лишилось" ||
    bad "після зупинки лишились процеси тіку: $(tick_procs)"
  teardown

  # 20f. Те саме без комітів → у чергу.
  setup
  enqueue 001-a "$(valid a)"
  AGENT_MODE=sleepstop0 tick
  requeued "STOP посеред сесії агента (комітів немає)"
  teardown

  # 20g. 137 без STOP і без мітки — OOM чи чуже вбивство: падіння, як і було.
  setup
  enqueue 001-a "$(valid a)"
  AGENT_MODE=oom tick
  [[ "$(jl .result)" == failed && "$(jl .detail)" == "rc=137" && "$(tail -n 1 "$LOGS/last-results" 2>/dev/null)" == failed ]] &&
    ok "137 без STOP → failed rc=137, падіння зараховано" || bad "137 без STOP: $(last)"
  teardown

  # 20h. Спостерігач зупинив контейнер, а людина встигла прибрати STOP: мітка
  # лишається, це зупинка. І мітка не переживає задачу: повернута в чергу, вона
  # наступним тіком виконується, а не «зупиняється» вдруге.
  setup
  enqueue 001-a "$(valid a)"
  DOCKER_RM_STOP=1 AGENT_MODE=sleepstop0 tick
  [[ ! -e "$ROOT/STOP" ]] && requeued "спостерігач зупинив, STOP уже прибрано (лише мітка)" ||
    bad "20h: STOP не прибрано заглушкою — сценарій нічого не перевіряє"
  tick
  [[ "$(jl .result)" == no-credential && "$(jl .task)" == a ]] &&
    ok "повернута задача наступним тіком виконується — мітку попередньої спроби скинуто" || bad "мітка пережила задачу: $(last)"
  teardown

  # 20i. STOP посеред оракула → спостерігач зупиняє контейнер ОРАКУЛА.
  PUSH_KIND=token_file setup
  enqueue 001-a "$(with_oracle a "grep -q MARKER result.txt && touch '$ROOT/STOP' && sleep $HANG_S")"
  t0="$(date +%s)"
  AGENT_MODE=work tick
  dt=$(($(date +%s) - t0))
  kept "STOP посеред оракула"
  [[ "$(jl .detail)" == *"під час оракула"* ]] && grep -qx 'docker kill a8-a-oracle' "$LOGS/docker-calls" && ((dt < 10)) &&
    ok "спостерігач оракула: docker kill a8-a-oracle за ${dt} с" ||
    bad "спостерігач оракула: $(last); ${dt} с; docker: $(cat "$LOGS/docker-calls" 2>/dev/null)"
  git -C "$ROOT/origin.git" rev-parse -q --verify refs/heads/ai/a >/dev/null &&
    bad "STOP посеред оракула: гілку все одно запушено" || ok "STOP посеред оракула: на origin нічого"
  teardown

  # 20j. Оракул зелений, STOP з'явився одразу після — перед push. Push — єдиний
  # крок назовні; гілка лишається локально.
  PUSH_KIND=token_file setup
  enqueue 001-a "$(with_oracle a "grep -q MARKER result.txt && touch '$ROOT/STOP'")"
  AGENT_MODE=work tick
  kept "STOP перед push"
  [[ "$(jl .detail)" == *"перед push"* && "$(jl .oracle_rc)" == 0 ]] &&
    ! git -C "$ROOT/origin.git" rev-parse -q --verify refs/heads/ai/a >/dev/null &&
    ok "STOP перед push: оракул зелений, на origin нічого, деталь «перед push»" || bad "STOP перед push: $(last)"
  teardown

  # 20l. 401 разом зі STOP: причина 401 важливіша — auth_stop, і файл STOP
  # містить «claude setup-token», а не порожній рядок людини.
  setup
  enqueue 001-a "$(valid a)"
  AGENT_MODE=authstop tick
  [[ "$(jl .result)" == auth_stop ]] && grep -q 'setup-token' "$ROOT/STOP" &&
    ok "401 і STOP одночасно → auth_stop, у STOP — причина 401" || bad "401 і STOP: $(last); STOP: $(cat "$ROOT/STOP" 2>/dev/null)"
  teardown

  # 20m. Перший docker kill б'є в порожнечу (контейнера ще немає): спостерігач
  # не здається, а повторює kill наступного інтервалу.
  setup
  enqueue 001-a "$(valid a)"
  t0="$(date +%s)"
  DOCKER_KILL_FAIL_ONCE=1 AGENT_MODE=sleepstop tick
  dt=$(($(date +%s) - t0))
  kills="$(grep -cx 'docker kill a8-a' "$LOGS/docker-calls" 2>/dev/null)"
  [[ "$(jl .result)" == stopped ]] && ((dt < 10 && kills >= 2)) &&
    ok "перший kill не влучив → спостерігач повторив (${kills} спроби), зупинка за ${dt} с" ||
    bad "повтор kill: $(last); спроб ${kills:-0}; ${dt} с"
  teardown

  # 20k. Спостерігач не переживає тік: ні звичайну задачу, ні TERM (systemd
  # stop), ні KILL — тоді trap не спрацьовує, і спостерігач виходить сам.
  WATCH_S=3 setup
  enqueue 001-a "$(valid a)"
  tick
  (($(tick_procs) == 0)) && ok "після звичайної задачі жодного процесу тіку не лишилось" ||
    bad "після звичайної задачі лишились процеси тіку: $(tick_procs)"
  teardown
  # Сигнал — лише коли спостерігач точно живий (мітка заглушки агента), а не
  # через фіксований sleep: під навантаженням (мутанти йдуть паралельно) тік за
  # 2 с міг не дійти до watch_start — тоді спостерігача, який мав би лишитись,
  # ще не було, і мутанти «trap EXIT прибрано» / «спостерігач не бачить, що тіку
  # вже немає» виживали випадково (#243, 15.10 — червоний main).
  #   TERM: інтервал 30 с — без trap спостерігач гарантовано ще живий у мить
  #   перевірки; з trap його прибирають одразу.
  #   KILL: інтервал 1 с — спостерігач мусить зникнути сам; чекаємо до 10 с
  #   з опитуванням (мутант «while :» не зникне ніколи).
  for sig in TERM KILL; do
    if [[ "$sig" == TERM ]]; then WATCH_S=30 setup; else WATCH_S=1 setup; fi
    enqueue 001-a "$(valid a)"
    AGENT_MODE=hang bash "$BIN/a8-tick" >>"$LOGS/tick.out" 2>&1 &
    tp=$!
    for _ in $(seq 1 300); do
      [[ -e "$ROOT/agent-started" ]] && break
      kill -0 "$tp" 2>/dev/null || break # тік помер до агента — не чекати 30 с
      sleep 0.1
    done
    if [[ ! -e "$ROOT/agent-started" ]]; then
      bad "тік не дійшов до агента (помер раніше або 30 с минуло) — сценарій $sig не перевірено"
      kill -9 "$tp" 2>/dev/null
      wait "$tp" 2>/dev/null
      teardown
      continue
    fi
    kill -"$sig" "$tp" 2>/dev/null
    wait "$tp" 2>/dev/null
    if [[ "$sig" == KILL ]]; then
      for _ in $(seq 1 100); do (($(tick_procs) == 0)) && break; sleep 0.1; done
    fi
    (($(tick_procs) == 0)) && ok "тік отримав $sig посеред агента → спостерігача не лишилось" ||
      bad "тік отримав $sig → лишились процеси тіку: $(tick_procs)"
    teardown
  done

  # 21. Образу агента немає (issue #117: 2026-10-11 docker-prune видалив його, і
  # три задачі поспіль стали failed — пауза черги). Тепер задачу не беруть: вона
  # лишається в черзі, у журналі env_broken image_missing, а лічильник падінь і
  # денний ліміт не ростуть. Тіки без образу нижче порогу (3) — не пауза: щойно
  # образ є, та сама задача виконується наступним тіком.
  setup
  enqueue 001-a "$(valid a)"
  for _ in 1 2; do IMAGE_MISSING=1 tick; done
  [[ ! -e "$ROOT/STOP" ]] && ok "два тіки без образу (нижче порогу) → STOP не поставлено" ||
    bad "STOP нижче порогу: $(cat "$ROOT/STOP")"
  [[ "$(jl .event)" == env_broken && "$(jl .detail)" == "image_missing: hart-agent:test"* ]] &&
    ok "образу немає → event env_broken, detail «image_missing: <образ>»" || bad "image_missing: $(last)"
  [[ -e "$QD/001-a.json" && -z "$(find "$QD/running" "$QD/failed" "$QD/done" -name '*.json')" ]] &&
    ok "образу немає → задача лишається в черзі (не running/, не failed/)" ||
    bad "image_missing: задача не в черзі: $(find "$QD" -name '*.json')"
  [[ ! -s "$LOGS/runner-calls" ]] && ok "образу немає → обгортку не запущено жодного разу" ||
    bad "image_missing: обгортку запущено: $(cat "$LOGS/runner-calls")"
  cnt="$(cat "$LOGS/counter-$(date -u +%Y-%m-%d)" 2>/dev/null || echo 0)"
  ! grep -q failed "$LOGS/last-results" 2>/dev/null && [[ "${cnt:-0}" == 0 ]] &&
    ok "тіки без образу → лічильник failed і денний ліміт не зросли" ||
    bad "image_missing: last-results «$(cat "$LOGS/last-results" 2>/dev/null)», лічильник «$cnt»"
  [[ "$(grep -c '"event":"env_broken"' "$LOGS/runs.log")" == 2 ]] &&
    ok "кожен тік без образу пише env_broken (2 з 2)" || bad "env_broken: $(cat "$LOGS/runs.log")"
  grep -qx 'docker image inspect hart-agent:test' "$LOGS/docker-calls" 2>/dev/null &&
    ok "перевіряється образ із конфігу (A8_CONTAINER_IMAGE)" ||
    bad "перевірка образу: $(cat "$LOGS/docker-calls" 2>/dev/null)"
  tick
  [[ "$(jl .task)" == a && "$(jl .result)" == no-credential && -e "$QD/done/001-a.json" ]] &&
    ok "образ з'явився → та сама задача виконується наступним тіком (паузи немає)" || bad "після образу: $(last)"
  [[ ! -e "$LOGS/env-broken-streak" ]] && ok "тік з образом скинув серію env_broken" ||
    bad "серію не скинуто: $(cat "$LOGS/env-broken-streak")"
  teardown

  # 21b. Сигнал людині: подія в журналі нікого не кличе (рецензія Flash, PR #232).
  # На A8_CONSECUTIVE_FAILURE_LIMIT-му тіку поспіль без образу тік пише kill
  # switch із причиною і ліками; далі черга стоїть як при 401, задача — в черзі.
  setup
  enqueue 001-a "$(valid a)"
  for _ in 1 2 3; do IMAGE_MISSING=1 tick; done
  [[ -e "$ROOT/STOP" ]] && grep -q 'hart-agent:test' "$ROOT/STOP" && grep -q 'ansible-playbook' "$ROOT/STOP" &&
    ok "третій тік поспіль без образу → STOP з образом і ліками" || bad "STOP після 3: $(cat "$ROOT/STOP" 2>/dev/null || echo немає)"
  IMAGE_MISSING=1 tick
  [[ "$(jl .event)" == kill_switch && -e "$QD/001-a.json" ]] &&
    ok "після STOP тік зупиняється запобіжником, задача ціла в черзі" || bad "після STOP: $(last)"
  ! grep -q failed "$LOGS/last-results" 2>/dev/null && ok "STOP за образом — не падіння (last-results без failed)" ||
    bad "last-results: $(cat "$LOGS/last-results")"
  teardown

  # 21c. Серію рахуємо ПОСПІЛЬ: тік з образом між збоями її скидає, тож два
  # окремі збої docker (рестарт) STOP не ставлять.
  setup
  enqueue 001-a "$(valid a)"
  for _ in 1 2; do IMAGE_MISSING=1 tick; done
  tick
  enqueue 002-b "$(valid b)"
  for _ in 1 2; do IMAGE_MISSING=1 tick; done
  [[ ! -e "$ROOT/STOP" && "$(cat "$LOGS/env-broken-streak" 2>/dev/null)" == 2 ]] &&
    ok "2 збої + тік з образом + 2 збої → серія 2, STOP немає" ||
    bad "серія не поспіль: STOP=$([[ -e "$ROOT/STOP" ]] && echo є || echo немає), серія=$(cat "$LOGS/env-broken-streak" 2>/dev/null)"
  teardown

  # 21d. Серію скидає будь-який тік, що бачить образ, — і з порожньою чергою, і
  # під STOP (контрприклад 3.1, PR #232). Інакше стара серія переживала ліки, і
  # перший разовий збій docker одразу ставив STOP.
  setup
  echo 2 >"$LOGS/env-broken-streak"
  tick
  [[ ! -e "$LOGS/env-broken-streak" ]] && ok "порожня черга, образ є → стару серію скинуто" ||
    bad "серія при порожній черзі: $(cat "$LOGS/env-broken-streak")"
  echo 2 >"$LOGS/env-broken-streak"
  touch "$ROOT/STOP"
  enqueue 001-a "$(valid a)"
  tick
  [[ ! -e "$LOGS/env-broken-streak" && "$(jl .event)" == kill_switch ]] &&
    ok "під STOP, образ є → серію скинуто (до запобіжників)" || bad "серія під STOP: $(cat "$LOGS/env-broken-streak" 2>/dev/null); $(last)"
  rm -f "$ROOT/STOP"
  IMAGE_MISSING=1 tick
  [[ ! -e "$ROOT/STOP" && "$(cat "$LOGS/env-broken-streak")" == 1 ]] &&
    ok "після скидання разовий збій → серія 1, STOP немає" || bad "після скидання: серія $(cat "$LOGS/env-broken-streak" 2>/dev/null)"
  teardown

  # 21e. docker не відповідає — STOP не бреше, що образу немає (контрприклад 2.3).
  setup
  enqueue 001-a "$(valid a)"
  for _ in 1 2 3; do DOCKER_DOWN=1 tick; done
  [[ "$(jl .detail)" == "docker_unavailable: hart-agent:test — failed to connect to the docker API"* ]] &&
    ok "docker не відповідає → env_broken docker_unavailable з першим рядком stderr" || bad "docker_unavailable: $(last)"
  stop_txt="$(cat "$ROOT/STOP" 2>/dev/null)"
  [[ "$stop_txt" == *"failed to connect to the docker API"* && "$stop_txt" == *"systemctl status docker"* && "$stop_txt" != *"Образу агента"* ]] &&
    ok "STOP: справжня причина й ліки docker, без «образу немає»" || bad "STOP docker_unavailable: ${stop_txt:-немає}"
  teardown

  # 21f. inspect висить — тік не тримає flock безкінечно, це теж збій середовища
  # (контрприклад 2.2).
  setup
  enqueue 001-a "$(valid a)"
  t0="$(date +%s)"
  IMAGE_HANG=1 A8_INSPECT_TIMEOUT_S=1 tick
  dt=$(($(date +%s) - t0))
  [[ "$(jl .detail)" == "docker_unavailable:"*"не відповів за 1 с"* && "$(cat "$LOGS/env-broken-streak")" == 1 ]] && ((dt < 10)) &&
    ok "завислий inspect → таймаут за ${dt} с, env_broken, серія 1" || bad "завислий inspect: ${dt} с; $(last)"
  # -x: точний збіг усього рядка — без нього «sleep 30.1234» збігався б як
  # підрядок із «sleep 30.12345» паралельного прогону (рецензія Flash #259).
  pkill -x -f "sleep $HANG_S" 2>/dev/null
  teardown

  # 21g. Серію не записати (повний диск) — вести лічбу нічим, тож STOP одразу,
  # а не серія, що застрягла на 1 (контрприклад 3.3).
  setup
  enqueue 001-a "$(valid a)"
  mkdir "$LOGS/env-broken-streak.tmp"
  IMAGE_MISSING=1 tick
  [[ -e "$ROOT/STOP" ]] && ok "серію не записати → STOP з першого збою" || bad "збій запису серії: STOP немає"
  teardown

  # 21h. Людина створила STOP із власною причиною, поки тік питав docker (після
  # запобіжників): тік не затирає її своїм текстом (noclobber, контрприклад 2.5).
  setup
  enqueue 001-a "$(valid a)"
  echo 2 >"$LOGS/env-broken-streak"
  STOP_DURING=inspect IMAGE_MISSING=1 tick
  [[ "$(cat "$ROOT/STOP" 2>/dev/null)" == "причина людини" && "$(jl .event)" == env_broken ]] &&
    ok "STOP людини під час inspect не затерто" || bad "STOP затерто: $(cat "$ROOT/STOP" 2>/dev/null)"
  teardown

  # 22a. Невідкладна (urgent/, a8-queue enqueue --urgent) береться ПЕРШОЮ, навіть
  # коли в плановому потоці є старіша задача (рішення yurii 2026-10-19, #262).
  setup
  enqueue 001-a "$(valid a)"
  mkdir -p "$QD/urgent"
  valid u >"$QD/urgent/urgent-20261020T000000Z-u.json"
  tick
  [[ "$(jl .task)" == u && -e "$QD/001-a.json" && -e "$QD/done/urgent-20261020T000000Z-u.json" ]] &&
    ok "urgent/ береться першою, планова 001-a чекає" || bad "urgent першою: $(last); $(find "$QD" -name '*.json')"
  teardown

  # 22b. Плановий потік на паузі (a8-queue pause): планову не беремо, невідкладну —
  # так. Тік на паузі мовчить: подія щотіку витісняла б записи прогонів (#231).
  setup
  enqueue 001-a "$(valid a)"
  date -u +%FT%TZ >"$LOGS/planned-paused"
  tick
  [[ -e "$QD/001-a.json" && ! -s "$LOGS/runs.log" && ! -e "$LOGS/runner-calls" ]] &&
    ! grep -q 'image inspect' "$LOGS/docker-calls" 2>/dev/null &&
    ok "плановий потік на паузі → планову не взято, docker і обгортку не чіпали, runs.log порожній" ||
    bad "пауза планового: $(cat "$LOGS/runs.log" 2>/dev/null); $(find "$QD" -name '*.json')"
  mkdir -p "$QD/urgent"
  valid u >"$QD/urgent/urgent-20261020T000000Z-u.json"
  tick
  [[ "$(jl .task)" == u && "$(jl .result)" == no-credential && -e "$QD/001-a.json" ]] &&
    ok "на паузі планового потоку невідкладна виконується, планова чекає" || bad "urgent на паузі: $(last)"
  rm -f "$LOGS/planned-paused"
  tick
  [[ "$(jl .task)" == a ]] && ok "після resume планова виконується" || bad "після resume: $(last)"
  teardown

  # 22c. Невідкладну, яку не виконали (STOP на залежностях), тік повертає в urgent/,
  # а не в плановий потік — інакше вона стала б у хвіст і на паузі не взялась би.
  setup
  mkdir -p "$QD/urgent"
  valid u >"$QD/urgent/urgent-20261020T000000Z-u.json"
  STOP_DURING=pnpm tick
  [[ "$(jl .result)" == stopped && -e "$QD/urgent/urgent-20261020T000000Z-u.json" && -z "$(find "$QD" -maxdepth 1 -name '*.json')" ]] &&
    ok "зупинена невідкладна повертається в urgent/" || bad "повернення urgent: $(last); $(find "$QD" -name '*.json')"
  teardown

  # 22e. Тік бере задачу (і переносить її далі) лише під queue.lock — тим самим, під
  # яким a8-queue enqueue перевіряє теки (контрприклад 3, PR #272).
  setup
  enqueue 001-a "$(valid a)"
  : >"$LOGS/queue.lock"
  flock "$LOGS/queue.lock" sleep 3 &
  qholder=$!
  sleep 0.5
  tick &
  tpid=$!
  sleep 1.5
  early=1
  [[ -e "$QD/001-a.json" ]] && early=0
  wait "$tpid"
  wait "$qholder"
  [[ "$early" == 0 && "$(jl .task)" == a ]] && ok "тік чекає queue.lock і лише тоді бере задачу" ||
    bad "тік без queue.lock: early=$early $(last)"
  teardown

  # 22f. Відхилений запис іде в rejected/ теж лише під queue.lock.
  setup
  echo '{"id":"bad"}' >"$QD/001-bad.json"
  : >"$LOGS/queue.lock"
  flock "$LOGS/queue.lock" sleep 3 &
  qholder=$!
  sleep 0.5
  tick &
  tpid=$!
  sleep 1.5
  early=1
  [[ -e "$QD/001-bad.json" ]] && early=0
  wait "$tpid"
  wait "$qholder"
  [[ "$early" == 0 && -e "$QD/rejected/001-bad.json" ]] && ok "відхилений запис переноситься в rejected/ лише під queue.lock" ||
    bad "rejected без queue.lock: early=$early $(find "$QD" -name '*.json')"
  teardown

  # 22g/22h. Між вибором кандидата і взяттям (проба образу) плановий потік
  # поставили на паузу чи з'явилась невідкладна — планову не беремо, наступний тік
  # вибирає заново (контрприклад Argon 5б, PR #272).
  setup
  enqueue 001-a "$(valid a)"
  DURING_INSPECT_CMD="date -u +%FT%TZ >'$LOGS/planned-paused'" tick
  [[ -e "$QD/001-a.json" && ! -s "$LOGS/runs.log" && ! -e "$LOGS/runner-calls" ]] &&
    ok "пауза з'явилась перед взяттям → планову не взято, обгортку не запущено" ||
    bad "пауза перед взяттям: $(cat "$LOGS/runs.log" 2>/dev/null); $(find "$QD" -name '*.json')"
  rm -f "$LOGS/planned-paused"
  tick
  [[ "$(jl .task)" == a ]] && ok "після resume планова виконується" || bad "після resume (22g): $(last)"
  teardown
  setup
  enqueue 001-a "$(valid a)"
  mkdir -p "$QD/urgent"
  valid u >"$ROOT/u.json"
  DURING_INSPECT_CMD="cp '$ROOT/u.json' '$QD/urgent/urgent-20261021T000000Z-u.json'" tick
  [[ -e "$QD/001-a.json" && -e "$QD/urgent/urgent-20261021T000000Z-u.json" && ! -s "$LOGS/runs.log" ]] &&
    ok "невідкладна з'явилась перед взяттям → планову не взято" ||
    bad "urgent перед взяттям: $(cat "$LOGS/runs.log" 2>/dev/null); $(find "$QD" -name '*.json')"
  tick
  [[ "$(jl .task)" == u && -e "$QD/001-a.json" ]] && ok "наступний тік бере невідкладну, планова чекає" || bad "наступний тік (22h): $(last)"
  teardown

  # 22d. Порядок черги не залежить від локалі машини (рецензія Flash, PR #272). До
  # LC_ALL=C тік сортував у локалі A8: у en_US.UTF-8 `-` і `_` при порівнянні
  # пропускаються, і «найстаріша» за назвою задача могла йти не першою.
  if loc="$(collating_locale)"; then
    setup
    enqueue 001-z "$(valid z)"
    enqueue 001_a "$(valid a)"
    LC_ALL="$loc" tick
    [[ "$(jl .task)" == z ]] && ok "у локалі $loc тік бере 001-z.json перед 001_a.json — порядок C" ||
      bad "порядок за локаллю $loc: $(last)"
    teardown
  else
    say "⚠ 22d НЕ ПЕРЕВІРЕНО: у системі немає локалі, де 001_a сортується раніше за 001-z (locale -a)"
  fi

  # ─── 23. Контейнер-шкідник (#276) ─────────────────────────────────────────
  # Агент задачі a, крім роботи, підкладає в .git головного клону те, що git ТІКУ
  # на хості виконав би (хук, ключ конфігу, чужий commondir) або чим підмінив би
  # дані (gitdir worktree, неоднозначне origin/main). Задача b — чиста, і тік
  # бере її ДРУГИМ: fetch і worktree add в одному тіку йдуть до контейнера, тож
  # post-checkout і fsmonitor спрацювали б лише на наступному (контрприклад 4).
  # Кожен прийом — окремий сценарій: інакше перевірка commondir закрила б усі
  # прийоми разом, і мутанти ключів hgit вижили б.
  pwned() { find "$ROOT/pwn" -type f -printf '%f ' 2>/dev/null; }
  on_origin() { git -C "$ROOT/origin.git" rev-parse -q --verify "refs/heads/ai/$1" >/dev/null; }
  two_ticks() { # two_ticks <режим агента задачі a>
    PUSH_KIND=token_file setup
    enqueue 001-a "$(valid a)"
    enqueue 002-b "$(valid b)"
    AGENT_MODE="$1" tick
    r1="$(last)"
    AGENT_MODE=commit tick
  }

  # 23a. Хуки post-checkout і pre-push у .git/hooks.
  two_ticks evil-hooks
  [[ -z "$(pwned)" && "$(jq -r .detail <<<"$r1")" == pushed && "$(jl .detail)" == pushed ]] && on_origin a && on_origin b &&
    ok "23a: підкладені post-checkout і pre-push не виконались, обидві задачі запушено" ||
    bad "23a хуки: маркери [$(pwned)]; $r1; $(last)"
  teardown

  # 23b. core.fsmonitor і core.sshCommand у .git/config (fetch і worktree add
  # запис у .git/config (fsmonitor, sshCommand) переписує файл із новим inode,
  # тож знімок identity ловить задачу a і ставить STOP черги (рецензія #290
  # коло 2) — задача b не стартує. На A8 config :ro, тож такий запис неможливий
  # узагалі; самі ключі (core.fsmonitor=false, core.sshCommand) тримає статична
  # перевірка check-ansible-a8.
  two_ticks evil-config
  if [[ -z "$(pwned)" && "$(jq -r .result <<<"$r1")" == failed &&
    "$(jq -r .detail <<<"$r1")" == *"змінили identity"* && -s "$ROOT/STOP" &&
    "$(jl .event)" == kill_switch && -e "$QD/002-b.json" ]] && ! on_origin a; then
    ok "23b: запис у config → задачу a спинив знімок + STOP, задача b не стартує, нічого не виконано"
  else
    bad "23b конфіг: маркери [$(pwned)]; STOP=[$(cat "$ROOT/STOP" 2>/dev/null)]; r1=$r1; last=$(last)"
  fi
  teardown

  # 23c. remote.origin.uploadpack і receivepack у .git/config — так само: `git
  # config` міняє inside config, знімок ловить задачу a і ставить STOP. Піни
  # --upload-pack/--receive-pack тримає статична перевірка (на A8 config :ro).
  two_ticks evil-pack
  if [[ -z "$(pwned)" && "$(jq -r .result <<<"$r1")" == failed &&
    "$(jq -r .detail <<<"$r1")" == *"змінили identity"* && -s "$ROOT/STOP" &&
    "$(jl .event)" == kill_switch ]] && ! on_origin a; then
    ok "23c: запис uploadpack/receivepack у config → знімок + STOP, нічого не виконано й не запушено"
  else
    bad "23c pack: маркери [$(pwned)]; STOP=[$(cat "$ROOT/STOP" 2>/dev/null)]; r1=$r1; last=$(last)"
  fi
  teardown

  # 23d. .git/commondir на чужий .git — fail closed з поясненням, і наступна
  # задача теж, доки людина не прибере.
  two_ticks evil-commondir
  [[ -z "$(pwned)" && "$(jq -r .result <<<"$r1")" == failed && "$(jq -r .detail <<<"$r1")" == *"небезпечний .git: .git/commondir"* &&
    "$(jl .result)" == failed && "$(jl .detail)" == *"небезпечний .git: .git/commondir"* && -e "$QD/failed/001-a.json" ]] && ! on_origin a &&
    ! on_origin b && ok "23d: commondir → обидві задачі failed «небезпечний .git: .git/commondir…», нічого не виконано й не запушено" ||
    bad "23d commondir: маркери [$(pwned)]; $r1; $(last)"
  teardown

  # 23e. .git — симлінк на чужий .git.
  two_ticks evil-symlink
  [[ -z "$(pwned)" && "$(jq -r .detail <<<"$r1")" == *"небезпечний .git: .git — не тека"* &&
    "$(jl .detail)" == *"небезпечний .git: .git — не тека"* ]] && ! on_origin a &&
    ok "23e: .git-симлінк → failed з поясненням, нічого не виконано" || bad "23e симлінк: маркери [$(pwned)]; $r1; $(last)"
  teardown

  # 23f–23h. alternates, grafts, shallow — підміна історії й об'єктів: fail closed.
  for m in alternates grafts shallow; do
    two_ticks "evil-$m"
    [[ "$(jq -r .result <<<"$r1")" == failed && "$(jq -r .detail <<<"$r1")" == *"небезпечний .git: .git/"*"$m"* ]] && ! on_origin a &&
      ok "23: $m → failed «небезпечний .git: …$m…», нічого не запушено" || bad "23 $m: $r1"
    teardown
  done

  # 23i. "$wt/.git" на власний gitdir, у якому під SHA забороненого коміту —
  # чистий: diff у worktree не побачив би infra/x, push із клону віддав би його.
  two_ticks evil-wtdiff
  [[ -z "$(pwned)" && "$(jq -r .detail <<<"$r1")" == forbidden-paths:*infra/x* ]] && ! on_origin a && on_origin b &&
    ok "23i: підмінений gitdir worktree не ховає заборонений файл від backstop'а" ||
    bad "23i wt diff: маркери [$(pwned)]; $r1; $(last)"
  teardown

  # 23j. Той самий підмінений gitdir з pre-push і receivepack — push іде з клону.
  two_ticks evil-wtpush
  [[ -z "$(pwned)" && "$(jq -r .detail <<<"$r1")" == pushed ]] && on_origin a &&
    ok "23j: push не з worktree — pre-push і receivepack підміненого gitdir не виконались" ||
    bad "23j wt push: маркери [$(pwned)]; $r1"
  teardown

  # 23k. refs/tags/origin/main і refs/heads/origin/main на коміті з infra/x:
  # чиста задача b стоїть на справжньому origin/main і пушиться без infra/x.
  two_ticks evil-tag
  [[ "$(jl .detail)" == pushed ]] && on_origin b &&
    ! git -C "$ROOT/origin.git" cat-file -e refs/heads/ai/b:infra/x 2>/dev/null &&
    ok "23k: неоднозначне origin/main — задача b на справжній базі, infra/x не запушено" || bad "23k тег: $(last)"
  teardown

  # 23l. origin/main пересунуто на гілку з роботою + 401: гілку не стерто.
  setup
  enqueue 001-a "$(valid a)"
  AGENT_MODE=evil-moveorigin401 tick
  [[ "$(jl .result)" == auth_stop && "$(jl .detail)" == *"гілка має коміти"* && -e "$QD/failed/001-a.json" && -d "$ROOT/wt/a" ]] &&
    git -C "$ROOT/repo" rev-parse -q --verify refs/heads/ai/a >/dev/null &&
    ok "23l: коміти рахуються від бази тіку — гілку з роботою не стерто, задача у failed/" || bad "23l origin/main: $(last)"
  teardown

  # 23m. Гілки вже немає, rev-list падає: це не «0 комітів».
  setup
  enqueue 001-a "$(valid a)"
  AGENT_MODE=evil-delbranch tick
  [[ "$(jl .result)" == stopped && "$(jl .detail)" == *"не вдалось порахувати коміти"* && -e "$QD/failed/001-a.json" && -d "$ROOT/wt/a" ]] &&
    ok "23m: помилка rev-list → worktree лишився, задача у failed/ з поясненням" || bad "23m rev-list: $(last)"
  teardown

  # 23n. Підміна всієї .git новою текою (mv .git .git-old + свій .git з фільтром):
  # знімок identity ловить зміну dev:inode/хешу на першому тіку → fail closed +
  # STOP усієї черги (рецензія #290 коло 2). Тому наступний тік задачу b НЕ бере,
  # і smudge з підміненої .git не виконується. У тесті монтувань немає, тож
  # rename проходить; на A8 його не дасть bind самої .git (шар 1, зонд V23c).
  two_ticks evil-mvgit
  if [[ -z "$(pwned)" && "$(jq -r .result <<<"$r1")" == failed &&
    "$(jq -r .detail <<<"$r1")" == *"змінили identity"* && -s "$ROOT/STOP" &&
    "$(jl .event)" == kill_switch && -e "$QD/002-b.json" ]] && ! on_origin a; then
    ok "23n: підміна .git → failed «змінили identity» + STOP; наступний тік не бере задачу, smudge не виконано"
  else
    bad "23n mvgit: маркери [$(pwned)]; STOP=[$(cat "$ROOT/STOP" 2>/dev/null)]; r1=$r1; last=$(last)"
  fi
  teardown

  # 23o. .git/worktrees → симлінк на чужий gitdir (контрприклад Argon CX1):
  # git_unsafe_reason відкидає симлінк worktrees.
  two_ticks evil-wtsymlink
  [[ -z "$(pwned)" && "$(jq -r .detail <<<"$r1")" == *"worktrees — симлінк"* ]] && ! on_origin a &&
    ok "23o: .git/worktrees-симлінк → failed з поясненням, нічого не виконано" || bad "23o wtsymlink: маркери [$(pwned)]; $r1"
  teardown

  # 23p. Таймаут + контейнер не зупинився (docker kill не вбив): тік НЕ кличе git,
  # а робить fail closed зі STOP (рецензія #290, п.3). Інакше живий контейнер —
  # вікно гонки над .git між перевіркою hgit і самим git.
  TASK_TIMEOUT=1 setup
  enqueue 001-a "$(valid a)"
  A8_KILL_WAIT_TRIES=2 A8_KILL_WAIT_S=0 KILL_NEVER=1 AGENT_MODE=hang tick
  cnt="$(cat "$LOGS/counter-$(date -u +%Y-%m-%d)" 2>/dev/null)"
  # Задача зарахована в денний ліміт і таймаут зафіксовано (oracle_rc=124) —
  # рецензія #290 коло 2.
  [[ "$(jl .result)" == failed && "$(jl .detail)" == *"не зупинився"* && -s "$ROOT/STOP" && -d "$ROOT/wt/a" &&
    "$cnt" == 1 && "$(jl .oracle_rc)" == 124 ]] &&
    ! on_origin a && ok "23p: контейнер не зупинився → STOP, git не чіпано, задача порахована (count=1, oracle_rc=124), нічого не запушено" ||
    bad "23p stuck: $(last); cnt=$cnt; STOP=[$(cat "$ROOT/STOP" 2>/dev/null)]"
  # Прибрати завислий sleep агента (KILL_NEVER лишив його живим).
  pkill -x -f "sleep $HANG_S" 2>/dev/null
  teardown

  # 23q. Підроблений commit-graph ховає infra/x від backstop diff (контрприклад
  # Argon CX2). На de95bb1 (без -c core.commitGraph=false) diff бере дерево з
  # графа → infra/x не видно → задача пушить заборонене. З фіксом git читає сам
  # об'єкт коміту → infra/x видно → forbidden-paths. python3 — залежність тесту.
  if command -v python3 >/dev/null 2>&1; then
    PUSH_KIND=token_file setup
    enqueue 001-a "$(valid a)"
    AGENT_MODE=evil-commitgraph tick
    [[ "$(jl .result)" == failed && "$(jl .detail)" == forbidden-paths:*infra/x* ]] &&
      ! git -C "$ROOT/origin.git" rev-parse -q --verify refs/heads/ai/a >/dev/null 2>&1 &&
      ok "23q: підроблений commit-graph не ховає infra/x від backstop (core.commitGraph=false)" ||
      bad "23q commitgraph: $(last); origin ai/a: $(git -C "$ROOT/origin.git" rev-parse -q --verify refs/heads/ai/a 2>&1)"
    teardown
  else
    say "⚠ 23q НЕ ПЕРЕВІРЕНО: немає python3 для підробки commit-graph"
  fi
}

run_scenarios

# КОНТРОЛЬ ПЕРЕД МУТАЦІЯМИ. Мутант вважається вбитим, якщо набір на ньому
# падає. Якщо набір падає вже БЕЗ мутації, кожен мутант виглядає вбитим — і
# рядок «26 з 26 убиті» стає хибно-зеленим, не помітивши жодної вцілілої.
# Саме це сталося 2026-09-20: локальний прогін від root провалював два
# сценарії, що тримаються на `chmod`, друкував усі мутації вбитими, і вцілілу
# знайшла аж CI. Контроль обов'язковий (docs/16 §8.1) — тут він механізм, а не
# звичка.
if [[ -z "${A8_TICK_UNDER_TEST:-}" && "$fail" -ne 0 ]]; then
  echo
  echo "✗ мутації НЕ ганялись: базовий набір червоний (див. ✗ вище)."
  echo "  На червоному базисі кожен мутант «вбитий» за визначенням, тож результат"
  echo "  був би хибно-зеленим. Полагодь базис і запусти знову."
elif [[ -z "${A8_TICK_UNDER_TEST:-}" ]]; then
  # Мутанти незалежні (кожен прогін — власні mktemp-теки), тож ганяємо їх
  # паралельно: послідовно набір ішов би ~6 хв на кожен PR.
  MUTDIR="$(mktemp -d)"
  trap 'rm -rf "$MUTDIR"' EXIT
  n=0
  mutate() { # mutate <назва> <perl-вираз>
    n=$((n + 1))
    local m="$MUTDIR/$n.sh"
    echo "$1" >"$MUTDIR/$n.name"
    perl -0pe "$2" "$ROLE/a8-tick.sh.j2" >"$m"
    if cmp -s "$m" "$ROLE/a8-tick.sh.j2"; then
      echo "stale" >"$MUTDIR/$n.res"
      return
    fi
    if ! bash -n <(sed 's/{{[^}]*}}/x/g' "$m") 2>/dev/null; then
      echo "syntax" >"$MUTDIR/$n.res"
      return
    fi
    (
      if QUIET=1 A8_TICK_UNDER_TEST="$m" bash "$0" >/dev/null 2>&1; then
        echo "survived" >"$MUTDIR/$n.res"
      else
        echo "killed" >"$MUTDIR/$n.res"
      fi
    ) &
    # Не більше 6 одночасно.
    while (($(jobs -rp | wc -l) >= 6)); do sleep 0.2; done
  }
  # Мутації «лічильник ДО запуску» тут БІЛЬШЕ НЕМАЄ, і це не пропуск.
  # Вона тримала порядок «count після запуску» через те, що обгортка кликала
  # `a8-guard check`: перенесення лічильника вперед валило сценарій 5 кодом 11.
  # З `check-run` ліміт до старту контейнера не стосується, тож порядок на
  # поведінку не впливає — і мутація почала ВИЖИВАТИ (CI на PR #126). Мутація,
  # що не розрізняє правильне і зламане, гірша за відсутню: вона додає рядок
  # «убита» і забирає увагу. Замість неї нижче — інваріант, який досі правда.
  mutate "задача не рахується після запуску" 's/\n"\$GUARD" count >\/dev\/null\n\n# ─── 6\./\n\n# ─── 6./'
  mutate "контейнер не вбивається при таймауті" 's/if \[\[ "\$rc" == 124 \]\] && ! ensure_container_gone "\$A8_CONTAINER_NAME"; then\n  container_stuck "\$A8_CONTAINER_NAME" "агент" count\nfi/:/'
  mutate "таймаут не переконується, що контейнер зник" 's/if \[\[ "\$rc" == 124 \]\] && ! ensure_container_gone "\$A8_CONTAINER_NAME"; then\n  container_stuck "\$A8_CONTAINER_NAME" "агент" count\nfi/[[ "\$rc" == 124 ]] \&\& "\$DOCKER" kill "\$A8_CONTAINER_NAME" >\/dev\/null 2>\&1/'
  mutate "ensure_container_gone завжди каже «зник»" 's/    "\$DOCKER" inspect "\$c" >\/dev\/null 2>&1 \|\| return 0\n    sleep "\$\{A8_KILL_WAIT_S:-1\}"\n  done\n  return 1/    return 0\n  done\n  return 1/'
  mutate "container_stuck не рахує задачу" 's/  \[\[ "\$\{3:-\}" == count \]\] && "\$GUARD" count >\/dev\/null\n//'
  mutate "container_stuck не пише oracle_rc=124" 's/\n  oracle_rc=124\n  fail_task "таймаут/\n  fail_task "таймаут/'
  mutate "підміна .git не ставить STOP" 's/    if \[\[ "\$why" == \*"змінили identity"\* \]\]; then\n(.*?\n)*?    fi\n//'
  mutate "401 без kill switch" 's/"\$id" "\$\(date -u \+%FT%TZ\)" >"\$A8_KILL_SWITCH"/"\$id" "\$(date -u +%FT%TZ)" >\/dev\/null/'
  mutate "no-credential як ok" 's/finish no-credential ok/finish ok ok/'
  mutate "відхилений запис лишається в черзі" 's/  qmv "\$f" "\$Q\/rejected\/"\n//'
  mutate "перевірку хука прибрано" 's/if \(\(hrc != 0\)\); then/if false; then/'
  mutate "case без гілки за замовчуванням" 's/  ok\) ;;\n  \*\)\n(.*?\n)*?    ;;\n(esac)/$2/'
  mutate "сироту не вбито" 's/  \[\[ -n "\$oid" \]\] && "\$DOCKER" kill[^\n]*\n//'
  mutate "залежності не ставляться" 's/if \(\(drc != 0\)\); then/if false; then/'
  mutate "режим OQ-34 не експортовано" 's/\nexport A8_SOURCES_ALLOWED\n/\n/'
  mutate "flock прибрано" 's/flock -n 9 \|\| \{/true || {/'
  mutate "merge-base guard прибрано" 's/if \[\[ -z "\$base" \|\| ! -f "\$wt\/\.git" \|\|\n[^\n]*\]\]; then/if false; then/'
  mutate "падіння fetch ігнорується" 's/if ! hgit fetch/if ! true || hgit fetch/'
  mutate "сирота не записана як failed" 's/  "\$GUARD" count >\/dev\/null\n  "\$GUARD" record failed\n/  "\$GUARD" count >\/dev\/null\n/'
  mutate "guard_error виходить з 0" 's/\[\[ "\$gstate" == guard_error \]\] && exit 1/[[ "\$gstate" == guard_error ]] \&\& exit 0/'
  mutate "stopped як failed" 's/  stopped\)\n    if release_or_keep; then/  stopped)\n    fail_task stopped; exit 0\n    if release_or_keep; then/'
  mutate "порожню гілку не прибрано" 's/  if ! hgit worktree remove --force "\$wt" >>"\$log" 2>&1; then\n    keep_why=[^\n]*\n    return 1\n  fi\n  hgit branch -D "\$branch" >>"\$log" 2>&1\n  return 0/  return 0/'
  mutate "невідомий kind → ok" 's/    fail_task "невідомий A8_PUSH_CREDENTIAL_KIND"/    finish ok ok unknown done/'
  mutate "push не перевіряється" 's/      hgit push --receive-pack=git-receive-pack origin/      true || hgit push --receive-pack=git-receive-pack origin/'
  mutate "класифікатор на спільному лозі" 's/logic classify "\$rc" "\$out"/logic classify "\$rc" "\$log"/'
  mutate "оракул не проганяється" 's/timeout "\$A8_ORACLE_TIMEOUT" "\$RUNNER" "\$wt" bash -c "\$oracle" >>"\$log" 2>&1 \|\| orc=\$\?/orc=0/'
  mutate "червоний оракул ігнорується" 's/if \(\(orc != 0\)\); then/if false; then/'
  mutate "оракул після push" 's/(# ─── 6b\. Оракул(?:.*?\n)*?^fi\n\n)(# ─── 6c\.)/$2/m'
  mutate "oracle_rc завжди зелений" 's/oracle_rc="\$orc"/oracle_rc=0/'
  mutate "kill switch під час оракула як червоний оракул" 's/  if stop_requested; then stop_task "під час оракула"; fi\n//'
  mutate "стани guard злиті в один" 's/"\$JOURNAL" event "\$gstate"/"\$JOURNAL" event stopped/'
  # Backstop заборонених шляхів (сценарії 19): кожне рішення кроку 6a — окрема
  # мутація, бо кожне закриває окремий обхід.
  mutate "backstop не викликає скрипт" 's/\| bash "\$FORBIDDEN" 2>&1\)/| true 2>\&1)/'
  mutate "backstop від origin/main, а не від бази" 's/--no-renames "\$base" "\$tip"/--no-renames origin\/main "\$tip"/'
  mutate "backstop без --no-renames" 's/--name-only --no-renames "/--name-only "/'
  mutate "backstop перевіряє HEAD, а не гілку" 's/tip="\$\(hgit rev-parse --verify --quiet "refs\/heads\/\$branch\^\{commit\}"\)"/tip="\$(git -C "\$wt" rev-parse --verify --quiet HEAD)"/'
  mutate "push незакріпленої гілки" 's/"\$tip:refs\/heads\/\$branch"/"\$branch:\$branch"/g'
  mutate "backstop без -z" 's/diff -z --name-only/diff --name-only/'
  mutate "no-commits від бази до HEAD worktree" 's/ncommits="\$\(hgit rev-list --count "\$base\.\.\$tip" 2>>"\$log"\)"/ncommits="\$(git -C "\$wt" rev-list --count "\$base..HEAD")"/'
  # Kill switch посеред задачі (сценарії 20): кожне рішення — окрема мутація.
  mutate "STOP на залежностях як падіння" 's/  if \(\(drc == 10\)\) \|\| stop_requested; then stop_task "під час залежностей"; fi\n//'
  mutate "STOP на хуку як падіння" 's/  if \(\(hrc == 10\)\) \|\| stop_requested; then stop_task "під час перевірки хука"; fi\n//'
  mutate "код 10 без STOP на залежностях як падіння" 's/if \(\(drc == 10\)\) \|\| stop_requested/if stop_requested/'
  mutate "STOP після агента ігнорується" 's/if \[\[ "\$cls" != auth_stop \]\] && stop_requested; then stop_task "під час агента"; fi\n//'
  mutate "спостерігач агента не стартує" 's/watch_start "\$A8_CONTAINER_NAME" "під час агента"\n//'
  mutate "спостерігач не зупиняє контейнер" 's/        "\$DOCKER" kill "\$1" >\/dev\/null 2>&1\n//'
  mutate "спостерігач оракула зупиняє контейнер агента" 's/watch_start "\$oracle_container"/watch_start "a8-\$id"/'
  mutate "137 без STOP як зупинка" 's/stop_requested\(\) \{ \[\[ -e "\$A8_KILL_SWITCH" \|\| -e "\$seen" \]\]; \}/stop_requested() { [[ -e "\$A8_KILL_SWITCH" || -e "\$seen" || "\${rc:-}" == 137 ]]; }/'
  mutate "мітку спостерігача не враховано" 's/\[\[ -e "\$A8_KILL_SWITCH" \|\| -e "\$seen" \]\]/[[ -e "\$A8_KILL_SWITCH" ]]/'
  mutate "мітку не скинуто на старті задачі" 's/\nrm -f "\$seen"\n/\n/'
  mutate "спостерігача не прибрано після агента" 's/\nwatch_stop\nunset CLAUDE_CODE_OAUTH_TOKEN/\nunset CLAUDE_CODE_OAUTH_TOKEN/'
  mutate "trap EXIT прибрано" 's/\ntrap watch_stop EXIT\n/\n/'
  mutate "спостерігач не бачить, що тіку вже немає" 's/while kill -0 "\$\$" 2>\/dev\/null; do/while :; do/'
  mutate "перевірку STOP перед push прибрано" 's/if stop_requested; then stop_task "перед push"; fi\n//'
  mutate "спостерігач одноразовий" 's/(        "\$DOCKER" kill "\$1" >\/dev\/null 2>&1\n)/$1        exit 0\n/'
  mutate "зупинка на залежностях спалює денний ліміт" 's/  if \(\(drc == 10\)\) \|\| stop_requested; then stop_task "під час залежностей"; fi\n  "\$GUARD" count >\/dev\/null\n/  "\$GUARD" count >\/dev\/null\n  if ((drc == 10)) || stop_requested; then stop_task "під час залежностей"; fi\n/'
  mutate "без перевірки STOP перед агентом" 's/if stop_requested; then stop_task "перед агентом"; fi\n//'
  mutate "контейнер оракула сироти не вбито" 's/"a8-\$oid" "a8-\$oid-oracle"/"a8-\$oid"/'
  mutate "STOP перекриває 401" 's/if \[\[ "\$cls" != auth_stop \]\] && stop_requested/if stop_requested/'
  # Образ агента (сценарій 21, issue #117).
  mutate "тік стартує задачу без перевірки образу" 's/^if ! image_probe; then/if false; then/m'
  mutate "без образу тік іде далі" 's/(\) 2>\/dev\/null\n  fi\n)  exit 0\n/$1/'
  mutate "без образу STOP не ставиться" 's/  if \(\(streak >= A8_CONSECUTIVE_FAILURE_LIMIT\)\); then/  if false; then/'
  mutate "серія env_broken не скидається" 's/if \[\[ -e "\$streak_file" \]\] && image_probe; then\n  rm -f "\$streak_file"\nfi\n//'
  mutate "inspect без timeout" 's/\$\(timeout "\$INSPECT_S" "\$DOCKER" image inspect/\$("\$DOCKER" image inspect/'
  mutate "STOP завжди про відсутній образ" 's/    \*\) kind=docker_unavailable ;;/    *) kind=image_missing ;;/'
  # Невідкладні й пауза планового потоку (сценарії 22).
  mutate "тік бере задачу без queue.lock" 's/exec 6>"\$A8_LOGS_DIR\/queue.lock"\nflock 6\n/exec 6>"\$A8_LOGS_DIR\/queue.lock"\n/'
  mutate "тік бере планову, хоч з'явилась пауза" 's/  \{ \[\[ -e "\$A8_LOGS_DIR\/planned-paused" \]\] \|\| /  { false || /'
  mutate "тік бере планову, хоч з'явилась невідкладна" 's/ \|\| compgen -G "\$Q\/urgent\/\*\.json" >\/dev\/null; \}; then/ || false; }; then/'
  mutate "тік переносить задачі без queue.lock" 's/qmv\(\) \{ flock "\$A8_LOGS_DIR\/queue.lock" mv "\$@"; \}/qmv() { mv "\$@"; }/'
  mutate "urgent/ не береться" 's/  find "\$Q\/urgent" -maxdepth 1 -type f -name \x27\*\.json\x27 \| LC_ALL=C sort\n//'
  mutate "пауза планового потоку ігнорується" 's/  \[\[ -e "\$A8_LOGS_DIR\/planned-paused" \]\] && return 0\n//'
  mutate "невідкладна повертається в плановий потік" 's/mv "\$claimed" "\$home\/"/mv "\$claimed" "\$Q\/"/'
  if collating_locale >/dev/null; then
    mutate "порядок планового потоку — у локалі машини" 's/(  find "\$Q" -maxdepth 1 -type f -name \x27\*\.json\x27 \| )LC_ALL=C sort\n\}/$1sort\n}/'
  else
    say "⚠ мутація «порядок планового потоку — у локалі машини» НЕ ганялась: немає відповідної локалі"
  fi
  mutate "STOP людини затирається" 's/^      set -o noclobber\n//m'
  mutate "збій запису серії ігнорується" 's/    streak="\$A8_CONSECUTIVE_FAILURE_LIMIT"\n/    :\n/'
  mutate "STOP на першому ж збої" 's/streak >= A8_CONSECUTIVE_FAILURE_LIMIT/streak >= 1/'
  mutate "перевіряється не той образ" 's/image inspect "\$A8_CONTAINER_IMAGE"/image inspect node:22/'
  mutate "зупинка рахується як падіння" 's/stop_task\(\) \{ # stop_task[^\n]*\n/$&  "\$GUARD" record failed\n/'
  # Git на хості не виконує підкладене контейнером (#276, сценарії 23). Кожен
  # захист — окрема мутація: кожен закриває свій прийом.
  # Ключі hgit, які сценарії змушують спрацювати. Решту (pager, editor, askPass,
  # sshCommand, gitProxy, diff.external, credential.helper, protocol.ext,
  # alternateRefsCommand) тримає статична перевірка — check-ansible-a8.test.sh.
  mutate "hgit без core.hooksPath=/dev/null" 's/  -c core\.hooksPath=\/dev\/null\n//'
  # core.fsmonitor, --upload-pack, --receive-pack динамічно не вбити: сценарії,
  # що міняли config (23b/23c), тепер спиняє знімок+STOP до того, як git-тіку
  # дійде до цих ключів. Їх тримає статична перевірка (check-ansible-a8.test.sh:
  # per-key мутанти HGIT_SAFE + --upload-pack/--receive-pack). core.hooksPath
  # лишається динамічним — його вбиває 23a (evil-hooks config не чіпає, STOP не
  # спрацьовує, хук виконався б на worktree add/push).
  # Перевірки .git перед кожним git.
  mutate "hgit не бачить commondir" 's/  elif \[\[ -e "\$g\/commondir" \|\| -L "\$g\/commondir" \]\]; then\n[^\n]*\n//'
  mutate "hgit не бачить симлінк .git" 's/if \[\[ -L "\$g" \|\| ! -d "\$g" \]\]; then/if [[ ! -d "\$g" ]]; then/'
  mutate "hgit не бачить alternates" 's/for f in objects\/info\/alternates info\/grafts shallow;/for f in info\/grafts shallow;/'
  mutate "hgit не бачить grafts" 's/for f in objects\/info\/alternates info\/grafts shallow;/for f in objects\/info\/alternates shallow;/'
  mutate "hgit не бачить shallow" 's/for f in objects\/info\/alternates info\/grafts shallow;/for f in objects\/info\/alternates info\/grafts;/'
  mutate "hgit не бачить симлінк worktrees" 's/  elif \[\[ -L "\$g\/worktrees" \]\]; then\n[^\n]*\n//'
  mutate "hgit без core.commitGraph=false" 's/  -c core\.commitGraph=false\n//'
  mutate "знімок identity не звіряється" 's/  elif \[\[ -n "\$git_snapshot" && "\$\(git_identity\)" != "\$git_snapshot" \]\]; then\n[^\n]*\n//'
  mutate "знімок identity не робиться" 's/\nsnapshot_git\n/\n/'
  mutate "hgit без GIT_NO_REPLACE_OBJECTS" 's/  GIT_NO_REPLACE_OBJECTS=1 git "\$\{HGIT_SAFE/  git "\${HGIT_SAFE/'
  mutate "причину відмови hgit не видно в журналі" 's/  \[\[ -s "\$unsafe" \]\] && detail=[^\n]*\n//'
  # Повні імена посилань.
  mutate "worktree add від короткого origin/main" 's/hgit worktree add --quiet -b "\$branch" "\$wt" "\$base"/hgit worktree add --quiet -b "\$branch" "\$wt" origin\/main/'
  mutate "база від короткого origin/main" 's/base="\$\(hgit rev-parse --verify --quiet "refs\/remotes\/origin\/main\^\{commit\}"\)"/base="\$(hgit rev-parse --verify --quiet origin\/main)"/'
  # release_or_keep.
  mutate "release_or_keep: помилка rev-list як 0 комітів" 's/  if ! cnt="\$\(hgit rev-list --count "\$base\.\.refs\/heads\/\$branch" 2>>"\$log"\)"; then/  cnt="\$(hgit rev-list --count "\$base..refs\/heads\/\$branch" 2>>"\$log" || echo 0)"\n  if false; then/'
  mutate "release_or_keep рахує від origin/main" 's/rev-list --count "\$base\.\.refs\/heads\/\$branch"/rev-list --count "refs\/remotes\/origin\/main..refs\/heads\/\$branch"/'
  # Після контейнера git не працює в "$wt".
  mutate "push з worktree" 's/      hgit push --receive-pack=git-receive-pack origin "\$tip:refs\/heads\/\$branch"/      git -C "\$wt" push origin "\$tip:refs\/heads\/\$branch"/'
  mutate "diff backstop'а з worktree" 's/changed="\$\(hgit diff -z/changed="\$(git --no-replace-objects -C "\$wt" diff -z/'
  wait
  for i in $(seq 1 "$n"); do
    name="$(cat "$MUTDIR/$i.name")"
    case "$(cat "$MUTDIR/$i.res" 2>/dev/null)" in
      killed) ok "мутація «$name» убита" ;;
      survived) bad "мутація «$name» ВИЖИЛА — набір зелений на зламаному демоні" ;;
      stale) bad "мутація «$name» нічого не змінила — вираз застарів" ;;
      syntax) bad "мутація «$name» ламає синтаксис — некоректна, а не вбита" ;;
      *) bad "мутація «$name» — результату немає" ;;
    esac
  done
fi

if [[ "$fail" -eq 1 ]]; then
  echo "FAIL"
  exit 1
fi
say "Усі тести пройдено."
exit 0
