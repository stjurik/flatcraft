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
  printf '%s\n' 'a8_egress_bridge: docker0' >"$dir/infra/ansible/roles/a8/defaults/main.yml"
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
printf '%s\n' 'a8_egress_bridge: br0' >"$tmproot/n27/infra/ansible/roles/a8/defaults/main.yml"
assert_exit "10: daemon.json і фільтр — обидва br0 → 0" 0 "$tmproot/n27"

make_net_tree "$tmproot/n28"
mkdir -p "$tmproot/n28/infra/ansible/group_vars"
printf '%s\n' 'a8_egress_bridge: br0' >"$tmproot/n28/infra/ansible/group_vars/a8.yml"
assert_exit "10: group_vars переносить фільтр з docker0 → 1" 1 "$tmproot/n28" "міст egress-фільтра"

make_net_tree "$tmproot/n29"
: >"$tmproot/n29/infra/ansible/roles/a8/defaults/main.yml"
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
printf '%s\n' "a8_egress_bridge: 'docker0'" >"$tmproot/n36/infra/ansible/roles/a8/defaults/main.yml"
assert_exit "10: a8_egress_bridge: 'docker0' в одинарних лапках → 0" 0 "$tmproot/n36"

# host_vars перекриває defaults і group_vars.
make_net_tree "$tmproot/n37"
mkdir -p "$tmproot/n37/infra/ansible/host_vars"
printf '%s\n' 'a8_egress_bridge: br-custom' >"$tmproot/n37/infra/ansible/host_vars/a8.yml"
assert_exit "10: host_vars переносить фільтр на br-custom → 1" 1 "$tmproot/n37" "міст egress-фільтра (br-custom)"

# ─── Мутації чинної ролі ───────────────────────────────────────────────────
# Копія справжньої ролі, у яку по черзі вносимо кожну з трьох реальних вад.
# Спершу доводимо, що НЕзламана копія зелена — інакше наступні три тести
# червоніли б із будь-якої причини, і мутація нічого б не доводила.
mut="$tmproot/mut"
mkdir -p "$mut/infra"
cp -r "$REPO/infra/ansible" "$mut/infra/ansible"
# Еталон системних бібліотек образу агента (інваріант 9).
cp -r "$REPO/infra/docker" "$mut/infra/docker"
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

if [[ "$fail" -eq 0 ]]; then
  echo "check-ansible-a8: усі перевірки пройдено"
else
  echo "check-ansible-a8: є падіння" >&2
fi
exit "$fail"
