#!/usr/bin/env bash
# check-ansible-a8.test.sh — прогін інваріантів ролі A8 на синтетичних деревах.
#
# Кожен тест будує мінімальне дерево `infra/ansible/…` у тимчасовій теці й
# перевіряє, що скрипт розрізняє здоровий і зламаний варіант. Мутаційна
# частина в кінці: ламаємо чинну роль у репозиторії (копією, не на місці) —
# скрипт МУСИТЬ почервоніти на кожній із трьох вад. Тест, що лишається
# зеленим на зламаному вході, доводить лише власну присутність.
#
# Запуск: tools/scripts/check-ansible-a8.test.sh
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-ansible-a8.sh"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
tmproot="$(mktemp -d)"
trap 'rm -rf "$tmproot"' EXIT

# Будує дерево: $1 — тека, $2 — вміст a8.yml, $3 — вміст tasks/main.yml.
make_tree() {
  local dir="$1"
  mkdir -p "$dir/infra/ansible/roles/a8/tasks" "$dir/infra/ansible/roles/a8/files" "$dir/infra/docker"
  printf '%s\n' "$2" >"$dir/infra/ansible/a8.yml"
  printf '%s\n' "$3" >"$dir/infra/ansible/roles/a8/tasks/main.yml"
  # Мінімальна узгоджена пара для інваріанта 9: без Dockerfile'ів він
  # червоніє (fail closed), а ці дерева перевіряють інші інваріанти.
  printf '%s\n' 'FROM python:3.12-slim-bookworm AS runner' \
    'RUN apt-get update && apt-get install -y --no-install-recommends \' \
    '    libgl1 \' '    && rm -rf /var/lib/apt/lists/*' >"$dir/infra/docker/cad-worker.Dockerfile"
  printf '%s\n' 'FROM node:22' 'RUN apt-get update \' \
    ' && apt-get install -y --no-install-recommends libgl1 \' \
    ' && rm -rf /var/lib/apt/lists/*' >"$dir/infra/ansible/roles/a8/files/agent.Dockerfile"
  # Мінімальна пара для інваріанта 10: збірка з мережею хоста й обгортка без
  # --network. Без них він червоніє (fail closed), як і інваріант 9.
  mkdir -p "$dir/infra/ansible/roles/a8/templates" "$dir/infra/ansible/roles/a8/defaults"
  printf '%s\n' "$BUILD_OK" >"$dir/infra/ansible/roles/a8/tasks/image.yml"
  printf '%s\n' "$RUNNER_TASK_OK" >"$dir/infra/ansible/roles/a8/tasks/runner.yml"
  printf '%s\n' "$RUNNER_OK" >"$dir/infra/ansible/roles/a8/templates/a8-run-agent.sh.j2"
  printf '%s\n' 'a8_egress_bridge: docker0' 'a8_egress_probe_host: deb.debian.org' 'a8_egress_domains:' \
    '  - github.com # git' >"$dir/infra/ansible/roles/a8/defaults/main.yml"
  # Мінімальний живий вимір фільтра для інваріанта 13: без нього він червоніє.
  printf '%s\n' "$VERIFY_OK" >"$dir/infra/ansible/roles/a8/tasks/verify.yml"
  printf '%s\n' "$DOCKER_TASK_OK" >"$dir/infra/ansible/roles/a8/tasks/docker.yml"
  # Мінімальна пара для інваріанта 11: крок CI з extras і `uv sync` агента.
  mkdir -p "$dir/.github/workflows"
  printf '%s\n' "$CI_OK" >"$dir/.github/workflows/ci.yml"
  printf '%s\n' "$DEPS_OK" >"$dir/infra/ansible/roles/a8/tasks/deps.yml"
}

CI_OK='jobs:
  python:
    steps:
      - name: Install deps
        run: uv sync --extra dev
      - name: Test
        run: uv run pytest'

VERIFY_OK='---
- name: V20a — agent probe
  ansible.builtin.command:
    argv:
      - /usr/local/bin/a8-run-agent
      - /home/agent/hart
      - bash
      - -c
      - &a8_egress_probe |
        echo @@PROBE_START@@
        getent ahostsv4 {{ a8_egress_probe_host }} && echo @@DNS4_OK@@ @@IP=1@@ || echo @@DNS4_FAIL@@
        echo @@EGRESS_REACHED@@ @@EGRESS_BLOCKED@@
        echo @@NO_GLOBAL_IPV6@@
  register: a8_v_egress_agent

- name: V20b — control
  ansible.builtin.command:
    argv:
      - docker
      - run
      - --network
      - host
      - hart-agent:test
      - bash
      - -c
      - *a8_egress_probe
  register: a8_v_egress_ctl

- name: V20c — ipset
  ansible.builtin.command:
    argv: [ipset, test, a8_egress, 1.1.1.1]
  register: a8_v_egress_inset'

DOCKER_TASK_OK='---
- name: Configure docker daemon options
  ansible.builtin.template:
    src: daemon.json.j2
    dest: /etc/docker/daemon.json'

DEPS_OK='---
- name: Install worker deps
  ansible.builtin.command:
    argv:
      - bash
      - -c
      - cd workers/cad && uv sync --extra dev'

# Дерево для інваріанта 11: здорова роль, у якій замінено задачу залежностей
# ($2) і/або ci.yml ($3). Порожній аргумент — лишити здоровим.
make_uv_tree() {
  make_tree "$1" "$PLAY_OK" "$TASKS_OK"
  [[ -n "${2:-}" ]] && printf '%s\n' "$2" >"$1/infra/ansible/roles/a8/tasks/deps.yml"
  [[ -n "${3:-}" ]] && printf '%s\n' "$3" >"$1/.github/workflows/ci.yml"
  return 0
}
deps_with() { # deps_with <команда uv> — задача залежностей із цією командою
  printf '%s\n' '---' '- name: Install worker deps' '  ansible.builtin.command:' '    argv:' \
    '      - bash' '      - -c' "      - cd workers/cad && $1"
}

BUILD_OK='---
- name: Build the agent image
  ansible.builtin.command: >-
    docker build
    --network host
    -t hart-agent:test /etc/a8/image'

RUNNER_TASK_OK='---
- name: Install agent container runner
  ansible.builtin.template:
    src: a8-run-agent.sh.j2
    dest: /usr/local/bin/a8-run-agent'

RUNNER_OK='#!/usr/bin/env bash
/usr/local/bin/a8-guard check-run >&2
exec docker run --rm \
  -w "$1" \
  hart-agent:test "$@"'

# Дерево для інваріанта 10: здорова роль, у якій замінено збірку ($2), обгортку
# ($3) і/або daemon.json.j2 ($4). Порожній аргумент — лишити здорову.
make_net_tree() {
  make_tree "$1" "$PLAY_OK" "$TASKS_OK"
  [[ -n "${2:-}" ]] && printf '%s\n' "$2" >"$1/infra/ansible/roles/a8/tasks/image.yml"
  [[ -n "${3:-}" ]] && printf '%s\n' "$3" >"$1/infra/ansible/roles/a8/templates/a8-run-agent.sh.j2"
  [[ -n "${4:-}" ]] && printf '%s\n' "$4" >"$1/infra/ansible/roles/a8/templates/daemon.json.j2"
  return 0
}

# $4 (необов'язковий) — підрядок очікуваного порушення. З ним тест вимагає, щоб
# порушення було рівно одне і саме це: код 1 з будь-якої іншої причини (синтаксис,
# сусідній інваріант) інакше зараховувався б як успіх (знайшов рецензент agy,
# Gemini 3.8 Flash, PR #147).
assert_exit() {
  local name="$1" expected="$2" dir="$3" want="${4:-}"
  local actual=0
  ROOT="$dir" "$SCRIPT" >"$tmproot/out" 2>&1 || actual=$?
  if [[ -n "$want" ]] && ! { grep -qF -- "порушено (1):" "$tmproot/out" && grep -qF -- "$want" "$tmproot/out"; }; then
    echo "✗ $name — очікував рівно одне порушення «$want»"
    sed 's/^/    /' "$tmproot/out"
    fail=1
  elif [[ "$actual" -eq "$expected" ]]; then
    echo "✓ $name"
  else
    echo "✗ $name — очікував exit $expected, отримав $actual"
    sed 's/^/    /' "$tmproot/out"
    fail=1
  fi
}

PLAY_OK='---
- name: p
  hosts: a8
  vars:
    ansible_shell_executable: /bin/bash
  roles:
    - role: a8'

PLAY_NO_BASH='---
- name: p
  hosts: a8
  roles:
    - role: a8'

TASKS_OK='---
- name: include verify
  ansible.builtin.include_tasks:
    file: verify.yml
    apply:
      tags: [verify]
  tags: [verify, never]

- name: probe
  ansible.builtin.shell: |
    set -o pipefail
    echo hi | cat

- name: container
  ansible.builtin.command:
    argv:
      - /usr/local/bin/a8-run-agent
      - /home/agent/hart
      - bash
      - -c
      - printenv HOME'

# Тест 1 — здорове дерево → 0.
make_tree "$tmproot/ok" "$PLAY_OK" "$TASKS_OK"
assert_exit "здорова роль → 0" 0 "$tmproot/ok"

# Тест 2 — include_tasks у рядковій формі (вада 1, реальна: ok=2 у verify).
make_tree "$tmproot/inc" "$PLAY_OK" '---
- name: include verify
  ansible.builtin.include_tasks: verify.yml
  tags: [verify, never]'
assert_exit "include_tasks без apply → 1" 1 "$tmproot/inc"

# Тест 3 — pipefail без bash (вада 2, реальна: Illegal option -o pipefail).
make_tree "$tmproot/pf" "$PLAY_NO_BASH" '---
- name: probe
  ansible.builtin.shell: |
    set -o pipefail
    echo hi | cat'
assert_exit "pipefail без bash → 1" 1 "$tmproot/pf"

# Тест 4 — той самий pipefail, але задача несе власний executable → 0.
# Інваріант не має диктувати стиль: обидва способи задати bash допустимі.
make_tree "$tmproot/pfx" "$PLAY_NO_BASH" '---
- name: probe
  ansible.builtin.shell: |
    set -o pipefail
    echo hi | cat
  args:
    executable: /bin/bash'
assert_exit "pipefail із власним executable → 0" 0 "$tmproot/pfx"

# Тест 5 — виклик контейнера рядковою формою (вада 3, реальна: HOME=/home/agent).
make_tree "$tmproot/argv" "$PLAY_OK" '---
- name: container
  ansible.builtin.command: >-
    /usr/local/bin/a8-run-agent /home/agent/hart
    bash -c "echo $HOME"'
assert_exit "a8-run-agent без argv → 1" 1 "$tmproot/argv"

# Тест 6-bis — shell-змінна в зонді до контейнера (вада 4, реальна: $HOME
# у V6a давав /home/agent замість /home/agent/container-home).
make_tree "$tmproot/dollar" "$PLAY_OK" '---
- name: probe
  ansible.builtin.command:
    argv:
      - /usr/local/bin/a8-run-agent
      - /home/agent/hart
      - bash
      - -c
      - echo "HOME=$HOME"
  register: probe_out'
assert_exit "shell-змінна в зонді → 1" 1 "$tmproot/dollar"

# Тест 6-ter — той самий зонд без змінної: значення читається printenv,
# шлях підставляє Jinja. Має проходити.
make_tree "$tmproot/nodollar" "$PLAY_OK" '---
- name: probe
  ansible.builtin.command:
    argv:
      - /usr/local/bin/a8-run-agent
      - /home/agent/hart
      - bash
      - -c
      - |
        printenv HOME
        touch "/home/agent/container-home/.a8probe"
  register: probe_out'
assert_exit "зонд без змінних → 0" 0 "$tmproot/nodollar"

# Тест 6-quater — `$` ПІСЛЯ register: належить іншій задачі, не зонду.
make_tree "$tmproot/after" "$PLAY_OK" '---
- name: probe
  ansible.builtin.command:
    argv:
      - /usr/local/bin/a8-run-agent
      - /home/agent/hart
      - printenv
      - HOME
  register: probe_out

- name: host-side shell, змінні тут доречні
  ansible.builtin.shell: |
    tmp=$(mktemp -d)
    rm -rf "$tmp"'
assert_exit "змінна поза зондом → 0" 0 "$tmproot/after"

# Тест 6-quinquies — login-shell у зонді (вада 5, реальна: V10 падала, бо
# `bash -lc` перезадав PATH із /etc/profile і викинув node_modules/.bin).
make_tree "$tmproot/login" "$PLAY_OK" '---
- name: probe
  ansible.builtin.command:
    argv:
      - /usr/local/bin/a8-run-agent
      - /home/agent/hart
      - bash
      - -lc
      - command -v lefthook
  register: probe_out'
assert_exit "login-shell у зонді → 1" 1 "$tmproot/login"

# Той самий зонд без -l має проходити: перевіряємо саме прапорець, не bash.
make_tree "$tmproot/nologin" "$PLAY_OK" '---
- name: probe
  ansible.builtin.command:
    argv:
      - /usr/local/bin/a8-run-agent
      - /home/agent/hart
      - bash
      - -c
      - command -v lefthook
  register: probe_out'
assert_exit "той самий зонд без -l → 0" 0 "$tmproot/nologin"

# Тест 6-sexies — цитата команди в тексті помилки не є викликом.
make_tree "$tmproot/prose" "$PLAY_OK" '---
- name: assert something
  ansible.builtin.assert:
    that:
      - true
    fail_msg: >-
      Не знайдено. Перевір PATH самого контейнера:
      `a8-run-agent /home/agent/hart bash -c printenv | grep ^PATH=`.'
assert_exit "цитата команди в fail_msg → 0" 0 "$tmproot/prose"

# Тест 6 — згадка a8-run-agent у коментарі не є викликом.
make_tree "$tmproot/cmt" "$PLAY_OK" '---
- name: container
  # Запускаємо через a8-run-agent — єдине місце, де описано docker run.
  ansible.builtin.command:
    argv:
      - /usr/local/bin/a8-run-agent
      - /home/agent/hart'
assert_exit "a8-run-agent у коментарі → 0" 0 "$tmproot/cmt"

# ─── Інваріант 10: мережа збірки й мережа агента ───────────────────────────
# Збірка: реальна вада 2026-09-28 — без --network host примус egress різав
# apt-get у RUN-кроці, образу не ставало.
make_net_tree "$tmproot/n1" '---
- name: Build the agent image
  ansible.builtin.command: >-
    docker build
    -t hart-agent:test /etc/a8/image'
assert_exit "10: docker build без --network → 1" 1 "$tmproot/n1" "docker build без --network host"

make_net_tree "$tmproot/n2" '---
- name: Build the agent image
  ansible.builtin.command: docker build --network=host -t hart-agent:test /etc/a8/image'
assert_exit "10: --network=host одним словом → 0" 0 "$tmproot/n2"

make_net_tree "$tmproot/n3" '---
- name: Build the agent image
  ansible.builtin.command:
    argv:
      - docker
      - build
      - --network
      - host
      - -t
      - hart-agent:test
      - /etc/a8/image'
assert_exit "10: argv-форма з --network host → 0" 0 "$tmproot/n3"

make_net_tree "$tmproot/n4" '---
- name: Build the agent image
  ansible.builtin.command: >-
    docker build
    --network bridge
    -t hart-agent:test /etc/a8/image'
assert_exit "10: збірка з --network bridge → 1" 1 "$tmproot/n4" "docker build без --network host"

# Коментар і назва задачі — не прапорець.
make_net_tree "$tmproot/n5" '---
- name: Build the agent image with --network host
  # --network host тут потрібен, див. інваріант 10
  ansible.builtin.command: >-
    docker build
    -t hart-agent:test /etc/a8/image'
assert_exit "10: --network host лише в назві й коментарі → 1" 1 "$tmproot/n5" "docker build без --network host"

# Прапорець у сусідній команді того самого shell — не прапорець збірки.
make_net_tree "$tmproot/n6" '---
- name: Build the agent image
  ansible.builtin.shell: >-
    docker build -t hart-agent:test /etc/a8/image
    && docker image ls --network host'
assert_exit "10: --network host після && в іншій команді → 1" 1 "$tmproot/n6" "docker build без --network host"

make_net_tree "$tmproot/n7" '---
- name: Build the agent image
  ansible.builtin.command: docker buildx build -t hart-agent:test /etc/a8/image'
assert_exit "10: docker buildx build без --network → 1" 1 "$tmproot/n7" "docker build без --network host"

# Збірки немає зовсім — перевіряти нічого, і це червоне, а не зелене.
make_net_tree "$tmproot/n8" '---
- name: Nothing to build
  ansible.builtin.debug:
    msg: ok'
assert_exit "10: жодного docker build у задачах → 1" 1 "$tmproot/n8" "немає жодного 'docker build'"

# Обгортка: будь-яка мережа, не лише host. Мережа з `docker network create`
# має власний міст br-…, а правила примусу стоять на -i docker0.
make_net_tree "$tmproot/n9" '' '#!/usr/bin/env bash
exec docker run --rm \
  --network host \
  hart-agent:test "$@"'
assert_exit "10: обгортка з --network host → 1" 1 "$tmproot/n9" "шаблон чи файл ролі задає мережу контейнера"

make_net_tree "$tmproot/n10" '' '#!/usr/bin/env bash
exec docker run --rm --net=a8net hart-agent:test "$@"'
assert_exit "10: обгортка з --net=a8net → 1" 1 "$tmproot/n10" "шаблон чи файл ролі задає мережу контейнера"

make_net_tree "$tmproot/n11" '' '#!/usr/bin/env bash
OPT_ARGS=()
OPT_ARGS+=(--network a8net)
exec docker run --rm "${OPT_ARGS[@]}" hart-agent:test "$@"'
assert_exit "10: --network через масив прапорців → 1" 1 "$tmproot/n11" "шаблон чи файл ролі задає мережу контейнера"

# Пояснення в обох видах коментарів — не порушення; схожий прапорець — теж.
make_net_tree "$tmproot/n12" '' '#!/usr/bin/env bash
# --network тут НЕ ставимо: агент мусить іти через docker0
exec docker run --rm \
  `# без --network host — інакше агент поза egress-фільтром` \
  -e CURL_OPTS=--netrc \
  hart-agent:test "$@"'
assert_exit "10: --network у коментарях, --netrc у значенні → 0" 0 "$tmproot/n12"

make_net_tree "$tmproot/n13"
rm "$tmproot/n13/infra/ansible/roles/a8/templates/a8-run-agent.sh.j2"
assert_exit "10: обгортки немає → 1" 1 "$tmproot/n13" "немає обгортки"

make_net_tree "$tmproot/n14" '' '#!/usr/bin/env bash
# exec docker run — колись тут був
exec podman run --rm hart-agent:test "$@"'
assert_exit "10: в обгортці немає docker run → 1" 1 "$tmproot/n14" "не знайдено 'docker run'"

# Інший шаблон ролі (напр. тік) теж не задає мережу контейнера.
make_net_tree "$tmproot/n15"
printf '%s\n' '#!/usr/bin/env bash' 'docker run --rm --network host alpine true' \
  >"$tmproot/n15/infra/ansible/roles/a8/templates/a8-tick.sh.j2"
assert_exit "10: --network в іншому шаблоні ролі → 1" 1 "$tmproot/n15" "шаблон чи файл ролі задає мережу контейнера"

# Знахідки рецензії PR #147 (agy, Gemini 3.8 Flash) і звірки оркестратора.
# Повторений прапорець бере останнє значення.
make_net_tree "$tmproot/n16" '---
- name: Build the agent image
  ansible.builtin.command: >-
    docker build
    --network host
    --network bridge
    -t hart-agent:test /etc/a8/image'
assert_exit "10: --network host, потім --network bridge → 1" 1 "$tmproot/n16" "docker build без --network host"

make_net_tree "$tmproot/n17" '---
- name: Build the agent image
  ansible.builtin.command: >-
    docker build
    --network bridge
    --network host
    -t hart-agent:test /etc/a8/image'
assert_exit "10: останнім стоїть --network host → 0" 0 "$tmproot/n17"

# Задачі в підтеці tasks/ теж задачі ролі.
make_net_tree "$tmproot/n18"
mkdir -p "$tmproot/n18/infra/ansible/roles/a8/tasks/image"
printf '%s\n' '---' '- name: b' '  ansible.builtin.command: docker build -t x /y' \
  >"$tmproot/n18/infra/ansible/roles/a8/tasks/image/build.yml"
assert_exit "10: збірка без мережі в tasks/image/ → 1" 1 "$tmproot/n18" "docker build без --network host"

# `docker compose build` прапорця --network не має — описувати заново.
make_net_tree "$tmproot/n19" '---
- name: Build the agent image
  ansible.builtin.command: docker compose -f build.yml build'
assert_exit "10: docker compose build → 1" 1 "$tmproot/n19" "docker build без --network host"

# `;` без пробілу — частина значення, а не межа команди.
make_net_tree "$tmproot/n20" '---
- name: Build the agent image
  ansible.builtin.command: >-
    docker build
    --label d=a;b
    --network host
    -t hart-agent:test /etc/a8/image'
assert_exit "10: ; усередині значення перед --network host → 0" 0 "$tmproot/n20"

# Прапорець у значенні іншого прапорця — не прапорець збірки.
make_net_tree "$tmproot/n21" '---
- name: Build the agent image
  ansible.builtin.command: >-
    docker build
    --build-arg DUMMY=--network host
    -t hart-agent:test /etc/a8/image'
assert_exit "10: --network host як значення --build-arg → 1" 1 "$tmproot/n21" "docker build без --network host"

# bash склеює лапки й \ в одне слово.
make_net_tree "$tmproot/n22" '' '#!/usr/bin/env bash
exec docker run --rm --net""work=host hart-agent:test "$@"'
assert_exit "10: обгортка з --net\"\"work=host → 1" 1 "$tmproot/n22" "шаблон чи файл ролі задає мережу контейнера"

make_net_tree "$tmproot/n23" '' '#!/usr/bin/env bash
exec docker run --rm --net\work=host hart-agent:test "$@"'
assert_exit "10: обгортка з --net\\work=host → 1" 1 "$tmproot/n23" "шаблон чи файл ролі задає мережу контейнера"

# Jinja-коментар — пояснення, до docker не доходить.
make_net_tree "$tmproot/n24" '' '#!/usr/bin/env bash
{# без --network: агент мусить іти через docker0 #}
exec docker run --rm hart-agent:test "$@"'
assert_exit "10: --network у Jinja-коментарі → 0" 0 "$tmproot/n24"

# ` #` у лапках — не коментар; прапорець після нього діє.
make_net_tree "$tmproot/n25" '' '#!/usr/bin/env bash
exec docker run --rm \
  --label " #" --network host \
  hart-agent:test "$@"'
assert_exit "10: --network після \" #\" у лапках → 1" 1 "$tmproot/n25" "шаблон чи файл ролі задає мережу контейнера"

# Міст фільтра й міст docker.
DAEMON_BR0='{
  "bridge": "br0",
  "live-restore": true
}'
make_net_tree "$tmproot/n26" '' '' "$DAEMON_BR0"
assert_exit "10: daemon.json кладе контейнери на br0, фільтр на docker0 → 1" 1 "$tmproot/n26" "міст egress-фільтра"

make_net_tree "$tmproot/n27" '' '' "$DAEMON_BR0"
sed -i 's/^a8_egress_bridge: docker0$/a8_egress_bridge: br0/' "$tmproot/n27/infra/ansible/roles/a8/defaults/main.yml"
assert_exit "10: daemon.json і фільтр — обидва br0 → 0" 0 "$tmproot/n27"

make_net_tree "$tmproot/n28"
mkdir -p "$tmproot/n28/infra/ansible/group_vars"
printf '%s\n' 'a8_egress_bridge: br0' >"$tmproot/n28/infra/ansible/group_vars/a8.yml"
assert_exit "10: group_vars переносить фільтр з docker0 → 1" 1 "$tmproot/n28" "міст egress-фільтра"

make_net_tree "$tmproot/n29"
sed -i '/^a8_egress_bridge:/d' "$tmproot/n29/infra/ansible/roles/a8/defaults/main.yml"
assert_exit "10: a8_egress_bridge ніде не задано → 1" 1 "$tmproot/n29" "a8_egress_bridge не знайдено"

# Обгортку ставить не шаблон — перевірка шаблону нічого б не доводила.
make_net_tree "$tmproot/n30"
printf '%s\n' '---' '- name: Install agent container runner' '  ansible.builtin.copy:' \
  '    src: a8-run-agent.sh' '    dest: /usr/local/bin/a8-run-agent' \
  >"$tmproot/n30/infra/ansible/roles/a8/tasks/runner.yml"
assert_exit "10: обгортку ставить copy з files/ → 1" 1 "$tmproot/n30" "обгортку ставить не шаблон"

make_net_tree "$tmproot/n31"
rm "$tmproot/n31/infra/ansible/roles/a8/tasks/runner.yml"
assert_exit "10: немає задачі, що ставить обгортку → 1" 1 "$tmproot/n31" "не видно, звідки береться обгортка"

# Контрприклади окремої сесії Claude (PR #147, ліміт Opus в agy вичерпано).
# Блок `|`: кожен рядок — окрема команда; перевіряється кожна збірка, не остання.
make_net_tree "$tmproot/n32"
printf '%s\n' '---' '- name: Build all images' '  ansible.builtin.shell: |' \
  '    docker build -t pre-img:latest /etc/a8/pre' \
  '    docker build --network host -t hart-agent:test /etc/a8/image' \
  >"$tmproot/n32/infra/ansible/roles/a8/tasks/extra.yml"
assert_exit "10: дві збірки в shell: |, перша без мережі → 1" 1 "$tmproot/n32" "docker build без --network host"

# Той самий блок, обидві з мережею хоста — зелено.
make_net_tree "$tmproot/n33"
printf '%s\n' '---' '- name: Build all images' '  ansible.builtin.shell: |' \
  '    docker build --network host -t pre-img:latest /etc/a8/pre' \
  '    docker build --network host -t hart-agent:test /etc/a8/image' \
  >"$tmproot/n33/infra/ansible/roles/a8/tasks/extra.yml"
assert_exit "10: дві збірки в shell: |, обидві з мережею хоста → 0" 0 "$tmproot/n33"

# Шаблони в підтеках і файли ролі теж ідуть на хост.
make_net_tree "$tmproot/n34"
mkdir -p "$tmproot/n34/infra/ansible/roles/a8/templates/helpers"
printf '%s\n' '#!/usr/bin/env bash' 'exec docker run --rm --network host alpine true' \
  >"$tmproot/n34/infra/ansible/roles/a8/templates/helpers/diag.sh.j2"
assert_exit "10: --network у templates/helpers/ → 1" 1 "$tmproot/n34" "шаблон чи файл ролі задає мережу контейнера"

make_net_tree "$tmproot/n35"
printf '%s\n' '#!/usr/bin/env bash' 'exec docker run --rm --net=host alpine true' \
  >"$tmproot/n35/infra/ansible/roles/a8/files/diag.sh"
assert_exit "10: --net=host у files/ → 1" 1 "$tmproot/n35" "шаблон чи файл ролі задає мережу контейнера"

# Лапки YAML навколо значення — те саме значення.
make_net_tree "$tmproot/n36"
sed -i "s/^a8_egress_bridge: docker0$/a8_egress_bridge: 'docker0'/" "$tmproot/n36/infra/ansible/roles/a8/defaults/main.yml"
assert_exit "10: a8_egress_bridge: 'docker0' в одинарних лапках → 0" 0 "$tmproot/n36"

# host_vars перекриває defaults і group_vars.
make_net_tree "$tmproot/n37"
mkdir -p "$tmproot/n37/infra/ansible/host_vars"
printf '%s\n' 'a8_egress_bridge: br-custom' >"$tmproot/n37/infra/ansible/host_vars/a8.yml"
assert_exit "10: host_vars переносить фільтр на br-custom → 1" 1 "$tmproot/n37" "міст egress-фільтра (br-custom)"

# ─── Інваріант 11: uv sync агента = uv sync CI ──────────────────────────────
# Реальна вада 2026-09-29: голий `uv sync` у тіку й V18c — у контейнері немає
# pytest, V18e rc=2 «Failed to spawn: `pytest`».
make_uv_tree "$tmproot/u1" "$(deps_with 'uv sync')"
assert_exit "11: голий uv sync → 1" 1 "$tmproot/u1" "uv sync без '--extra dev'"

make_uv_tree "$tmproot/u2" "$(deps_with 'uv sync --quiet')"
assert_exit "11: uv sync --quiet без extra → 1" 1 "$tmproot/u2" "uv sync без '--extra dev'"

make_uv_tree "$tmproot/u3" "$(deps_with 'uv sync --extra=dev --quiet')"
assert_exit "11: --extra=dev одним словом → 0" 0 "$tmproot/u3"

make_uv_tree "$tmproot/u4" "$(deps_with 'uv sync --all-extras')"
assert_exit "11: --all-extras покриває dev → 0" 0 "$tmproot/u4"

make_uv_tree "$tmproot/u5" "$(deps_with 'uv sync --extra development')"
assert_exit "11: --extra development — не dev → 1" 1 "$tmproot/u5" "uv sync без '--extra dev'"

# Еталон — CI: нове extra в CI без правки ролі червонить.
make_uv_tree "$tmproot/u6" '' 'jobs:
  python:
    steps:
      - run: uv sync --extra dev --extra docs'
assert_exit "11: у CI нове extra docs, в агента немає → 1" 1 "$tmproot/u6" "uv sync без '--extra docs'"

make_uv_tree "$tmproot/u7" '' 'jobs:
  python:
    steps:
      - run: pip install -e .'
assert_exit "11: у CI немає команди uv sync → 1" 1 "$tmproot/u7" "немає команди 'uv sync"

make_uv_tree "$tmproot/u8" '---
- name: Nothing to install
  ansible.builtin.debug:
    msg: ok'
assert_exit "11: жодного uv sync у ролі → 1" 1 "$tmproot/u8" "не знайдено жодного 'uv sync'"

# Проза й коментарі командою не є.
make_uv_tree "$tmproot/u9"
printf '%s\n' '---' '- name: V18c — uv sync, then the registry test' '  # `uv sync` без dev колись падав' \
  '  ansible.builtin.assert:' '    that: [true]' '    fail_msg: "на 3.14 uv sync падає; uv sync: пройшов"' \
  >"$tmproot/u9/infra/ansible/roles/a8/tasks/prose.yml"
assert_exit "11: uv sync у назві, коментарі й тексті повідомлення → 0" 0 "$tmproot/u9"

# Обгортка з `` `# … uv sync …` `` посеред команди — коментар.
make_uv_tree "$tmproot/u10"
printf '%s\n' '#!/usr/bin/env bash' 'exec docker run --rm \' '  `# uv sync на 3.14 падає` \' '  hart-agent:test "$@"' \
  >"$tmproot/u10/infra/ansible/roles/a8/templates/a8-run-agent.sh.j2"
assert_exit "11: uv sync у backtick-коментарі обгортки → 0" 0 "$tmproot/u10"

# autorun.sh — той самий крок для локального автономного прогону.
make_uv_tree "$tmproot/u11"
mkdir -p "$tmproot/u11/tools/scripts"
printf '%s\n' '#!/usr/bin/env bash' '(cd "$WT_DIR/workers/cad" && uv sync)' >"$tmproot/u11/tools/scripts/autorun.sh"
assert_exit "11: голий uv sync в autorun.sh → 1" 1 "$tmproot/u11" "autorun.sh"

# Знахідки рецензії PR #148 (agy, Gemini 3.8 Flash).
make_uv_tree "$tmproot/u12" "$(deps_with 'uv sync --extra dev --no-dev')"
assert_exit "11: --extra dev разом із --no-dev → 1" 1 "$tmproot/u12" "звужує набір прапорцем '--no-dev'"

make_uv_tree "$tmproot/u13" "$(deps_with 'uv sync -q # --extra dev')"
assert_exit "11: --extra dev лише в коментарі в кінці рядка → 1" 1 "$tmproot/u13" "uv sync без '--extra dev'"

make_uv_tree "$tmproot/u14" '' 'jobs:
  python:
    steps:
      - run: uv sync --extra dev --group integration'
assert_exit "11: у CI --group integration, в агента немає → 1" 1 "$tmproot/u14" "uv sync без '--group integration'"

# Еталон у CI через продовження `\`: вимога не губиться.
CI_CONT='jobs:
  python:
    steps:
      - run: uv sync \
          --extra dev'
make_uv_tree "$tmproot/u15" "$(deps_with 'uv sync')" "$CI_CONT"
assert_exit "11: CI з \\, голий uv sync агента → 1" 1 "$tmproot/u15" "uv sync без '--extra dev'"
make_uv_tree "$tmproot/u16" '' "$CI_CONT"
assert_exit "11: CI з \\, агент з --extra dev → 0" 0 "$tmproot/u16"

# handlers/ — теж файли ролі.
make_uv_tree "$tmproot/u17"
mkdir -p "$tmproot/u17/infra/ansible/roles/a8/handlers"
printf '%s\n' '---' '- name: deps' '  ansible.builtin.command: bash -c "cd w && uv sync"' \
  >"$tmproot/u17/infra/ansible/roles/a8/handlers/main.yml"
assert_exit "11: голий uv sync у handlers/ → 1" 1 "$tmproot/u17" "handlers/main.yml"

make_uv_tree "$tmproot/u18" "$(deps_with 'uv sync --extra "dev"')"
assert_exit "11: --extra \"dev\" у лапках → 0" 0 "$tmproot/u18"

make_uv_tree "$tmproot/u19" '' 'jobs:
  python:
    steps:
      - run: |
          cd workers/cad
          uv sync --extra dev'
assert_exit "11: CI — блок run: | → 0" 0 "$tmproot/u19"

make_uv_tree "$tmproot/u20" '' 'jobs:
  python:
    steps:
      - run: uv --directory workers/cad sync --extra dev'
assert_exit "11: CI — uv --directory X sync → 0" 0 "$tmproot/u20"

make_uv_tree "$tmproot/u21" "$(deps_with 'uv sync --extra dev && echo "uv sync ok"')"
assert_exit "11: друга згадка uv sync у рядку — проза → 0" 0 "$tmproot/u21"

make_uv_tree "$tmproot/u22" "$(deps_with 'uv sync --extra dev && uv sync')"
assert_exit "11: друга команда в рядку — голий uv sync → 1" 1 "$tmproot/u22" "uv sync без '--extra dev'"

# Контрприклади окремої сесії Claude (PR #148, ліміт Opus в agy вичерпано).
# Продовження `\` у шаблоні ролі склеюється, як у CI.
make_uv_tree "$tmproot/u23"
printf '%s\n' '#!/usr/bin/env bash' "\"\$RUNNER\" \"\$wt\" bash -c 'cd workers/cad && uv sync \\" \
  "  --quiet' >>\"\$log\" 2>&1" >"$tmproot/u23/infra/ansible/roles/a8/templates/tick.sh.j2"
assert_exit "11: uv sync \\ + --quiet на наступному рядку → 1" 1 "$tmproot/u23" "tick.sh.j2"

make_uv_tree "$tmproot/u24"
printf '%s\n' '#!/usr/bin/env bash' "\"\$RUNNER\" \"\$wt\" bash -c 'cd workers/cad && uv sync \\" \
  "  --extra dev' >>\"\$log\" 2>&1" >"$tmproot/u24/infra/ansible/roles/a8/templates/tick.sh.j2"
assert_exit "11: uv sync \\ + --extra dev на наступному рядку → 0" 0 "$tmproot/u24"

# Еталон — лише job python: extra іншої job агентові не потрібне.
make_uv_tree "$tmproot/u25" '' 'jobs:
  python:
    steps:
      - run: uv sync --extra dev
  docs:
    steps:
      - run: uv sync --extra docs'
assert_exit "11: інша job ставить --extra docs → 0" 0 "$tmproot/u25"

make_uv_tree "$tmproot/u26" '' 'jobs:
  pyworker:
    steps:
      - run: uv sync --extra dev'
assert_exit "11: job python перейменовано → 1" 1 "$tmproot/u26" "у job 'python'"

# Коментарі в кінці рядка: Jinja і YAML — не команди.
make_uv_tree "$tmproot/u27"
printf '%s\n' '#!/usr/bin/env bash' '{# old: uv sync --no-dev #}' 'true' \
  >"$tmproot/u27/infra/ansible/roles/a8/templates/note.sh.j2"
assert_exit "11: uv sync --no-dev у Jinja-коментарі → 0" 0 "$tmproot/u27"

make_uv_tree "$tmproot/u28"
printf '%s\n' '---' '- name: x' '  ansible.builtin.debug:' '    msg: ok  # old approach: uv sync --quiet' \
  >"$tmproot/u28/infra/ansible/roles/a8/tasks/note.yml"
assert_exit "11: uv sync --quiet у YAML-коментарі в кінці рядка → 0" 0 "$tmproot/u28"

# ` #` у лапках — не коментар: голий uv sync за ним видно.
make_uv_tree "$tmproot/u29"
printf '%s\n' '#!/usr/bin/env bash' 'echo " #"; uv sync' >"$tmproot/u29/infra/ansible/roles/a8/templates/q.sh.j2"
assert_exit "11: голий uv sync після \" #\" у лапках → 1" 1 "$tmproot/u29" "q.sh.j2"

# Назва extra — слово, не регекс: `.` не збігається з будь-яким символом.
make_uv_tree "$tmproot/u30" "$(deps_with 'uv sync --extra devXtest')" 'jobs:
  python:
    steps:
      - run: uv sync --extra dev.test'
assert_exit "11: у CI --extra dev.test, в агента devXtest → 1" 1 "$tmproot/u30" "uv sync без '--extra dev.test'"

# ─── Інваріанти 12–13: docker без IPv6, живий вимір фільтра V20 ──────────────
DTPL="infra/ansible/roles/a8/templates/daemon.json.j2"
g_daemon() { make_tree "$1" "$PLAY_OK" "$TASKS_OK"; printf '%s\n' "$2" >"$1/$DTPL"; }
g_daemon "$tmproot/g1" '{ "live-restore": true, "ipv6": true }'
assert_exit "12: daemon.json з \"ipv6\": true → 1" 1 "$tmproot/g1" "daemon.json вмикає IPv6"
g_daemon "$tmproot/g2" '{
  "ipv6": false,
  "live-restore": true
}'
assert_exit "12: \"ipv6\": false → 0" 0 "$tmproot/g2"
g_daemon "$tmproot/g3" '{ "fixed-cidr-v6": "fd00::/80" }'
assert_exit "12: fixed-cidr-v6 → 1" 1 "$tmproot/g3" "daemon.json вмикає IPv6"
g_daemon "$tmproot/g4" '{
  "ipv6": {{ a8_docker_ipv6 | to_json }},
  "live-restore": true
}'
assert_exit "12: \"ipv6\" з Jinja — не буквальне false → 1" 1 "$tmproot/g4" "daemon.json вмикає IPv6"

DEF="infra/ansible/roles/a8/defaults/main.yml"
VER="infra/ansible/roles/a8/tasks/verify.yml"
make_tree "$tmproot/h1" "$PLAY_OK" "$TASKS_OK"
printf '%s\n' '  - deb.debian.org # раптом дописали' >>"$tmproot/h1/$DEF"
assert_exit "13: ціль проби в allowlist → 1" 1 "$tmproot/h1" "є в a8_egress_domains"
make_tree "$tmproot/h2" "$PLAY_OK" "$TASKS_OK"
sed -i '/^a8_egress_probe_host:/d' "$tmproot/h2/$DEF"
assert_exit "13: немає a8_egress_probe_host → 1" 1 "$tmproot/h2" "немає a8_egress_probe_host"
make_tree "$tmproot/h3" "$PLAY_OK" "$TASKS_OK"
sed -i 's/getent ahostsv4/getent hosts/' "$tmproot/h3/$VER"
assert_exit "13: V20a — getent hosts замість ahostsv4 → 1" 1 "$tmproot/h3" "getent ahostsv4"
make_tree "$tmproot/h4" "$PLAY_OK" "$TASKS_OK"
sed -i 's/ *echo @@NO_GLOBAL_IPV6@@//' "$tmproot/h4/$VER"
assert_exit "13: V20a без маркера @@NO_GLOBAL_IPV6@@ → 1" 1 "$tmproot/h4" "@@NO_GLOBAL_IPV6@@"
make_tree "$tmproot/h5" "$PLAY_OK" "$TASKS_OK"
sed -i '/^      - --network$/d; /^      - host$/d' "$tmproot/h5/$VER"
assert_exit "13: V20b без --network host → 1" 1 "$tmproot/h5" "контроль без --network host"
make_tree "$tmproot/h6" "$PLAY_OK" "$TASKS_OK"
printf '%s\n' '---' '- name: V1 — something' '  ansible.builtin.debug:' '    msg: ok' >"$tmproot/h6/$VER"
assert_exit "13: у verify.yml немає V20 → 1" 1 "$tmproot/h6" "немає V20a, V20b і V20c"
make_tree "$tmproot/h7" "$PLAY_OK" "$TASKS_OK"
sed -i 's|/usr/local/bin/a8-run-agent|docker|; s|      - /home/agent/hart|      - run|' "$tmproot/h7/$VER"
assert_exit "13: V20a не через a8-run-agent → 1" 1 "$tmproot/h7" "не йде через a8-run-agent"
make_tree "$tmproot/h8" "$PLAY_OK" "$TASKS_OK"
python3 - "$tmproot/h8/$VER" <<'PY2'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("      - --network\n      - host\n", "      - --network=host\n", 1)
open(p, "w").write(s)
PY2
assert_exit "13: V20b з --network=host одним словом → 0" 0 "$tmproot/h8"

# Знахідки рецензії PR #150 (agy, Gemini 3.8 Flash).
g_daemon "$tmproot/g5" '{
  "ipv6"
    : true,
  "live-restore": true
}'
assert_exit "12: \"ipv6\" і true на різних рядках → 1" 1 "$tmproot/g5" "daemon.json вмикає IPv6"
g_daemon "$tmproot/g6" '{ "default-address-pools": [{ "base": "fd00:a8::/48", "size": 64 }] }'
assert_exit "12: IPv6-пул у default-address-pools → 1" 1 "$tmproot/g6" "IPv6-діапазон у пулі адрес"
g_daemon "$tmproot/g7" '{
  {# IPv6 вимкнено: фільтр лише IPv4 #}
  "ipv6": false,
  "live-restore": true
}'
assert_exit "12: \"ipv6\": false з Jinja-коментарем поруч → 0" 0 "$tmproot/g7"
make_tree "$tmproot/g8" "$PLAY_OK" "$TASKS_OK"
printf '%s\n' '[Service]' 'ExecStart=' 'ExecStart=/usr/bin/dockerd --ipv6 --fixed-cidr-v6 fd00::/80' \
  >"$tmproot/g8/infra/ansible/roles/a8/templates/dockerd-ipv6.conf.j2"
assert_exit "12: --ipv6 у drop-in шаблоні → 1" 1 "$tmproot/g8" "прапорець IPv6"
make_tree "$tmproot/g9" "$PLAY_OK" "$TASKS_OK"
sed -i 's/src: daemon.json.j2/src: daemon-v6.json.j2/' "$tmproot/g9/infra/ansible/roles/a8/tasks/docker.yml"
assert_exit "12: daemon.json ставить інший шаблон → 1" 1 "$tmproot/g9" "ставить не шаблон daemon.json.j2"
make_tree "$tmproot/g10" "$PLAY_OK" "$TASKS_OK"
rm "$tmproot/g10/infra/ansible/roles/a8/tasks/docker.yml"
assert_exit "12: немає задачі, що ставить daemon.json → 1" 1 "$tmproot/g10" "немає 'dest: /etc/docker/daemon.json'"

make_tree "$tmproot/h9" "$PLAY_OK" "$TASKS_OK"
mkdir -p "$tmproot/h9/infra/ansible/group_vars"
printf '%s\n' 'a8_egress_domains:' '  - github.com' '  - deb.debian.org' >"$tmproot/h9/infra/ansible/group_vars/a8.yml"
assert_exit "13: ціль проби в allowlist через group_vars → 1" 1 "$tmproot/h9" "є в a8_egress_domains"
make_tree "$tmproot/h10" "$PLAY_OK" "$TASKS_OK"
printf '%s\n' '  - "deb.debian.org" # у лапках' >>"$tmproot/h10/$DEF"
assert_exit "13: ціль проби в allowlist у лапках → 1" 1 "$tmproot/h10" "є в a8_egress_domains"
make_tree "$tmproot/h11" "$PLAY_OK" "$TASKS_OK"
sed -i 's/      - \*a8_egress_probe/      - echo @@DNS4_OK@@ @@EGRESS_REACHED@@/' "$tmproot/h11/$VER"
assert_exit "13: контроль V20b з фальшивим echo замість зонда → 1" 1 "$tmproot/h11" "бере не той самий зонд"
make_tree "$tmproot/h12" "$PLAY_OK" "$TASKS_OK"
sed -i 's/^- name: \(V20[abc]\) \(.*\)$/- name: "\1 \2"/' "$tmproot/h12/$VER"
assert_exit "13: назви V20 у лапках → 0" 0 "$tmproot/h12"
make_tree "$tmproot/h13" "$PLAY_OK" "$TASKS_OK"
python3 - "$tmproot/h13/$VER" <<'PY2'
import sys
p = sys.argv[1]; s = open(p).read()
s = s[:s.index("\n- name: V20c")] + "\n"
open(p, "w").write(s)
PY2
assert_exit "13: немає V20c (ipset test) → 1" 1 "$tmproot/h13" "немає V20a, V20b і V20c"

# ─── Мутації чинної ролі ───────────────────────────────────────────────────
# Копія справжньої ролі, у яку по черзі вносимо кожну з трьох реальних вад.
# Спершу доводимо, що НЕзламана копія зелена — інакше наступні три тести
# червоніли б із будь-якої причини, і мутація нічого б не доводила.
mut="$tmproot/mut"
mkdir -p "$mut/infra"
cp -r "$REPO/infra/ansible" "$mut/infra/ansible"
# Еталон системних бібліотек образу агента (інваріант 9).
cp -r "$REPO/infra/docker" "$mut/infra/docker"
# Еталон uv sync (інваріант 11) і локальний автономний прогін.
mkdir -p "$mut/.github/workflows" "$mut/tools/scripts"
cp "$REPO/.github/workflows/ci.yml" "$mut/.github/workflows/ci.yml"
cp "$REPO/tools/scripts/autorun.sh" "$mut/tools/scripts/autorun.sh"
assert_exit "мутація 0: чинна роль як є → 0" 0 "$mut"

sed -i 's|^\(\s*\)ansible_shell_executable: /bin/bash|\1# знято мутацією|' "$mut/infra/ansible/a8.yml"
assert_exit "мутація 1: прибрано bash із play → 1" 1 "$mut"
cp -r "$REPO/infra/ansible/a8.yml" "$mut/infra/ansible/a8.yml"

python3 - "$mut/infra/ansible/roles/a8/tasks/main.yml" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
s = re.sub(
    r'include_tasks:\n\s*file: (\S+)\n\s*apply:\n\s*tags: \[[^\]]*\]',
    r'include_tasks: \1',
    s,
)
open(p, 'w').write(s)
PY
assert_exit "мутація 2: include_tasks назад у рядкову форму → 1" 1 "$mut"
cp "$REPO/infra/ansible/roles/a8/tasks/main.yml" "$mut/infra/ansible/roles/a8/tasks/main.yml"

python3 - "$mut/infra/ansible/roles/a8/tasks/verify.yml" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace(
    "  ansible.builtin.command:\n    argv:\n      - /usr/local/bin/a8-run-agent\n",
    "  ansible.builtin.command: >-\n    /usr/local/bin/a8-run-agent\n",
    1,
)
open(p, 'w').write(s)
PY
assert_exit "мутація 3: зонд назад у рядкову форму → 1" 1 "$mut"
cp "$REPO/infra/ansible/roles/a8/tasks/verify.yml" "$mut/infra/ansible/roles/a8/tasks/verify.yml"

# Мутація 4 — повертаємо в зонд shell-змінну, тобто рівно ту ваду, через яку
# V6b падала 2026-09-19 при справному середовищі.
python3 - "$mut/infra/ansible/roles/a8/tasks/verify.yml" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
# Прив'язка саме до РЯДКА КОДУ, а не до першого входження підрядка:
# `printenv HOME` згадується ще й у коментарі над зондом, і мутація без
# відступу правила б коментар, лишаючи код цілим. Guard тоді законно мовчить,
# а тест «проходить», доводячи лише власну присутність (docs/16 §8.1).
anchor = "\n        printenv HOME\n"
assert anchor in s, "фікстура застаріла: у зонді немає рядка `printenv HOME`"
s = s.replace(anchor, '\n        echo "HOME=$HOME"\n', 1)
open(p, 'w').write(s)
PY
assert_exit "мутація 4: shell-змінна назад у зонд → 1" 1 "$mut"
cp "$REPO/infra/ansible/roles/a8/tasks/verify.yml" "$mut/infra/ansible/roles/a8/tasks/verify.yml"

# Мутація 5 — повертаємо login-shell у зонд V10a. Прив'язка за відступом до
# рядка коду, а не до підрядка: `-c` трапляється в тексті часто.
python3 - "$mut/infra/ansible/roles/a8/tasks/verify.yml" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = "      - -c\n      - command -v lefthook\n"
assert anchor in s, "фікстура застаріла: V10a більше не виглядає так"
s = s.replace(anchor, "      - -lc\n      - command -v lefthook\n", 1)
open(p, 'w').write(s)
PY
assert_exit "мутація 5: login-shell назад у зонд → 1" 1 "$mut"
cp "$REPO/infra/ansible/roles/a8/tasks/verify.yml" "$mut/infra/ansible/roles/a8/tasks/verify.yml"

# Мутація 6 — повертаємо обгортці дієслово `check`. Це і є та вада, через яку
# оракул останньої дозволеної задачі дня падав би кодом 11. Тестом її не
# дістати: a8-tick.test.sh підміняє обгортку заглушкою.
python3 - "$mut/infra/ansible/roles/a8/templates/a8-run-agent.sh.j2" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = "\n/usr/local/bin/a8-guard check-run >&2\n"
assert anchor in s, "фікстура застаріла: обгортка більше не кличе guard так"
s = s.replace(anchor, "\n/usr/local/bin/a8-guard check >&2\n", 1)
open(p, 'w').write(s)
PY
assert_exit "мутація 6: обгортка назад на 'a8-guard check' → 1" 1 "$mut"
cp "$REPO/infra/ansible/roles/a8/templates/a8-run-agent.sh.j2" "$mut/infra/ansible/roles/a8/templates/a8-run-agent.sh.j2"

# Мутація 7 — повертаємо verify.yml до судження про машину за змінною play'ю.
# Саме так `--tags verify` без `-e` повідомляв «КРЕДЕНШАЛА НА PUSH НЕМАЄ» при
# налаштованому deploy_key на машині (2026-09-20).
python3 - "$mut/infra/ansible/roles/a8/tasks/verify.yml" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = "  when: a8_v_push_kind != 'none'\n"
assert anchor in s, "фікстура застаріла: V11 більше не гілкується так"
s = s.replace(anchor, "  when: a8_push_credential_kind != 'none'\n", 1)
open(p, 'w').write(s)
PY
assert_exit "мутація 7: verify.yml назад на змінну play'ю → 1" 1 "$mut"
cp "$REPO/infra/ansible/roles/a8/tasks/verify.yml" "$mut/infra/ansible/roles/a8/tasks/verify.yml"

# Мутація 8 — знімаємо `| bool` з умови примусу egress. Саме на цьому впало
# застосування на A8 2026-09-21, а на старішому ansible-core та сама вада
# мовчки інвертує прапорець замість падіння.
python3 - "$mut/infra/ansible/roles/a8/tasks/main.yml" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = "  when:\n    - a8_egress_enabled | bool\n    - a8_egress_enforce | bool\n"
assert anchor in s, "фікстура застаріла: умова примусу egress виглядає інакше"
s = s.replace(anchor, "  when:\n    - a8_egress_enabled\n    - a8_egress_enforce\n", 1)
open(p, 'w').write(s)
PY
assert_exit "мутація 8: умова egress без '| bool' → 1" 1 "$mut"
cp "$REPO/infra/ansible/roles/a8/tasks/main.yml" "$mut/infra/ansible/roles/a8/tasks/main.yml"

# Мутація 9 — той самий клас у тернарнику стану таймера. Це найнебезпечніший
# випадок: `-e a8_tick_timer_enabled=false` на ansible-core 2.16 дає "started".
python3 - "$mut/infra/ansible/roles/a8/tasks/main.yml" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = "'started' if a8_tick_timer_enabled | bool else 'stopped'"
assert anchor in s, "фікстура застаріла: тернарник стану таймера виглядає інакше"
s = s.replace(anchor, "'started' if a8_tick_timer_enabled else 'stopped'", 1)
open(p, 'w').write(s)
PY
assert_exit "мутація 9: тернарник таймера без '| bool' → 1" 1 "$mut"
cp "$REPO/infra/ansible/roles/a8/tasks/main.yml" "$mut/infra/ansible/roles/a8/tasks/main.yml"

# Мутація 10 — той самий клас у ШАБЛОНІ. Перша редакція інваріанта 8 дивилась
# лише в tasks/ і цю міну не бачила: при `-e a8_egress_enforce=false` рядок
# "false" у Jinja істинний, тож відрендерився б код, який ПОВЕРТАЄ правила
# примусу кожні 30 хв, поки роль їх одноразово знімає.
python3 - "$mut/infra/ansible/roles/a8/templates/a8-egress-refresh.sh.j2" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = "{% if a8_egress_enforce | bool %}"
assert anchor in s, "фікстура застаріла: умова примусу в шаблоні виглядає інакше"
s = s.replace(anchor, "{% if a8_egress_enforce %}", 1)
open(p, 'w').write(s)
PY
assert_exit "мутація 10: Jinja-умова в шаблоні без '| bool' → 1" 1 "$mut"
cp "$REPO/infra/ansible/roles/a8/templates/a8-egress-refresh.sh.j2" "$mut/infra/ansible/roles/a8/templates/a8-egress-refresh.sh.j2"

# Мутації 11–13 — інваріант 9, паритет системних бібліотек з образом воркера.
AGENT_DF="infra/ansible/roles/a8/files/agent.Dockerfile"
CAD_DF="infra/docker/cad-worker.Dockerfile"

# 11: з образу агента зникла одна бібліотека — рівно та, без якої оракул
# воркера на A8 давав rc=2 (libGL.so.1).
python3 - "$mut/$AGENT_DF" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = "libgl1 libglu1-mesa"
assert anchor in s, "фікстура застаріла: рядок пакетів в agent.Dockerfile виглядає інакше"
s = s.replace(anchor, "libglu1-mesa", 1)
open(p, 'w').write(s)
PY
assert_exit "мутація 11: з образу агента прибрано libgl1 → 1" 1 "$mut"
cp "$REPO/$AGENT_DF" "$mut/$AGENT_DF"

# 12: воркер отримав нову бібліотеку, а агент — ні. Перевірка йде ЗА еталоном,
# а не за списком, переписаним у скрипт.
python3 - "$mut/$CAD_DF" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = "AS runner\n\nRUN apt-get update && apt-get install -y --no-install-recommends \\\n"
assert anchor in s, "фікстура застаріла: runtime-стадія cad-worker.Dockerfile виглядає інакше"
s = s.replace(anchor, anchor + "    libxkbcommon0 \\\n", 1)
open(p, 'w').write(s)
PY
assert_exit "мутація 12: у воркера нова бібліотека, в агента немає → 1" 1 "$mut"
cp "$REPO/$CAD_DF" "$mut/$CAD_DF"

# 13: runtime-стадію перейменовано — розбір не знаходить жодного пакета.
# Порожній еталон мусить бути червоним: інакше інваріант «проходить», не
# виконавшись (той самий клас, що з grep у інваріанті 8).
sed -i 's/ AS runner$/ AS runtime/' "$mut/$CAD_DF"
assert_exit "мутація 13: еталон не розібрано (стадію перейменовано) → 1" 1 "$mut"
cp "$REPO/$CAD_DF" "$mut/$CAD_DF"

# 14: еталона немає взагалі (перейменовано, видалено). Мовчазний пропуск тут
# був першою редакцією інваріанта — знайшов рецензент (Gemini 3.8 Flash).
rm "$mut/$CAD_DF"
assert_exit "мутація 14: cad-worker.Dockerfile відсутній → 1" 1 "$mut"
cp "$REPO/$CAD_DF" "$mut/$CAD_DF"

# 15: друга інструкція `apt-get install` у runtime-стадії воркера. Парсер,
# що зупинявся на першому `&&`, її не бачив.
python3 - "$mut/$CAD_DF" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = "    && rm -rf /var/lib/apt/lists/*\n\nRUN useradd"
assert anchor in s, "фікстура застаріла: кінець apt-шару runtime-стадії виглядає інакше"
s = s.replace(anchor, "    && rm -rf /var/lib/apt/lists/*\nRUN apt-get update && apt-get install -y libxkbcommon0 && rm -rf /var/lib/apt/lists/*\n\nRUN useradd", 1)
open(p, 'w').write(s)
PY
assert_exit "мутація 15: друга apt-get install у воркері, в агента пакета немає → 1" 1 "$mut"
cp "$REPO/$CAD_DF" "$mut/$CAD_DF"

# 16: пакет із піном версії (`імʼя=версія`) — теж пакет еталона.
python3 - "$mut/$CAD_DF" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = "AS runner\n\nRUN apt-get update && apt-get install -y --no-install-recommends \\\n"
assert anchor in s, "фікстура застаріла: runtime-стадія cad-worker.Dockerfile виглядає інакше"
s = s.replace(anchor, anchor + "    libxkbcommon0=1.5.0-1 \\\n", 1)
open(p, 'w').write(s)
PY
assert_exit "мутація 16: у воркера пакет із піном версії, в агента немає → 1" 1 "$mut"
cp "$REPO/$CAD_DF" "$mut/$CAD_DF"

# 17: пакет із суфіксом архітектури (`імʼя:amd64`) — теж пакет еталона.
# Знайшов рецензент (agy, Claude Opus 4.6, PR #142).
python3 - "$mut/$CAD_DF" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = "AS runner\n\nRUN apt-get update && apt-get install -y --no-install-recommends \\\n"
assert anchor in s, "фікстура застаріла: runtime-стадія cad-worker.Dockerfile виглядає інакше"
s = s.replace(anchor, anchor + "    libxkbcommon0:amd64 \\\n", 1)
open(p, 'w').write(s)
PY
assert_exit "мутація 17: у воркера пакет із :amd64, в агента немає → 1" 1 "$mut"
cp "$REPO/$CAD_DF" "$mut/$CAD_DF"

# Мутації 18–23 — інваріант 10, мережа збірки й мережа агента.
TASKS_MAIN="infra/ansible/roles/a8/tasks/main.yml"
RUNNER="infra/ansible/roles/a8/templates/a8-run-agent.sh.j2"

# 18: збірка знову без мережі хоста — рівно стан, у якому 2026-09-28 впало
# застосування (apt-get → deb.debian.org, connection timed out).
python3 - "$mut/$TASKS_MAIN" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = "    docker build\n    --network host\n"
assert anchor in s, "фікстура застаріла: задача збірки образу виглядає інакше"
s = s.replace(anchor, "    docker build\n", 1)
open(p, 'w').write(s)
PY
assert_exit "мутація 18: зі збірки прибрано --network host → 1" 1 "$mut" "docker build без --network host"
cp "$REPO/$TASKS_MAIN" "$mut/$TASKS_MAIN"

# 19: агент у мережі хоста — поза DOCKER-USER, тобто без allowlist'а.
python3 - "$mut/$RUNNER" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = "exec docker run --rm \\\n"
assert anchor in s, "фікстура застаріла: обгортка більше не запускає контейнер так"
s = s.replace(anchor, anchor + "  --network host \\\n", 1)
open(p, 'w').write(s)
PY
assert_exit "мутація 19: обгортка запускає агента з --network host → 1" 1 "$mut" "шаблон чи файл ролі задає мережу контейнера"
cp "$REPO/$RUNNER" "$mut/$RUNNER"

# 20: агент у власній мережі — свій міст br-…, правило на docker0 його не бачить.
python3 - "$mut/$RUNNER" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = "[[ -n \"${A8_CONTAINER_NAME:-}\" ]] && OPT_ARGS+=(--name \"$A8_CONTAINER_NAME\")\n"
assert anchor in s, "фікстура застаріла: необов'язкові прапорці обгортки виглядають інакше"
s = s.replace(anchor, anchor + "OPT_ARGS+=(--net=a8-agents)\n", 1)
open(p, 'w').write(s)
PY
assert_exit "мутація 20: обгортка додає --net=a8-agents → 1" 1 "$mut" "шаблон чи файл ролі задає мережу контейнера"
cp "$REPO/$RUNNER" "$mut/$RUNNER"

# 21: повтор прапорця у збірці — останнє значення bridge.
python3 - "$mut/$TASKS_MAIN" <<'PY2'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = "    docker build\n    --network host\n"
assert anchor in s, "фікстура застаріла: задача збірки образу виглядає інакше"
s = s.replace(anchor, anchor + "    --network bridge\n", 1)
open(p, 'w').write(s)
PY2
assert_exit "мутація 21: після --network host додано --network bridge → 1" 1 "$mut" "docker build без --network host"
cp "$REPO/$TASKS_MAIN" "$mut/$TASKS_MAIN"

# 22: docker кладе контейнери на інший міст, фільтр лишився на docker0.
DAEMON="infra/ansible/roles/a8/templates/daemon.json.j2"
python3 - "$mut/$DAEMON" <<'PY2'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = '  "live-restore": true,\n'
assert anchor in s, "фікстура застаріла: daemon.json.j2 виглядає інакше"
s = s.replace(anchor, '  "bridge": "br-a8",\n' + anchor, 1)
open(p, 'w').write(s)
PY2
assert_exit "мутація 22: daemon.json задає \"bridge\": \"br-a8\" → 1" 1 "$mut" "міст egress-фільтра"
cp "$REPO/$DAEMON" "$mut/$DAEMON"

# 23: обгортку ставить інший шаблон, а перевіряється старий.
python3 - "$mut/$TASKS_MAIN" <<'PY2'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = "    src: a8-run-agent.sh.j2\n    dest: /usr/local/bin/a8-run-agent\n"
assert anchor in s, "фікстура застаріла: задача встановлення обгортки виглядає інакше"
s = s.replace(anchor, "    src: a8-run-agent-host.sh.j2\n    dest: /usr/local/bin/a8-run-agent\n", 1)
open(p, 'w').write(s)
PY2
assert_exit "мутація 23: обгортку ставить інший шаблон → 1" 1 "$mut" "обгортку ставить не шаблон"
cp "$REPO/$TASKS_MAIN" "$mut/$TASKS_MAIN"

# Мутації 24–27 — інваріант 11, uv sync агента = uv sync CI.
TICK="infra/ansible/roles/a8/templates/a8-tick.sh.j2"
VERIFY="infra/ansible/roles/a8/tasks/verify.yml"
AUTORUN="tools/scripts/autorun.sh"

# 24: тік знову ставить без dev — рівно стан до 2026-09-29.
python3 - "$mut/$TICK" <<'PY2'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = "bash -c 'cd workers/cad && uv sync --extra dev'"
assert anchor in s, "фікстура застаріла: крок uv sync у тіку виглядає інакше"
s = s.replace(anchor, "bash -c 'cd workers/cad && uv sync'", 1)
open(p, 'w').write(s)
PY2
assert_exit "мутація 24: тік — голий uv sync → 1" 1 "$mut" "a8-tick.sh.j2"
cp "$REPO/$TICK" "$mut/$TICK"

# 25: V18c без dev — V18e падає на «Failed to spawn: pytest».
python3 - "$mut/$VERIFY" <<'PY2'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = "(cd workers/cad && uv sync --extra dev --quiet)"
assert anchor in s, "фікстура застаріла: V18c виглядає інакше"
s = s.replace(anchor, "(cd workers/cad && uv sync --quiet)", 1)
open(p, 'w').write(s)
PY2
assert_exit "мутація 25: V18c — uv sync --quiet без dev → 1" 1 "$mut" "verify.yml"
cp "$REPO/$VERIFY" "$mut/$VERIFY"

# 26: локальний автономний прогін без dev.
python3 - "$mut/$AUTORUN" <<'PY2'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = '(cd "$WT_DIR/workers/cad" && uv sync --extra dev)'
assert anchor in s, "фікстура застаріла: крок uv sync в autorun.sh виглядає інакше"
s = s.replace(anchor, '(cd "$WT_DIR/workers/cad" && uv sync)', 1)
open(p, 'w').write(s)
PY2
assert_exit "мутація 26: autorun.sh — голий uv sync → 1" 1 "$mut" "autorun.sh"
cp "$REPO/$AUTORUN" "$mut/$AUTORUN"

# 27: CI додав extra, роль — ні. Порушень три (тік, V18c, autorun.sh), тож
# перевіряємо код і текст, без вимоги «рівно одне».
sed -i 's/run: uv sync --extra dev$/run: uv sync --extra dev --extra docs/' "$mut/.github/workflows/ci.yml"
grep -q 'uv sync --extra dev --extra docs' "$mut/.github/workflows/ci.yml" ||
  { echo "✗ фікстура застаріла: у ci.yml немає 'run: uv sync --extra dev'"; fail=1; }
assert_exit "мутація 27: у CI нове extra, в агента немає → 1" 1 "$mut"
# Рівно три порушення, і кожне — в іншому місці (знайшов рецензент agy,
# Gemini 3.8 Flash, PR #148: без цього мовчазний пропуск двох файлів лишав би
# мутацію зеленою).
grep -qF "порушено (3):" "$tmproot/out" ||
  { echo "✗ мутація 27: очікував рівно три порушення"; sed 's/^/    /' "$tmproot/out"; fail=1; }
for where in a8-tick.sh.j2 verify.yml autorun.sh; do
  grep -F "uv sync без '--extra docs'" "$tmproot/out" | grep -qF "$where" ||
    { echo "✗ мутація 27: немає порушення про --extra docs у $where"; fail=1; }
done
cp "$REPO/.github/workflows/ci.yml" "$mut/.github/workflows/ci.yml"

# Мутації 28–32 — інваріанти 12–13, docker без IPv6 і живий вимір фільтра.
DAEMON_T="infra/ansible/roles/a8/templates/daemon.json.j2"
DEFAULTS="infra/ansible/roles/a8/defaults/main.yml"
VERIFY_Y="infra/ansible/roles/a8/tasks/verify.yml"

# 28: docker вмикає IPv6 — агент обходить IPv4-фільтр.
python3 - "$mut/$DAEMON_T" <<'PY2'
import sys
p = sys.argv[1]; s = open(p).read()
anchor = '  "live-restore": true,\n'
assert anchor in s, "фікстура застаріла: daemon.json.j2 виглядає інакше"
s = s.replace(anchor, '  "ipv6": true,\n' + anchor, 1)
open(p, "w").write(s)
PY2
assert_exit "мутація 28: daemon.json вмикає IPv6 → 1" 1 "$mut" "daemon.json вмикає IPv6"
cp "$REPO/$DAEMON_T" "$mut/$DAEMON_T"

# 29: ціль проби потрапила в allowlist — REACHED агента стає нормою.
python3 - "$mut/$DEFAULTS" <<'PY2'
import sys
p = sys.argv[1]; s = open(p).read()
anchor = "  - pypi.org # uv\n"
assert anchor in s, "фікстура застаріла: a8_egress_domains виглядає інакше"
s = s.replace(anchor, anchor + "  - deb.debian.org # apt\n", 1)
open(p, "w").write(s)
PY2
assert_exit "мутація 29: ціль проби дописано в allowlist → 1" 1 "$mut" "є в a8_egress_domains"
cp "$REPO/$DEFAULTS" "$mut/$DEFAULTS"

# 30: проба знову без явного IPv4.
python3 - "$mut/$VERIFY_Y" <<'PY2'
import sys
p = sys.argv[1]; s = open(p).read()
anchor = "getent ahostsv4 {{ a8_egress_probe_host }}"
assert s.count(anchor) == 1, "фікстура застаріла: зонд V20a виглядає інакше"
s = s.replace(anchor, "getent hosts {{ a8_egress_probe_host }}")
open(p, "w").write(s)
PY2
assert_exit "мутація 30: V20a — getent hosts замість ahostsv4 → 1" 1 "$mut" "getent ahostsv4"
cp "$REPO/$VERIFY_Y" "$mut/$VERIFY_Y"

# 31: контроль без мережі хоста — BLOCKED агента нічого не доводить.
python3 - "$mut/$VERIFY_Y" <<'PY2'
import sys
p = sys.argv[1]; s = open(p).read()
anchor = "      - --rm\n      - --network\n      - host\n"
assert anchor in s, "фікстура застаріла: V20b виглядає інакше"
s = s.replace(anchor, "      - --rm\n", 1)
open(p, "w").write(s)
PY2
assert_exit "мутація 31: V20b без --network host → 1" 1 "$mut" "контроль без --network host"
cp "$REPO/$VERIFY_Y" "$mut/$VERIFY_Y"

# 32: контроль друкує маркери сам, а не виконує зонд — V20c завжди зелений.
python3 - "$mut/$VERIFY_Y" <<'PY2'
import sys
p = sys.argv[1]; s = open(p).read()
anchor = "      - *a8_egress_probe\n"
assert s.count(anchor) == 1, "фікстура застаріла: V20b виглядає інакше"
s = s.replace(anchor, "      - echo @@DNS4_OK@@ @@EGRESS_REACHED@@\n", 1)
open(p, "w").write(s)
PY2
assert_exit "мутація 32: V20b друкує маркери замість зонда → 1" 1 "$mut" "бере не той самий зонд"
cp "$REPO/$VERIFY_Y" "$mut/$VERIFY_Y"

if [[ "$fail" -eq 0 ]]; then
  echo "check-ansible-a8: усі перевірки пройдено"
else
  echo "check-ansible-a8: є падіння" >&2
fi
exit "$fail"
