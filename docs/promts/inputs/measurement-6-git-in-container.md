# Вимір №6 — git усередині контейнера агента

**Дата:** 2026-09-17 · **Машина:** A8 (`a8`, Ubuntu, kernel 6.8.0-139) · **Користувач хоста:** `agent` (uid 1002)
**Роль:** Розвідник (`docs/15` §0) · **Питання:** чи може демон Стадії 1 робити `worktree add`, `commit`, `push` у контейнері

> Куди мав лягти цей файл: постановка казала «записати в `docs/20` вимір №6 як закритий». `docs/20_OPEN_DECISIONS.md` живе
> лише в гілці `claude/agent-orchestration-planning-w06nh9` і в `main` його немає, тож внесення його у гілку,
> авторизовану під два рядки ADR-038, було б зміною значно більшою за авторизовану. Оркестратор визнав приписку
> власним дефектом; протокол лягає сюди, готовий рядок для таблиці `docs/20` — у §7.

---

## 1. Передбачення, записане ДО прогону

Дослівно з `docs/20`, «вимір №6» (не змінювалось після прогону):

> у контейнері зламаний не `prepare`, а git загалом; окремо `git commit` впаде ще й через відсутню identity, бо
> `user.email`/`user.name` зазвичай живуть у глобальному конфігу, який недоступний.

І ланцюг двох гіпотез, теж записаний до прогону:

> 1. …спрацювала перевірка **dubious ownership**: тека репо належить іншому UID, ніж користувач контейнера.
> 2. Лікування падає. `git config --global --add …` — це **запис** у `~/.gitconfig`… Вони **не альтернативні, а
>    послідовні**.

---

## 2. Таблиця результатів

| Що                                              | Очікування ДО                                   | Факт                                                                                                                        | Контроль був?                                                           | Вердикт                       |
| ----------------------------------------------- | ----------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- | ----------------------------- |
| Гіпотеза 1 — чужий власник                      | підтверджується непрямо                         | **підтверджена дослівно** під UID ≠ власника: `fatal: detected dubious ownership in repository at '/repo'`, 128             | так: `git status` **до** будь-якого `safe.directory`, у трьох UID       | ✅ причина сигнатури М-3      |
| Гіпотеза 2 — `$HOME` недоступний                | «послідовна» з першою: ремонту нема куди писати | **існує, але окремо і в іншій конфігурації.** Під `--user 1002:1002` `HOME=/`, `HOME_READONLY`, `git config --global` → 255 | так: під root `HOME=/root`, `HOME_WRITABLE`, той самий `git config` → 0 | ⚠️ гіпотеза жива, ланцюг — ні |
| «Вони послідовні»                               | так                                             | **ні — незалежні.** Яку з двох дістанеш, вирішує вибір UID; збіг UID знімає першу і створює другу                           | пара UID 1000 / 1002 / root                                             | ❌ передбачення хибне         |
| `git status` у репо                             | (вважалось зламаним «git загалом»)              | **працює**, exit 0, без жодного `safe.directory` — коли UID = власник                                                       | той самий крок у трьох UID                                              | ✅ працює за умови            |
| `git worktree add -b`                           | не перевірялось ніколи                          | **працює**, exit 0, гілка створюється                                                                                       | —                                                                       | ✅                            |
| `git commit` **без** identity                   | впаде через відсутню identity                   | **128**: `fatal: unable to auto-detect email address (got 'unknown@5cfc80feedf3.(none)')`                                   | **так** — пара з наступним рядком                                       | ✅ передбачення підтверджене  |
| `git commit` **з** `-c user.email/-c user.name` | (контроль)                                      | **0**, коміт створено: `[probe/gitcheck 2abe85c] probe2`                                                                    | це і є контроль                                                         | ✅ причина саме в identity    |
| Вірність відтворення М-3                        | (не передбачалось)                              | під `--user 1000:1000` сигнатура М-3 відтворена **дослівно**, разом із командою, що падала                                  | три UID; критерій за уточненням 1                                       | ✅ міряв той самий контейнер  |
| Побічне: чистота репо після прогону             | (не передбачалось)                              | контейнер-root лишає в репо `agent` **15 файлів, які `agent` не може видалити**                                             | `find -not -user agent` до і після                                      | ⚠️ окрема вимога до образу    |

---

## 3. Дослівні виводи

Процедура — сім кроків `docs/20`. Два свідомі відхилення, обидва названі до прогону:

- **`2-bis`** — `git status` **до** будь-якого `safe.directory`. У прописаному порядку `safe.directory` додається на
  кроці 3, а `status` перевіряється на кроці 4, тобто вже після вимкнення перевірки власності: гіпотеза 1 у такому
  порядку не читається в принципі.
- **`git_exit` окремо від `pipe_exit`.** Чотири з семи рядків процедури мають вигляд `git … | head -3; echo "exit=$?"`,
  а це код `head`, не `git`. Справжній беру з `PIPESTATUS[0]`; друкую обидва, щоб різниця була видима.

### 3.1. Варіант B — `--user 1002:1002` (UID = власник репо). Кандидат на конфігурацію Стадії 1

```
docker run --rm --user 1002:1002 <монтування М-3-fix> -w /repo node:22 bash /probe.sh
```

```
=== 0. хто ми / де ми ===
-- uname --
Linux 6.8.0-139-generic x86_64
-- git --version --
git version 2.39.5
-- власник /repo --
UNKNOWN:UNKNOWN 1002:1002 775 /repo
UNKNOWN:UNKNOWN 1002:1002 775 /repo/.git

=== 1. id; HOME; ls -ld $HOME ===
uid=1002 gid=1002 groups=1002
HOME=/
drwxr-xr-x 1 root root 4096 Sep 17 09:42 /

=== 2. $HOME записуваний? ===
HOME_READONLY

=== 2-bis. git -C /repo status ДО будь-якого safe.directory  (КОНТРОЛЬ власності) ===
HEAD detached at FETCH_HEAD
nothing to commit, working tree clean
git_exit=0 pipe_exit=0

=== 3. git config --global --add safe.directory /repo ===
error: could not lock config file //.gitconfig: Permission denied
exit=255

=== 4. git -C /repo status ===
HEAD detached at FETCH_HEAD
nothing to commit, working tree clean
git_exit=0 pipe_exit=0

=== 5. git -C /repo worktree add /tmp/wt-probe -b probe/gitcheck ===
Preparing worktree (new branch 'probe/gitcheck')
HEAD is now at e382f58 chore(measure): М-2 — харнес виміру deny vs --dangerously-skip-permissions
git_exit=0 pipe_exit=0

=== 6. git -C /tmp/wt-probe commit --allow-empty -m probe   (БЕЗ identity) ===
Omit --global to set the identity only in this repository.

fatal: unable to auto-detect email address (got 'unknown@5cfc80feedf3.(none)')
git_exit=128 pipe_exit=128

=== 7. те саме З явною identity   (КОНТРОЛЬ до кроку 6) ===
Can't find lefthook in PATH
Can't find lefthook in PATH
[probe/gitcheck 2abe85c] probe2
git_exit=0 pipe_exit=0

=== 8. довідково: що лишилось у дереві ===
/repo          e382f58 (detached HEAD)
/tmp/wt-probe  2abe85c [probe/gitcheck]
-- глобальний конфіг, якщо він з'явився --
ls: cannot access '//.gitconfig': No such file or directory
cat: //.gitconfig: No such file or directory
```

**Читання.** Усе, що потрібно демону, працює: `status` 0, `worktree add` 0, `commit` з явною identity 0. Не працює
рівно двоє, і обидва не блокують: `git config --global` (бо `HOME=/` на читання — але глобальний конфіг демону не
потрібен) і `commit` без identity.

### 3.2. Варіант A — дефолтний користувач образу (root)

```
docker run --rm <монтування М-3-fix> -w /repo node:22 bash /probe.sh
```

```
=== 1. id; HOME; ls -ld $HOME ===
uid=0(root) gid=0(root) groups=0(root)
HOME=/root
drwx------ 2 root root 4096 Aug 24 00:00 /root

=== 2. $HOME записуваний? ===
HOME_WRITABLE

=== 2-bis. git -C /repo status ДО будь-якого safe.directory  (КОНТРОЛЬ власності) ===
fatal: detected dubious ownership in repository at '/repo'
To add an exception for this directory, call:

git_exit=128 pipe_exit=128

=== 3. git config --global --add safe.directory /repo ===
exit=0

=== 4. git -C /repo status ===
HEAD detached at FETCH_HEAD
nothing to commit, working tree clean
git_exit=0 pipe_exit=0

=== 5. git -C /repo worktree add /tmp/wt-probe -b probe/gitcheck ===
Preparing worktree (new branch 'probe/gitcheck')
HEAD is now at e382f58 chore(measure): М-2 — харнес виміру deny vs --dangerously-skip-permissions
git_exit=0 pipe_exit=0

=== 6. git -C /tmp/wt-probe commit --allow-empty -m probe   (БЕЗ identity) ===
fatal: unable to auto-detect email address (got 'root@f3762b9f7a81.(none)')
git_exit=128 pipe_exit=128

=== 7. те саме З явною identity   (КОНТРОЛЬ до кроку 6) ===
[probe/gitcheck d44446a] probe2
git_exit=0 pipe_exit=0

-- глобальний конфіг, якщо він з'явився --
-rw-r--r-- 1 root root 26 Sep 17 09:36 /root/.gitconfig
[safe]
	directory = /repo
```

**Читання.** Це варіант, у якому **обидві гіпотези розділяються чисто**: власність ламає `status` (крок 2-bis, 128),
`$HOME` натомість записуваний і ремонт проходить (крок 3, 0). Тобто гіпотеза 2 до сигнатури М-3 відношення не має.

Ціна цього варіанта — окрема, і вона дорожча за саму зручність:

```
--- прибирання в репо на хості (від імені agent) ---
error: failed to delete '.git/worktrees/wt-probe': Permission denied
error: cannot delete branch 'probe/gitcheck' used by worktree at '/tmp/wt-probe'
```

```
--- усі 15 root-файлів, які лишив контейнер ---
2026-09-17 12:36 root /home/agent/hart/.git/logs/refs/heads/probe/gitcheck
2026-09-17 12:36 root /home/agent/hart/.git/objects/d4/4446a22c70528423cc64ae9010ab65394e43ff
2026-09-17 12:36 root /home/agent/hart/.git/refs/heads/probe/gitcheck
2026-09-17 12:36 root /home/agent/hart/.git/worktrees/wt-probe/index
…(15 усього)
```

Знімалось лише `sudo rm`. Тобто **контейнер-root псує репозиторій `agent` необоротно з-під самого `agent`** — демон,
який так працює, ламає своє дерево на першому ж коміті і не може це прибрати.

### 3.3. Варіант C — `--user 1000:1000` (користувач `node` образу). Це і є контейнер М-3

Критерій уточнення 1: перш ніж читати результат, треба довести, що міряється той самий контейнер. Варіант B
відтворив механізм, але не число (`255` проти `128` у М-3), варіант A — ані числа, ані шляху. Форензика вказала на
третій UID: у репо **нуль** файлів, не належних `agent`, датованих 09-16 — отже контейнер М-3 не був root; а
`node_modules` — `agent:agent`, тож і не 1002 з записом. Лишався `1000` (`node` в образі `node:22`).

```
docker run --rm --user 1000:1000 -v /home/agent/hart:/repo -w /repo node:22 \
  bash -c 'cd /repo && ./node_modules/.bin/lefthook install'
```

```
uid=1000(node) gid=1000(node) groups=1000(node)
HOME=/home/node
===
│  > git rev-parse --path-format=absolute --show-toplevel --git-path hooks --git-path info --git-dir
│    fatal: detected dubious ownership in repository at '/repo'
│    To add an exception for this directory, call:
│    git config --global --add safe.directory /repo
│
│  Error: exit status 128
lefthook_exit=1
```

**Це дослівна сигнатура М-3** — і вона показує, що її читали неправильно, включно з моїм власним звітом М-3:

| Як читалось у `docs/20` і в звіті М-3                                     | Що насправді                                                                                      |
| ------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `git config --global --add safe.directory /repo → Error: exit status 128` | впала команда **`git rev-parse`**, не `git config`                                                |
| «`128` на ньому означає, що git не може записати `~/.gitconfig`»          | `128` — код git при **dubious ownership**; `$HOME=/home/node` тут записуваний, і `git config` → 0 |
| дві гіпотези «послідовні»                                                 | у цьому UID друга не настає взагалі                                                               |

Рядок `git config --global --add safe.directory /repo` у тому повідомленні — **порада, яку git сам друкує у тексті
своєї помилки**, а не команда, що впала. `Error: exit status 128` — формат Go (`exec.ExitError`) від `lefthook`,
який обгортає `git rev-parse` і віддає її код. Обидва рядки належать одному повідомленню git, і склеювання їх у
«впав `git config`» і породило гіпотезу 2 як частину ланцюга.

Додатково під цим UID: `lefthook install` після ручного `safe.directory` падає інакше —
`Error: could not replace the hook: remove /repo/.git/hooks/pre-push: permission denied` (1000 не має права на
`.git/hooks`, що належить 1002 з правами 775 — група не помагає). Тобто UID 1000 хибний двічі.

### 3.4. Побічний факт про `pnpm`, який М-3 лишив без пояснення

Під `--user 1002:1002` `lefthook install` **проходить** (`sync hooks: ✔️ (pre-commit, pre-push)`, exit 0), а
`pnpm run prepare` усе одно падає — але вже на іншому:

```
  code: 'EACCES',
  syscall: 'mkdir',
  path: '/.cache/node/corepack/v1'
```

Це та сама причина, що й `git config --global` — `HOME=/` — але інший симптом і інший інструмент. Тобто `exit=1` на
`pnpm install`, який М-3 бачив у **кожному** прогоні, має два різні джерела залежно від UID, і для Стадії 1 лікується
одним і тим самим: записуваний `$HOME`.

---

## 4. Вимоги до образу Стадії 1 — тільки те, що випливає з виміру

Сформульовані **після** прогону, кожна з дослівного рядка вище.

1. **UID контейнера = власник примонтованого репо** (тут `1002:1002`). Підстава: §3.2 крок 2-bis (128 при
   розбіжності) і §3.3 (та сама 128 плюс відмова на `.git/hooks`). Варіант «root» відкидається не через 128, а через
   §3.2: він лишає в репо файли, яких `agent` не видалить.
   _Альтернатива «`safe.directory` на етапі побудови»_ лікує лише читання: у §3.3 після ручного `safe.directory`
   `lefthook` усе одно впав на праві до `.git/hooks`. Тобто вона **недостатня** сама по собі — вимога залишається на UID.
2. **`$HOME` існує і записуваний.** Підстава: §3.1 крок 3 (`could not lock config file //.gitconfig`, 255) і §3.4
   (`EACCES mkdir /.cache/node/corepack/v1`). Для самих git-операцій це не потрібно, для `pnpm` — обов'язково.
3. **git-identity задається явно**, репо-локально або через `GIT_AUTHOR_*`/`GIT_COMMITTER_*`. Підстава: пара §3.1
   кроки 6 і 7 — без identity 128, з identity 0, за інших рівних. Це єдина умова, яку **не** знімає правильний UID.

---

## 5. Як перевірити очима

1. `git -C ~/hart log --oneline -3` → зверху `#109`, під ним `#110`; обидва змерджені squash.
2. `git show origin/main:docs/promts/inputs/agy-stats.md | grep -c '^| 2026-09-16'` → **2**. Обидва рядки вижили:
   рев'ю Стадії 1 і контрольний зонд OQ-23.
3. `sed -n '48p' docs/03_DECISIONS.md` → у колонці статусу «Accepted; виконання (D.1) відкладено 2026-09-17 — OQ-30»;
   слів `Rejected`/`Superseded` немає.
4. `grep -n 'Без private весь трек A8' docs/03_DECISIONS.md` → **нічого не знайдено**; замість цього
   `grep -n 'Без private неможливий саме' docs/03_DECISIONS.md` дає один рядок.
5. `git diff origin/main --numstat -- docs/03_DECISIONS.md` → один файл, і `git diff origin/main -U0 -- docs/03_DECISIONS.md | grep -c '^-[^-]'` → **2**: більше жодного рядка у файлі не змінено.
6. У §3.3 цього файлу рядок `> git rev-parse --path-format=absolute …` стоїть **над** `fatal: detected dubious
ownership` — видно, що падала `rev-parse`, а не `git config`.
7. У §3.1 кроки 6 і 7 відрізняються **лише** наявністю `-c user.email/-c user.name`, а коди — 128 і 0.
8. На A8: `sudo find /home/agent/hart -not -user agent | wc -l` → **0**. Репо після прогону чисте.
9. На A8: `sudo -u agent git -C /home/agent/hart branch --list 'probe/*'` → порожньо; `ls -d /tmp/wt-probe` → немає.
10. `npx prettier --check docs/03_DECISIONS.md docs/promts/inputs/measurement-6-git-in-container.md` → без скарг.

---

## 6. Чого цей прогін НЕ доводить

1. **Що `push` працює.** Не мірявся свідомо: потребує креденшала і вихідної мережі — два додаткові невідомі.
   Чотири кроки до нього зелені, тож `push` тепер перевіряється окремо.
2. **Що `pnpm install` у контейнері проходить до кінця.** Виміряно лише, що `lefthook install` під правильним UID
   проходить, а падіння переїжджає на кеш `corepack`. Повний `pnpm install --frozen-lockfile` під записуваним `$HOME`
   не проганявся.
3. **Що конфігурація §4 достатня для демона.** Виміряні три git-операції з семи, які демон робить. `fetch`,
   `rebase`, `push`, робота з хуками при **коміті** (а не при `install`) — поза цим прогоном.
4. **Що `--user 1000:1000` — єдине можливе джерело сигнатури М-3.** Форензика (нуль не-`agent` файлів від 09-16)
   виключає root і вказує на 1000; це сильний, але непрямий доказ — самого запуску М-3 у логах не збереглось.
5. **Що вимога «UID = власник» переживе інші монтування.** Міряно на одному репо з одним власником. Якщо Стадія 1
   монтуватиме ще й теки з іншими власниками, питання відкривається заново.
6. **Що прогін щось говорить про хуки при коміті.** `Can't find lefthook in PATH` у §3.1 крок 7 — це попередження
   `.git/hooks/pre-commit`, тобто хук **спрацював, але не знайшов бінарника**: у контейнері `node_modules/.bin` не в
   `PATH`. Коміт усе одно пройшов, тож для цього виміру це шум — але для демона, який робить справжні коміти, це
   окреме питання.

---

## 7. Готовий рядок для таблиці вимірів `docs/20`

Внести тому, хто мерджитиме `claude/agent-orchestration-planning-w06nh9`:

```markdown
| 6 | **Git-операції всередині контейнера** | ✅ **працюють за умови:** UID = власник репо + явна git-identity. Гіпотеза «чужий власник» підтверджена, «$HOME» — окрема, не ланцюг; сигнатура М-3 читалась хибно (падала `git rev-parse`, не `git config`). `push` не мірявся |
```

---

_Прогонів контейнера: 6 (варіант A, варіант B зі стороннім станом, варіант B чистий, lefthook під 1002, lefthook під
1000 з `safe.directory`, lefthook під 1000 без нього). Викликів `agy`: 0 — прогін нічого від Gemini не потребував,
вікно OQ-35 лишається 2/10._
