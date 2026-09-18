# Вхід рев'ю №2 — готова роль `a8` і таблиця assertion'ів

**Роль для тебе:** Рев'юер. **Обмеження:** не виконуй bash, читай лише `read_file`.
Пиши **виключно** у `docs/promts/inputs/agy-a8-role-2-output.md`.

## Що читати

- `infra/ansible/a8.yml`
- `infra/ansible/roles/a8/defaults/main.yml`
- `infra/ansible/roles/a8/tasks/main.yml`
- `infra/ansible/roles/a8/tasks/verify.yml`
- `infra/ansible/roles/a8/README.md` — таблиця §2 «вимога → задача → assertion → вимір»
- `infra/ansible/roles/a8/templates/` — усі шаблони, особливо `a8-run-agent.sh.j2`,
  `a8-guard.sh.j2`, `a8-egress-rules.sh.j2`, `a8-trust.py.j2`
- для звірки фактів: `docs/promts/inputs/measurement-6-git-in-container.md`,
  `docs/promts/inputs/measurement-7-push.md`, `docs/19_A8_PREFLIGHT.md`

## Стан оракулів (уже прогнано)

- `ansible-playbook a8.yml --syntax-check` → exit 0
- `ansible-lint a8.yml roles/a8/` → **Passed, 0 failures, профіль production**, 17 файлів
- `ansible-playbook a8.yml -i inventory.a8.ini --check --diff` → exit 0, `failed=0`,
  `changed=13`, `skipped=8`

Сухий прогін уже знайшов два дефекти, які я виправив:

1. `Enable egress refresh timer` падав у `--check`: юніт-файл фізично не пишеться,
   systemd його не бачить. Виправлено через `not ansible_check_mode` (а не `check_mode: no`,
   бо той робить реальний запис у сухому прогоні).
2. Задача довіри Claude Code переписувала ВЕСЬ `~/.claude.json` (973 рядки, відступ 2→4)
   через `to_nice_json`, тобто була б «changed» назавжди і могла затерти паралельний запис
   живої сесії. Замінено на точковий ідемпотентний скрипт `a8-trust.py`.

## Головне питання цього рев'ю

**Чи доводить кожен assertion саме ту вимогу, навпроти якої він стоїть у таблиці §2 README?**

Для КОЖНОГО з 16 рядків таблиці дай один із трьох вердиктів і обґрунтуй:

- **ДОВОДИТЬ** — assertion упаде, якщо вимогу порушити;
- **НЕ ДОВОДИТЬ** — assertion може лишитись зеленим на зламаній вимозі; назви сценарій;
- **ЧАСТКОВО** — доводить вужче твердження, ніж заявлено; назви, яке саме.

Мисленнєвий тест на кожен рядок: «що конкретно треба зламати в середовищі, щоб цей
assertion почервонів?» Якщо відповідь «нічого з того, про що вимога» — це НЕ ДОВОДИТЬ.

## Додатково

1. У `a8-egress-rules.sh.j2` позиція правил обчислюється пошуком останнього
   `RELATED,ESTABLISHED` у `DOCKER-USER`. Чи є вхідні дані, на яких ця арифметика дасть
   неправильну позицію? Порожній ланцюг, кілька стейтових правил, інший порядок?
2. У `a8-guard.sh.j2` три падіння поспіль рахуються `tail -n 3 | grep -c '^failed$'`.
   Знайди вхідні дані, на яких ця логіка дасть хибний результат.
3. Що в ролі зламається при ПОВТОРНОМУ застосуванні (ідемпотентність)?
4. Де я видаю припущення за факт? Перевір цитатою.

Якщо чогось не можеш перевірити — пиши «НЕ ПЕРЕВІРЕНО» і причину.
