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

if [[ "$fail" -eq 0 ]]; then
  echo "check-ansible-a8: усі перевірки пройдено"
else
  echo "check-ansible-a8: є падіння" >&2
fi
exit "$fail"
