# Вимір №7 — `push` із контейнера агента

**Дата:** 2026-09-18 · **Машина:** A8 (`a8`, Ubuntu, kernel 6.8.0-139-generic) · **Репо:** `/home/agent/hart`, власник `agent` (uid 1002)
**Роль:** Розвідник (`docs/15` §0) · **Питання:** чи може демон Стадії 1 віддати результат — і чи щось тримає його від `main`

> **Звідки керувався прогін.** Сесія працювала не на A8, а на `T470` (WSL, `uid=1000(yurii)`); контейнери
> запускались через `ssh a8-ts` (tailnet). LAN-аліас `a8` (192.168.1.20) дав `exit=124` — timeout; tailnet-аліас
> `a8-ts` відповів одразу. Це не впливає на вимір (усі команди виконувались усередині контейнера на A8), але
> пояснює, чому в логах немає локальної консолі A8.
>
> **Метод.** Правила вимірювального прогону цитуються **змістом, а не номером розділу**: `docs/16` §8.2 живе лише
> в гілці `claude/agent-orchestration-planning-w06nh9` (PR #113, не змерджено), і читач `main` номер не перевірить.

---

## 1. Передбачення, записані ДО прогону

Сліпий пріор (до інвентаризації §2, зафіксований у плані):

| Прогін | Очікування ДО                                                                                 | Заявлена впевненість          |
| ------ | --------------------------------------------------------------------------------------------- | ----------------------------- |
| A      | exit 0, список ref'ів                                                                         | висока                        |
| B1     | падає; **розвилка:** HTTPS → `could not read Username`; SSH → `Permission denied (publickey)` | середня                       |
| B2     | **тільки за HTTPS** зависає до `timeout`, exit 124                                            | **слабка, позначена наперед** |
| C      | відмова через відсутній креденшал, не через protection; `gh api …/protection` → **404**       | середня                       |
| D      | `fetch`/`rebase` → 0; хук при коміті → `Can't find lefthook in PATH`, коміт проходить         | середня                       |

Правило «записуйте очікування ДО, і в звіт ідуть обидва, навіть коли збіглися» дотримано буквально: очікування
вкарбовані в сам `probe.sh` і друкуються в логу **над** результатом кожного прогону.

Два передбачення не справдились: **B2** (див. §2, рядок B2/B3) і **C у частині protection** — вона існує.

---

## 2. Таблиця результатів

| Що                                      | Очікування ДО                 | Факт (дослівно)                                                                                                              | Контроль був?                                         | Вердикт                                  |
| --------------------------------------- | ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------- | ---------------------------------------- |
| §2 інвентаризація, комірка 1            | невідомо, пріор не формувався | ні `.ssh`, ні `.git-credentials`, ні `.gitconfig`, `credential.helper` не задано, токен-змінних нема                         | так: комірка 2 зі справжнім `$HOME`                   | ✅ креденшала нема                       |
| §2 інвентаризація, комірка 2            | те саме                       | у справжньому `~agent` теж нічого: `.ssh`, `.git-credentials`, `.gitconfig`, `.config/git`, `.config/gh` — усі відсутні      | це і є контроль до комірки 1                          | ✅ негатив **виміряний**, не влаштований |
| **A** — `ls-remote` без креденшала      | exit 0                        | список ref'ів, **exit=0**                                                                                                    | лічильники `DOCKER-USER` до/після                     | ✅ контроль зелений                      |
| **B1** — push, `GIT_TERMINAL_PROMPT=0`  | падає, 128                    | `fatal: could not read Username for 'https://github.com': terminal prompts disabled`, **exit=128**                           | пара з B2                                             | ✅ збіглось                              |
| **B2** — push без `GIT_TERMINAL_PROMPT` | **зависне**, exit 124         | `fatal: could not read Username for 'https://github.com': No such device or address`, **exit=128** — **не завис**            | пара з B1 (одна змінна) і далі B3                     | ❌ передбачення хибне                    |
| **B3** — те саме з `-t`                 | (додано після B2) зависне     | `Username for 'https://github.com':` → **exit=124**                                                                          | одна змінна проти B2: наявність термінала             | ✅ зависання існує, але потребує TTY     |
| **C** — `push --dry-run` у `main`       | відмова по креденшалу         | `fatal: could not read Username …: terminal prompts disabled`, **exit=128** — в **обох** комірках                            | комірка 2 + незалежна перевірка `gh api`              | ⚠️ до protection справа не дійшла        |
| **C-хост** — `gh api …/protection`      | **404** (захисту немає)       | **200**: PR + 1 апрув + 10 required checks, `allow_force_pushes: false`; але **`enforce_admins: enabled: false`**            | `--jq .permissions` → `admin:true`; `rulesets` → `[]` | ❌ передбачення хибне; лінія є, з діркою |
| **D1** — `fetch` із worktree            | 0                             | `30915d3..3a51217  main -> origin/main`, **exit=0**                                                                          | —                                                     | ✅                                       |
| **D2** — `rebase` із worktree           | 0                             | `Successfully rebased and updated refs/heads/probe/push-7.`, **exit=0**                                                      | —                                                     | ✅                                       |
| **D3** — хук при справжньому коміті     | попередження, коміт проходить | `.git/hooks/pre-commit` існує (2780 B); `command -v lefthook` → `which_exit=1`; `Can't find lefthook in PATH` ×2; **exit=0** | пара: наявність хука проти наявності бінарника        | ⚠️ хук — no-op, окрема вимога до образу  |
| Чистота репо після прогону              | (не передбачалось)            | `find /home/agent/hart -not -user agent \| wc -l` → **0**                                                                    | той самий критерій, що у вимірі №6 §3.2               | ✅ комірка 1002 репо не псує             |

---

## 3. Дослівні виводи

### 3.0. Команди, що створили середовище

Комірка 1 — конфігурація Стадії 1 (чистий записуваний `$HOME`):

```
sudo -n -u agent docker run --rm --user 1002:1002 \
  -v /home/agent/hart:/repo \
  -v /home/agent/m7-home:/home/agent-home \
  -v /home/agent/m7/probe.sh:/probe.sh:ro \
  -e HOME=/home/agent-home \
  -e GIT_AUTHOR_NAME=measure7 -e GIT_AUTHOR_EMAIL=measure7@local \
  -e GIT_COMMITTER_NAME=measure7 -e GIT_COMMITTER_EMAIL=measure7@local \
  -w /repo node:22 bash /probe.sh
```

Комірка 2 — одна змінна: змонтований **справжній** `$HOME` користувача `agent`, `ro`:

```
sudo -n -u agent docker run --rm --user 1002:1002 \
  -v /home/agent/hart:/repo \
  -v /home/agent:/home/agent:ro \
  -v /home/agent/m7/probe-cell2.sh:/probe2.sh:ro \
  -e HOME=/home/agent \
  -e GIT_AUTHOR_NAME=measure7 -e GIT_AUTHOR_EMAIL=measure7@local \
  -e GIT_COMMITTER_NAME=measure7 -e GIT_COMMITTER_EMAIL=measure7@local \
  -w /repo node:22 bash /probe2.sh
```

B3 — одна змінна проти B2: `-t` (термінал):

```
sudo -n -u agent docker run --rm -t --user 1002:1002 \
  -v /home/agent/hart:/repo -v /home/agent/m7-home:/home/agent-home \
  -e HOME=/home/agent-home -w /repo node:22 bash -c '…git push origin HEAD:refs/heads/probe/push-7-tty…'
```

### 3.1. Комірка 1 — інвентаризація й чотири прогони

```
=== 0. хто ми / де ми ===
6.8.0-139-generic
git version 2.39.5
uid=1002 gid=1002 groups=1002
HOME=/home/agent-home
HOME_WRITABLE
STDIN_NOT_TTY

=== 2. ІНВЕНТАРИЗАЦІЯ (промпт §2) — значень токенів не друкуємо ===
-- git remote -v --
origin	https://github.com/stjurik/flatcraft.git (fetch)
origin	https://github.com/stjurik/flatcraft.git (push)
-- ls -la $HOME/.ssh --
ls: cannot access '/home/agent-home/.ssh': No such file or directory
-- ls -la $HOME/.git-credentials --
ls: cannot access '/home/agent-home/.git-credentials': No such file or directory
-- ls -la $HOME/.gitconfig --
ls: cannot access '/home/agent-home/.gitconfig': No such file or directory
-- credential.helper --
exit=1
-- токен-змінні середовища (лише факт наявності) --
grep_exit=0 (1 = жодної такої змінної)
-- ssh-agent сокет --
SSH_AUTH_SOCK=<не задано>
```

⚠️ **Дефект мого власного харнесу, спійманий тут же.** Рядок `grep_exit=0` **нічого не означає**: код узято з
`env | grep … | sed …`, тобто це код `sed`, а не `grep`. Це рівно та пастка, про яку попереджає правило
«`cmd | head; echo $?` віддає код фільтра, а не команди» — і я в неї впав у першій же комірці, хоча в решті
рядків скрипта користувався `${PIPESTATUS[0]}`. Читати треба **за відсутністю надрукованих рядків**: `grep` не
вивів жодного. У комірці 2 це виправлено явно (`${PIPESTATUS[1]}` і лічильник рядків) — див. §3.3.

```
=== A. МЕРЕЖА БЕЗ КРЕДЕНШАЛА — контроль усього виміру ===
ОЧІКУВАННЯ ДО: exit 0, список ref'ів. Репо публічне, вихідного фільтра на A8 немає.
638d9090550ae198ab2faea8daf128cbdfedc369	refs/pull/94/head
b028069c90af95b816d1556d7ff19bcc6e29711f	refs/pull/95/head
922f2ff900bd90a451a30dfc8cdbaf38233ea09d	refs/pull/97/head
473fc55e6178ecf31978ea7d7082671d862288d4	refs/pull/98/head
4bab143b9d8eeba53ebbc10a9ac88a5fcdc87a47	refs/pull/99/head
exit=0

=== 3. підготовка worktree + порожній коміт ===
Preparing worktree (new branch 'probe/push-7')
HEAD is now at e382f58 chore(measure): М-2 — харнес виміру deny vs --dangerously-skip-permissions
exit=0
Can't find lefthook in PATH
Can't find lefthook in PATH
[probe/push-7 7c79206] probe: measurement 7
exit=0

=== B1. push у власну гілку, GIT_TERMINAL_PROMPT=0 — так, як зробить демон ===
fatal: could not read Username for 'https://github.com': terminal prompts disabled
exit=128

=== B2. КОНТРОЛЬ: те саме БЕЗ GIT_TERMINAL_PROMPT (одна змінна) ===
fatal: could not read Username for 'https://github.com': No such device or address
exit=128

=== C. push у main — ГОЛОВНЕ ПИТАННЯ. --dry-run, прибирати заборонено ===
fatal: could not read Username for 'https://github.com': terminal prompts disabled
exit=128

=== D1. fetch із worktree ===
From https://github.com/stjurik/flatcraft
 * branch            main       -> FETCH_HEAD
   30915d3..3a51217  main       -> origin/main
exit=0

=== D2. rebase на origin/main із worktree ===
Rebasing (1/3)dropping 0f6949c… -- patch contents already upstream
Rebasing (2/3)dropping e382f58… -- patch contents already upstream
Rebasing (3/3)Can't find lefthook in PATH
Successfully rebased and updated refs/heads/probe/push-7.
exit=0

=== D3. хук при СПРАВЖНЬОМУ коміті ===
-- чи існує .git/hooks/pre-commit --
-rwxr-xr-x 1 1002 1002 2780 Sep 17 09:40 /repo/.git/hooks/pre-commit
-- чи є lefthook у PATH --
which_exit=1
Can't find lefthook in PATH
Can't find lefthook in PATH
[probe/push-7 f693ecb] probe: real commit for hook check
 1 file changed, 1 insertion(+)
 create mode 100644 M7_PROBE.txt
exit=0

=== E. ПРИБИРАННЯ ===
Deleted branch probe/push-7 (was f693ecb).
-- локальні probe/* --
-- віддалені probe/* --
exit=0
-- worktree list --
/repo  e382f58 (detached HEAD)
```

### 3.2. B3 — та сама команда, що B2, плюс `-t`

```
=== B3. те саме, що B2, але з -t (одна змінна: термінал) ===
ОЧІКУВАННЯ ДО: STDIN_IS_TTY; git спитає Username і зависне до timeout -> exit 124.
STDIN_IS_TTY
Username for 'https://github.com': exit=124
```

**Читання пари B1/B2/B3.** Пара B1/B2, задумана як контроль зависання, його **не показала**: обидва прогони
впали за 128, бо в контейнері без `-t` термінала немає і git не має де спитати. Вони все ж розділили одну
змінну — **сигнатури різні**: `terminal prompts disabled` (git сам відмовився питати) проти
`No such device or address` (git спробував відкрити термінал і не зміг). Зависання показав лише B3, де термінал
є. Звідси твердження, яке тепер підперте виміром: **під реальними умовами демона (`docker run` без `-t`) `push`
зависнути з цієї причини не може; `GIT_TERMINAL_PROMPT=0` — підстраховка, а не несуча конструкція.** Без B3
робити це твердження було б не можна.

### 3.3. Комірка 2 — справжній `$HOME`, змонтований `ro`

```
=== 0. конфігурація комірки 2 ===
HOME=/home/agent
HOME_READONLY
STDIN_NOT_TTY

=== 2'. ІНВЕНТАРИЗАЦІЯ у справжньому $HOME ===
-- ls $HOME (лише імена) --
. .. .bash_logout .bashrc .cache .claude .claude-oauth-token .claude.json .claude.json.measure-bak
.claude.json.pre-m1 .config .gemini .local .npm .npmrc .profile .zshrc hart hart-wt m7 m7-home
-- $HOME/.ssh --
ls: cannot access '/home/agent/.ssh': No such file or directory
-- $HOME/.git-credentials --
ls: cannot access '/home/agent/.git-credentials': No such file or directory
-- $HOME/.gitconfig --
ls: cannot access '/home/agent/.gitconfig': No such file or directory
-- $HOME/.config/git --
ls: cannot access '/home/agent/.config/git': No such file or directory
-- $HOME/.config/gh --
ls: cannot access '/home/agent/.config/gh': No such file or directory
-- credential.helper --
helper_exit=1  (1 = не задано; це код git, не код пайпа)
-- токен-змінні: рахуємо рядки, код беремо з PIPESTATUS --
0
grep_exit=1  (1 = жодної такої змінної)

=== A'. контроль мережі у цій комірці ===
exit=0

=== B1'. push у власну гілку зі справжнім $HOME ===
fatal: could not read Username for 'https://github.com': terminal prompts disabled
exit=128

=== C'. push --dry-run у main зі справжнім $HOME ===
fatal: could not read Username for 'https://github.com': terminal prompts disabled
exit=128
```

**Навіщо була потрібна ця комірка.** Без неї відповідь на питання «чи має контейнер креденшал на запис» була б
**визначена монтуванням**, а не виміряна: чиста тека тривіально порожня. Комірка 2 змінює рівно одну змінну —
який `$HOME` змонтовано — і дає той самий результат. Тобто негатив належить середовищу, а не конфігурації
виміру. Побічно вона ж показує, що `$HOME` користувача `agent` містить креденшали **Claude** і **Gemini**
(`.claude-oauth-token`, `.claude.json`, `.gemini/`) — але **жодного git-креденшала**.

### 3.4. Хостові перевірки (з `T470`, не з контейнера)

```
$ gh api repos/stjurik/flatcraft --jq .permissions
{"admin":true,"maintain":true,"pull":true,"push":true,"triage":true}
exit=0
```

Це **контроль до наступного запиту**: 404 на `/protection` означав би або «захисту немає», або «немає прав
бачити». `admin:true` знімає другу гілку.

```
$ gh api repos/stjurik/flatcraft/branches/main/protection
{"required_status_checks":{"strict":false,"contexts":[
  "Install + lockfile check","Lint + format","Typecheck","Unit tests","Build",
  "Playwright e2e (web + api)","Python CAD worker (ruff + mypy + pytest)","Lint workflows",
  "Validate prod compose + Caddyfile","Ansible — syntax-check + ansible-lint"]},
 "required_signatures":{"enabled":false},
 "enforce_admins":{"enabled":false},
 "required_linear_history":{"enabled":false},
 "allow_force_pushes":{"enabled":false},
 "allow_deletions":{"enabled":false},
 "block_creations":{"enabled":false},
 "required_conversation_resolution":{"enabled":false},
 "lock_branch":{"enabled":false}}
exit=0

$ gh api repos/stjurik/flatcraft/branches/main/protection/required_pull_request_reviews
{"dismiss_stale_reviews":false,"require_code_owner_reviews":false,
 "require_last_push_approval":false,"required_approving_review_count":1}
exit=0

$ gh api repos/stjurik/flatcraft/rules/branches/main
[]
exit=0

$ gh api repos/stjurik/flatcraft/rulesets
[]
exit=0
```

Обидва механізми перевірені окремо, як і належить: класична branch protection і rulesets — різні речі, і репо
могло мати нуль першого при активному другому. Тут навпаки: **класична protection увімкнена, rulesets порожні.**

### 3.5. Лічильники `DOCKER-USER` — до і після прогонів

```
--- ДО ---
num   pkts bytes target     prot opt in      out
1     253K  900M RETURN     0    --  *       *      ctstate RELATED,ESTABLISHED
2        0     0 DROP       0    --  enp1s0  *
3      258 16428 RETURN     0    --  *       *

--- ПІСЛЯ ---
1     254K  900M RETURN     0    --  *       *      ctstate RELATED,ESTABLISHED
2        0     0 DROP       0    --  enp1s0  *
3      291 18320 RETURN     0    --  *       *
```

**Приріст на правилі 2 (`DROP`) — нуль.** Правило 1 (stateful RETURN) стоїть **перед** ним, тож зворотний трафік
контейнера повертається раніше, ніж доходить до DROP; сам DROP стосується лише трафіку, що **входить** з
`enp1s0`. Приріст +33 пакети на правилі 3 — це нові вихідні з'єднання прогонів. Тобто прогін A міряв мережу, а
не фільтр: жодного вихідного allowlist'а на A8 **не існує** (`ufw`: `DEFAULT_OUTPUT_POLICY="ACCEPT"`, вхідні
правила лише для tailnet і SSH з LAN).

---

## 4. Вимоги до образу Стадії 1 — доповнення до трьох із виміру №6

Сформульовані **після** прогону, кожна з дослівного рядка вище.

4. **Креденшал на запис треба внести явно — сьогодні його немає ніде.** Підстава: §3.1 і §3.3 — у чистому й у
   справжньому `$HOME` відсутні `.ssh`, `.git-credentials`, `.gitconfig`, `credential.helper` не задано,
   токен-змінних нема. Наслідок: `fetch`/`rebase` демон робить уже зараз, `push` — ні.
5. **`GIT_TERMINAL_PROMPT=0` лишається в конфігурації, але як підстраховка, не як захист від зависання.**
   Підстава: пара B1/B2 (обидва 128, без `-t` зависання неможливе) плюс B3 (`exit=124` з `-t`). Несуча
   конструкція тут — **відсутність `-t` у `docker run`**; її і треба зафіксувати як вимогу.
6. **`node_modules/.bin` має бути в `PATH` контейнера, інакше git-хуки — тихий no-op.** Підстава: §3.1 D3 —
   `.git/hooks/pre-commit` існує і виконується, `command -v lefthook` → `which_exit=1`, надруковано
   `Can't find lefthook in PATH`, і коміт **усе одно пройшов** (`exit=0`). Тобто в контейнері pre-commit не
   перевіряє ні ESLint, ні `tsc`, ні `prettier`, ні `ruff` — вимір №6 бачив цей рядок, але не перевіряв, чи
   коміт від нього залежить. Тепер перевірено: не залежить.
7. **`--user 1002:1002` підтверджено вдруге, вже на записі.** Підстава: після двох комірок із коміт-операціями
   `find /home/agent/hart -not -user agent | wc -l` → **0**.

---

## 5. Як перевірити очима

1. `gh api repos/stjurik/flatcraft/branches/main/protection --jq .enforce_admins.enabled` → **`false`**. Це і є
   дірка: адміністратор (тобто yurii і будь-який його токен) обходить усю решту рядків цієї відповіді.
2. `gh api repos/stjurik/flatcraft/rulesets` → **`[]`**. Другого механізму немає, тож усе тримається на першому.
3. `gh api repos/stjurik/flatcraft --jq .permissions` → `"admin":true` — доказ, що п.1 і п.2 не є артефактом
   браку прав.
4. У §3.1 прогони **B1** і **B2** відрізняються лише змінною `GIT_TERMINAL_PROMPT`, а їхні сигнатури різні:
   `terminal prompts disabled` проти `No such device or address`. Коди при цьому однакові — 128.
5. У §3.2 єдина відмінність від B2 — прапорець `-t`, і саме там з'являється `Username for 'https://github.com':`
   та `exit=124`.
6. У §3.5 рядок `2 0 0 DROP … enp1s0` має **однакові нулі** до і після прогонів, а рядок 3 виріс із 258 до 291.
7. На A8: `sudo find /home/agent/hart -not -user agent | wc -l` → **0**; `sudo -u agent git -C /home/agent/hart
branch --list 'probe/*'` → порожньо; `ls -d /tmp/wt-push /tmp/wt-push2` → обидва `No such file or directory`.
8. На A8: `getent group docker` → `docker:x:988:runner,agent` — `agent` у docker-групі (див. §6 п.7 і знахідку Б).
9. На A8: `sudo -u agent sudo -n -l` → `sudo: a password is required` — sudo в `agent` справді немає.
10. `npx prettier --check docs/promts/inputs/measurement-7-push.md` → без скарг.

---

## 6. Чого цей прогін НЕ доводить

1. **Що `push` неможливий після видачі креденшала.** Виміряно рівно одне: креденшала **зараз** немає, тож
   `push` падає на автентифікації. Що станеться з ключем — не міряв ніхто.
2. **Що `main` захищений від демона.** Прогін C **не дійшов** до перевірки прав: обидві комірки впали на
   креденшалі. Те, що protection існує, відоме з `gh api`, а не з push'а. `--dry-run`, який повернув би 0,
   теж означав би лише «механічної лінії не видно», а не «справжній push пройшов би».
3. **Що deploy key не зможе запушити в `main`.** Це **висновок, а не спостереження**: `enforce_admins:false`
   звільняє адміністраторів, а deploy key адміністратором не є, тож protection на нього мала б поширюватись.
   Перевірити це без створення ключа неможливо — а створювати ключ прогону заборонено.
4. **Що результат переживе перехід репо в private** (ADR-038 прийнято, виконання відкладено — OQ-30). Прогін A
   зелений саме тому, що репо **публічне**: `ls-remote` і `fetch` по HTTPS не потребують підпису. Після private
   read-шлях теж потребуватиме креденшала, і розділ A треба **переміряти**.
5. **Що вихідна мережа лишиться відкритою.** Виміряно стан на 2026-09-18: allowlist'а немає. Коли він з'явиться
   (`docs/19` §6), прогін A перестане бути лише контролем і його треба повторити.
6. **Що `pnpm install` у контейнері проходить** — як і у вимірі №6, не перевірялось.
7. **Що docker-група справді дає `agent` root на хості.** Членство перевірено (`getent group docker`),
   експлуатація — **ні** і свідомо: це відома властивість docker-групи, а не знахідка виміру.

---

## 6.1. Дві окремі знахідки, ширші за сам вимір

### Знахідка А — «allowlist вихідної мережі» описаний як чинна властивість, а існує тільки в планах

`CLAUDE.md` §6.1 (рядок 250) описує середовище автономного прогону **теперішнім часом**:

> Середовище: контейнер, користувач `agent` без sudo, окремий git-worktree на задачу, **allowlist вихідної
> мережі**, `--dangerously-skip-permissions` **дозволений тільки тут**

Виміряно (§3.5): вихідного фільтра на A8 немає — `DEFAULT_OUTPUT_POLICY="ACCEPT"`, `DOCKER-USER` містить лише
вхідний `DROP` з нульовим лічильником.

**Але формулювання знахідки треба звузити проти первинного.** Перевірка показала, що `docs/19` §6 **не** заявляє
allowlist готовим: розділ називається «**Що ви НЕ ставите руками**» і перелічує роботу master-run'а, тобто
allowlist там стоїть як **беклог**, коректно. Хибне твердження одне, не два, і воно в `CLAUDE.md`.

Тому це **не** третій випадок класу «конфігурація, якої немає в git, не існує» (deny-правила `docs/16` §1 і
cron дайджеста `docs/11` §11): ті два були позначені як зроблені. Тут інший, суміжний клас — **документ описує
майбутнє середовище теперішнім часом**, через що читач `CLAUDE.md` вважає властивість чинною. Чи зараховувати
його до «правила трьох» — рішення yurii; мій рахунок класу «конфігурація без git» лишається **2**, а цей випадок
я записую як перший у власному класі. Мінімальна дія — привести §6.1 до майбутнього часу або позначити
allowlist як заплановане; сам `CLAUDE.md` цей прогін правити не має права.

### Знахідка Б — `agent` без sudo, але в docker-групі

`CLAUDE.md` §6.1 обіцяє «користувач `agent` **без sudo**». Це буквально правда:

```
$ sudo -u agent sudo -n -l
sudo: a password is required
```

Але:

```
$ getent group docker
docker:x:988:runner,agent
$ id agent
uid=1002(agent) gid=1002(agent) groups=1002(agent),100(users),988(docker)
```

Членство в docker-групі загальновідомо еквівалентне root на хості (контейнер може змонтувати `/` хоста і
писати туди від імені root). Я цього **не перевіряв практично** — саме тому воно стоїть у §6 п.7 як недоведене.
Але для ADR-039 §2, де ізоляція контейнера є несучою передумовою автономності, факт членства сам по собі
достатній, щоб поставити питання: демон, який може запустити `docker run -v /:/host`, ізольований лише доти,
доки сам цього не робить. Без docker-групи він, утім, не зможе запускати контейнери взагалі — тобто це не
недогляд, а нерозв'язана суперечність постановки. Вона заслуговує рядка в `docs/20`.

---

## 6.2. Розвилка класу A — який креденшал дати демону

Питання до yurii. **Дефолту при мовчанні немає**, бо створення креденшала в чужому акаунті незворотне.
Таблиця промпту доповнена двома фактами прогону: `enforce_admins:false` і відсутність rulesets.

| #     | Варіант                                                            | Плюс                                                                          | Мінус                                                                                                                                                                                                                                                                    | Наслідок для Стадії 1                                                               |
| ----- | ------------------------------------------------------------------ | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------- |
| а     | SSH deploy key з правом запису, змонтований `ro`                   | Не залежить від акаунта yurii; відкликається одним кліком; без TTL            | Не звужується до гілок. **Доповнення прогону:** deploy key не є адміністратором, тож `enforce_admins:false` його **не** звільняє — `main` для нього закритий protection'ом (**висновок, не вимір**, §6 п.3)                                                              | Демон пише в будь-яку гілку, але `main` прикритий не лише відсутністю ключа         |
| б     | Fine-grained PAT, `contents: write`, через env                     | Найтонше з трьох по правах; має термін дії; видно в аудиті                    | **Доповнення прогону, що перевертає оцінку:** PAT живе в акаунті yurii, а yurii — адміністратор, і `enforce_admins:false` означає, що **його токен обходить PR, апрув і всі 10 checks**. Тобто найтонший на папері варіант — єдиний, що дає демону прямий запис у `main` | Найбільша реальна поверхня з трьох, попри найвужчі scope'и                          |
| в ★   | Deploy key + воркфлоу, що відкриває draft PR на push у гілку `ai/` | Демон фізично не має прав на PR і merge; успадковує закритий `main` з (а)     | Треба воркфлоу, а `.github/**` — заборонений шлях: окрема іменна згода                                                                                                                                                                                                   | Демон віддає роботу, але не може її прийняти                                        |
| **г** | **(нове) спершу `enforce_admins:true`, потім будь-що з (а)–(в)**   | Знімає дірку, яка робить (б) небезпечним, і не залежить від вибору креденшала | Зачіпає самого yurii: його власні merge теж почнуть вимагати зелених checks                                                                                                                                                                                              | Єдиний варіант, після якого «що тримає демона від `main`» має відповідь, не порожню |

★ лишається за (в). Але прогін додає до нього передумову: **доки `enforce_admins:false`, вибір між (а), (б) і
(в) вирішує не те, куди демон може писати, а лише те, чиїм іменем.** Варіант (г) не заміняє решту — він їх
уможливлює.

Шість полів на кожне питання — у тілі PR.

---

## 7. Готовий рядок для таблиці вимірів `docs/20`

Внести тому, хто мерджитиме `claude/agent-orchestration-planning-w06nh9`:

```markdown
| 7 | **`push` із контейнера** | ⚠️ **не може: креденшала на запис немає ніде** (ні в чистому, ні в справжньому `$HOME`, ні в `credential.helper`, ні в env) — `fetch`/`rebase`/`commit` працюють, `push` падає 128 на автентифікації. Зависання без `GIT_TERMINAL_PROMPT=0` **неможливе без `-t`** (B1/B2 → 128; B3 з `-t` → 124). `main` прикритий класичною protection (PR + 1 апрув + 10 checks), але **`enforce_admins:false`** — адмінський токен обходить усе; rulesets порожні. Хуки в контейнері — no-op (`lefthook` не в `PATH`), коміт проходить попри це |
```
