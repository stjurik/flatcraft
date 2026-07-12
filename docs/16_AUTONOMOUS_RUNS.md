# 16. Autonomous Runs — headless-запуск промптів з docs/15

> Як запускати промпти з `docs/15_LLM_PROMPTS.md` автономно (без діалогу) і паралельно.
> Інструменти: Claude Code headless (`claude -p`), git worktree, `tools/scripts/autorun.sh`.

## 0. Головний принцип: автономність ≠ безконтрольність

Промпти 15 мають gate «покажи план → дочекайся OK». В автономному режимі цей gate **переноситься з чату на PR-review**:

- агент працює без пауз, але фінал — **draft PR**, ніколи не merge;
- план агент пише не в чат, а першим commit'ом у `PLAN.md` гілки;
- ручна точка контролю одна: yurii читає diff PR і мерджить (або коментує і перезапускає).

Це реалізовано «автономним хедером» (§3), який додається перед текстом будь-якого A/B-промпту.

---

## 1. Одноразова підготовка (WSL, ~/hart)

```bash
claude --version          # Claude Code встановлений і залогінений
gh auth status            # gh працює (для gh pr create)
git -C ~/hart status      # чистий main
mkdir -p ~/hart/docs/promts/autorun ~/hart-wt ~/hart-logs
```

1. **Розкласти промпти по файлах:** вміст кожного код-блоку з `docs/15_LLM_PROMPTS.md` → окремий файл `docs/promts/autorun/{a1,a2,a3,b1,b2,b3,b4,b5}.md`. C-промпти файлів не потребують (§6).
2. **Створити хедер** `docs/promts/autorun/_autonomous-header.md` (текст у §3).
3. **Обмеження прав** — у `~/hart/.claude/settings.json` додати deny-правила, що механічно захищають інваріанти CLAUDE.md §6 навіть при автономному агенті:

```json
{
  "permissions": {
    "deny": [
      "Edit(packages/db/migrations/**)",
      "Edit(infra/**)",
      "Edit(CLAUDE.md)",
      "Bash(pnpm discord:apply:*)",
      "Bash(git push --force:*)",
      "Bash(docker:*)"
    ]
  }
}
```

> deny має пріоритет над allow — навіть якщо агент попросить, дозволу не буде.

---

## 2. Запуск одного промпту вручну (без скрипта)

```bash
cd ~/hart
cat docs/promts/autorun/_autonomous-header.md docs/promts/autorun/a1.md | claude -p \
  --model opus \
  --permission-mode acceptEdits \
  --allowedTools "Read,Glob,Grep,Edit,Write,Bash(git:*),Bash(gh pr create:*),Bash(gh pr view:*),Bash(pnpm:*),Bash(uv:*)" \
  --max-turns 200 \
  --output-format stream-json --verbose \
  | tee ~/hart-logs/a1-$(date +%F).jsonl
```

Пояснення:

| Флаг                                    | Навіщо                                                                          |
| --------------------------------------- | ------------------------------------------------------------------------------- |
| `-p` (print)                            | headless: один прогін без інтерактиву, вихід у stdout                           |
| `--permission-mode acceptEdits`         | правки файлів без підтверджень; Bash — лише з allowlist                         |
| `--allowedTools "…"`                    | білий список: файлові тули + git/gh/pnpm/uv за префіксом. Все інше — блокується |
| `--max-turns 200`                       | стоп-кран від зациклення (A-промпти ~50-100 turns, B — більше)                  |
| `--output-format stream-json --verbose` | повний лог дій у jsonl — можна грепати постфактум                               |
| `--model opus\|sonnet\|haiku`           | маршрутизація за рівнем A/B/C (15 §0)                                           |

**Не** використовуй `--dangerously-skip-permissions` на робочій машині — allowlist + deny з §1 дає ту саму автономність без ризику. Skip-permissions допустимий лише в одноразовому контейнері.

Альтернатива для «запустив і забув»: прапорець `--background` — сесія стартує як background-агент, друкує session ID і одразу повертає термінал; стан дивись через `claude agents`.

---

## 3. Автономний хедер (вміст `_autonomous-header.md`)

```
РЕЖИМ: АВТОНОМНИЙ HEADLESS-ПРОГІН. Це доповнення МОДИФІКУЄ промпт нижче:

1. Кроки «покажи ПЛАН і дочекайся OK від yurii» НЕ виконувати як паузу.
   Замість цього: запиши план у файл PLAN.md у корені гілки ПЕРШИМ commit'ом.
2. Працюй без пауз до завершення всіх деліверейблів промпту.
3. Фінал — ЗАВЖДИ: gh pr create --draft --fill (саме --draft). НЕ мерджити,
   НЕ пушити в main, НЕ починати наступний PR фази.
4. Якщо зустрів блокер, суперечність з ADR/інваріантом або рішення, яке в промпті
   позначене «узгодь з yurii» — НЕ вгадуй: запиши суть у BLOCKED.md, закоміть,
   створи draft PR з префіксом [BLOCKED] і заверши роботу.
5. Тести: перед створенням PR прожени релевантні (pnpm test / pytest — за AGENTS.md).
   Якщо червоні і полагодити в межах scope не вдалось — це блокер (див. п.4).
6. Незмінні заборони (CLAUDE.md §6): не генерувати drizzle-міграції (підготуй
   schema.ts і опиши міграцію у PR description), не чіпати docker-compose,
   infra/ansible, CLAUDE.md §1-12, не запускати discord:apply. Нові залежності —
   лише в межах existing workspace, перелічи їх окремим списком у PR description.
```

---

## 4. Паралельність: git worktree — кожному агенту свою копію

Два агенти в одному каталозі = гонки за git index і файли. Ізоляція:

```bash
cd ~/hart
git fetch origin main
git worktree add ~/hart-wt/a1 -b docs/phase-3-3-observability origin/main
git worktree add ~/hart-wt/c1 -b chore/c1-inventory origin/main

# у кожному worktree — власні залежності (node_modules не шаруться):
(cd ~/hart-wt/a1 && pnpm install --frozen-lockfile && cd workers/cad && uv sync)

# запуск паралельно (окремі вікна tmux або &):
(cd ~/hart-wt/a1 && cat ... | claude -p ... | tee ~/hart-logs/a1.jsonl) &
```

Після merge PR: `git worktree remove ~/hart-wt/a1 && git branch -d …`.

> Кожен worktree — це +1-2 ГБ (node_modules + venv) і ~2 хв на install. Паралель має сенс лише для реально незалежних завдань — див. матрицю нижче.

### 4.1. Матриця хвиль: що можна паралельно, а що ні

| Хвиля | Запуски                                 | Паралельно?                | Чому                                                                                                                                                                                  |
| ----- | --------------------------------------- | -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0     | C1 + C2                                 | ✅ так                     | read-only аналіз, пишуть різні файли у `docs/promts/inputs/`                                                                                                                          |
| 1     | A1 + A2                                 | ⚠️ можна, з застереженням  | обидва додають секції у `03_DECISIONS.md` і `02_ROADMAP.md` → rebase-конфлікт гарантований, але тривіальний (append-only секції). Якщо не хочеш конфліктів — послідовно: A1, потім A2 |
| —     | **GATE: yurii читає і мерджить ADR-PR** | ручна точка                | без затверджених ADR-032/033 B-хвиля не стартує                                                                                                                                       |
| 2а    | B1 → потім B2 ∥ B5                      | B2∥B5 ✅                   | B1 — фундамент (events/exports у БД, чіпає db+types+api+worker). B2 (Sentry) і B5 (digest) після нього незалежні: різні зони                                                          |
| 2б    | B3                                      | після B1, ❌ не поряд з B1 | обидва чіпають apps/api і schema.ts                                                                                                                                                   |
| 3     | A3, потім B4 (×6 послідовно)            | B4 тільки послідовно       | кожен PR B4 мігрує один шаблон і має бути змерджений до наступного (registry-контракт еволюціонує)                                                                                    |

Правило вибору: **паралелити можна те, що не перетинається по файлах і не залежить по змісту.** Все інше — черга.

---

## 5. Runner-скрипт

`tools/scripts/autorun.sh` робить усе з §2+§4 однією командою:

```bash
tools/scripts/autorun.sh a1 docs/phase-3-3-observability opus
tools/scripts/autorun.sh b1 feat/observability-events sonnet
tools/scripts/autorun.sh c1 chore/c1-inventory haiku
```

(створює worktree зі свіжого origin/main → ставить залежності → headless-прогін з хедером і логом → друкує, де дивитись результат). Джерело — `tools/scripts/autorun.sh`.

Моніторинг під час прогону:

```bash
tail -f ~/hart-logs/a1-*.jsonl | grep -o '"type":"[^"]*"'   # пульс подій
cd ~/hart-wt/a1 && git log --oneline                        # що вже закомічено
```

---

## 6. C-промпти: автономно і дешево

C-рівню не потрібен worktree і права на запис у код:

```bash
cd ~/hart
claude -p "$(cat docs/promts/autorun/c2-wrapper.md)" \
  --model haiku \
  --permission-mode acceptEdits \
  --allowedTools "Read,Glob,Grep,Write(docs/promts/inputs/**)" \
  --max-turns 60
```

Де `c2-wrapper.md` — це C-промпт з 15 плюс один рядок зверху: «Сам збери вхідні дані (grep по apps/, workers/) і збережи результат у docs/promts/inputs/c2-log-audit.md». Write обмежений одним каталогом — агент фізично не може зачепити код.

---

## 7. Після прогону: чекліст приймання (5 хвилин на PR)

1. `gh pr list --draft` — PR існує? Якщо `[BLOCKED]` — читай BLOCKED.md, це очікувана поведінка, не фейл.
2. CI зелений? (lefthook/CI самі проженуть lint+tests).
3. Diff відповідає scope промпту? Червоні прапорці: зміни поза переліченими у промпті каталогами, згенеровані міграції, правки CLAUDE.md.
4. `PLAN.md` у гілці збігається з тим, що реально зроблено?
5. Правки потрібні? — два шляхи:
   - дрібні: коментар собі + `claude --resume` у тому ж worktree («врахуй коментарі у PR №N і онови гілку»);
   - концептуальні: закрити PR, поправити промпт у `docs/promts/autorun/`, перезапустити (промпт — це код; фейл прогону = баг промпту).
6. Merge (squash) → `git worktree remove` → наступна хвиля.

---

## 8. Типові фейли і що з ними робити

| Симптом                                   | Причина                                           | Дія                                                                                                    |
| ----------------------------------------- | ------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| Прогін обірвався по `--max-turns`         | scope завеликий або зациклення на червоному тесті | подивись лог; або `--resume` («продовж, фініш — draft PR»), або розбий промпт на два                   |
| PR нема, коміти є                         | агент не мав дозволу на `gh` або впав до фіналу   | `cd worktree && gh pr create --draft --fill` руками; додай `Bash(gh pr create:*)` в allowlist          |
| Rebase-конфлікт у 03_DECISIONS/02_ROADMAP | паралельні A-прогони (очікувано, §4.1)            | конфлікт append-секцій вирішується за 2 хв руками; або серіалізуй хвилю 1                              |
| Агент «завис» на питанні                  | у headless нема кому відповісти                   | це баг промпту: правило «не питай — пиши BLOCKED.md» вже у хедері; перевір, що хедер справді доклеївся |
| Тести червоні у PR                        | хедер п.5 дозволяє [BLOCKED]-PR                   | читай BLOCKED.md — часто це цінна знахідка, а не сміття                                                |

---

## 9. Межі автономності (свідомо ручне)

- **Merge будь-якого PR** — тільки yurii.
- **Drizzle-міграції** — руками за PR description (CLAUDE.md §6).
- **A4 (щомісячний huddle)** — це діалог, не headless; ганяй у звичайному чаті.
- **Деплой** — release-флоу без змін (`docs/08_DEPLOYMENT.md`).
