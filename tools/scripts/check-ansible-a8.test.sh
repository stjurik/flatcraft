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
  mkdir -p "$dir/infra/ansible/roles/a8/tasks"
  printf '%s\n' "$2" >"$dir/infra/ansible/a8.yml"
  printf '%s\n' "$3" >"$dir/infra/ansible/roles/a8/tasks/main.yml"
}

assert_exit() {
  local name="$1" expected="$2" dir="$3"
  local actual=0
  ROOT="$dir" "$SCRIPT" >"$tmproot/out" 2>&1 || actual=$?
  if [[ "$actual" -eq "$expected" ]]; then
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
      - echo "$HOME"'

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

# Тест 6 — згадка a8-run-agent у коментарі не є викликом.
make_tree "$tmproot/cmt" "$PLAY_OK" '---
- name: container
  # Запускаємо через a8-run-agent — єдине місце, де описано docker run.
  ansible.builtin.command:
    argv:
      - /usr/local/bin/a8-run-agent
      - /home/agent/hart'
assert_exit "a8-run-agent у коментарі → 0" 0 "$tmproot/cmt"

# ─── Мутації чинної ролі ───────────────────────────────────────────────────
# Копія справжньої ролі, у яку по черзі вносимо кожну з трьох реальних вад.
# Спершу доводимо, що НЕзламана копія зелена — інакше наступні три тести
# червоніли б із будь-якої причини, і мутація нічого б не доводила.
mut="$tmproot/mut"
mkdir -p "$mut/infra"
cp -r "$REPO/infra/ansible" "$mut/infra/ansible"
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

if [[ "$fail" -eq 0 ]]; then
  echo "check-ansible-a8: усі перевірки пройдено"
else
  echo "check-ansible-a8: є падіння" >&2
fi
exit "$fail"
