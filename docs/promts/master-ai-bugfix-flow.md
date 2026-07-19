[MASTER RUN 9 — AI bugfix flow v2: issue → тріаж (Actions) → фікс (Actions) →
мультиагентне рев'ю Claude+agy (локально) → merge yurii]

МЕТА
Конвеєр дрібних виправлень: yurii описує баг у issue і ставить лейбл →
Claude-тріаж у GitHub Actions (чи можна виправити без зміни архітектури;
план; модель) → після approve-лейбла Claude-фікс draft-PR'ом (з обов'язковим
регресійним тестом) → ЛОКАЛЬНЕ мультиагентне рев'ю: agy/Gemini дає незалежний
вердикт І генерує додаткові тест-кейси; Claude-оркестратор верифікує та
оформлює тести — БЕЗ доступу до архітектурних файлів → merge yurii.
НІЩО не мержиться автоматично.

РОЛІ (ADR-036; вендорна диверсифікація)
| Роль | Хто | Де | Права на запис |
| Тріаж | Claude сильна | Actions (label ai-fix) | лише коментар+лейбл |
| Будівельник | Claude Sonnet | Actions (label ai-approved) | код фікса + тести, ЗАБОРОНЕНІ шляхи нижче |
| Рев'юер | agy/Gemini Pro | локально | НУЛЬ (read-only, вихід у inputs/) |
| Тест-інженер | agy/Gemini Pro | локально | НУЛЬ (пропонує кейси текстом) |
| Оркестратор рев'ю | Claude (свіжа сесія) | локально | ЛИШЕ тест-файли у гілці фікса |
| Гейти | yurii | — | merge, лейбли |

ПРАВИЛА agy (ДОЗВОЛИ НЕ РОЗШИРЮЄМО — свідомо, для збору статистики проблем)

- Чинні правила без змін: headless `agy -p`; файлова передача diff (stdin
  не працює); БЕЗ bash; запис лише у docs/promts/inputs/; git status ПІСЛЯ
  кожного виклику, стороння зміна → git restore + інцидент у лог.
- НОВЕ — журнал статистики docs/promts/inputs/agy-stats.md: після КОЖНОГО
  виклику agy оркестратор дописує рядок: дата | задача | модель agy |
  результат (ok/scope-creep/timeout/auth) | вердикт підтверджений? (для
  рев'ю) | кейсів прийнято/відхилено (для тестів). Це джерело даних для
  майбутнього рішення про worktree-ізоляцію і CI-роль agy (v3, після A8).

РЕЖИМ АВТОНОМІЇ SETUP-RUN'У (патерн docs/16)
Гілка feat/ai-bugfix-flow від origin/main (merge-base guard); draft PR;
план у description; «Опитування» (★ + дефолт-при-merge); «Як перевірити
очима»; НЕ мержити; оновити issue #78. ЯВНА ЗГОДА yurii: створення файлів
у .github/workflows/ та .github/ISSUE_TEMPLATE/ (§6). Нуль нових залежностей.

КОНТЕКСТ SETUP-RUN'У
CLAUDE.md (§2, §5-8, §13), AGENTS.md, docs/16, docs/15 §0 (ролі), docs/14
§4.4, docs/04_RISKS, наявні .github/workflows/\*.yml (стиль, pinned),
docs/promts/agy-orchestration-recommendations.md (файлова передача, no-bash),
docs/promts/inputs/c1-template-inventory.md, формат ADR у docs/03 (індекс:
ADR-035 «Зарезервовано» — цей run його займає). Актуальні доки
anthropics/claude-code-action@v1 — через WebFetch, параметри НЕ вигадувати.

ДЕЛІВЕРАБЛИ SETUP-RUN'У
A. ADR-035 «AI bugfix flow v2» у docs/03 (+індекс): рішення у форматі
ALT/CHOICE/RATIONALE/CONSEQUENCES:

1.  лейбл-гейт (ai-fix, лейбли = write-access) — захист від prompt-injection;
2.  двостадійність тріаж→approve→фікс;
3.  рев'ю ЛОКАЛЬНЕ мультиагентне (Claude+agy), НЕ в Actions — бо agy-квоти
    прив'язані до локального Google-логіна, а дублювати рев'ю Claude'ом
    у CI = подвійна витрата квоти без вендорної диверсифікації; v3-тригер:
    private repo + A8 self-hosted runner → тріаж/рев'ю переїздять на agy у CI;
4.  agy без розширення дозволів + журнал agy-stats (дані для v3-рішення);
5.  SECURITY: issue-текст = untrusted input; мітигації: лейбл-гейт,
    мінімальні permissions workflow, pinned action SHA, заборонені шляхи,
    concurrency 1, max turns.
    B. .github/workflows/ai-triage.yml — on: issues [labeled: ai-fix]:
    claude-code-action, сильна модель. Вбудований промпт тріажу: прочитати
    issue + CLAUDE.md §7 + релевантні ADR + c1-template-inventory (відомі
    дрейфи шаблонів); класифікація:

- LOCAL-FIX → коментар: root-cause гіпотеза, план (файли у скоупі, які
  регресійні тести додати — обов'язково, культура 2.10.e), рекомендована
  модель фікса, «Опитування» за потреби → лейбл ai-plan-ready;
- ARCHITECTURAL (інваріанти §7/ADR, спільні шари, схема БД, infra,
  Registry-зона під час Run 7) → коментар з посиланням на трек
  docs/02 → лейбл ai-architectural, СТОП — захист від костилів;
- NEED-INFO → 1-3 питання → лейбл ai-need-info.
  C. .github/workflows/ai-fix.yml — on: issues [labeled: ai-approved]:
  імплементація ЗА ПЛАНОМ з тріаж-коментаря, TDD, гілка fix/issue-{N}
  (merge-base guard кроком workflow), draft PR --base main (лінк issue,
  «Як перевірити очима», «Опитування»). ЗАБОРОНЕНІ ШЛЯХИ (промпт + окремий
  verification-step, що валить job при порушенні):
  packages/db/src/migrations/**, infra/**, .github/**, CLAUDE.md,
  docs/03_DECISIONS.md, docs/12_TEMPLATE_CONTRACT.md, packages/db/src/schema.ts,
  DXF/PDF-снапшоти (workers/cad/tests/snapshots/**). Потрібен заборонений
  шлях → коментар + ai-architectural + СТОП без PR. Наприкінці — коментар
  у PR: «готово до локального рев'ю: docs/promts/ai-review-local.md».
  D. `.github/ISSUE_TEMPLATE/bug_report.yml` + `improvement.yml` — UA-форми під
  нетехнічний опис: Де (URL/шаблон) / Кроки / Очікував / Побачив /
  Скріншот / Пристрій.
  E. docs/promts/ai-review-local.md — ПЕРЕЮЗАБЕЛЬНИЙ промпт мультиагентного
  рев'ю (запускає yurii однією командою на кожен ai-fix PR):
  «Свіжа Claude-сесія, оркеструєш перевірку PR #N. Код фікса НЕ правиш;
  писати можеш ЛИШЕ тест-файли (`*.test.ts` / `*.test.tsx` / `*.spec.ts` /
  `workers/cad/tests/**`) у гілку фікса. Кроки:

1.  gh pr diff N > /tmp-файл у репо-корені (файлова передача).
2.  agy-РЕВ'Ю: agy читає diff + issue + план тріажу → вердикт ✅/⚠️/❌
    (відповідність плану, інваріанти §7, регресійний тест присутній і
    осмислений, зачеплені ділянки) → inputs/review-issue-N.md.
    Опублікувати ДОСЛІВНО коментарем «Gemini Reviewer (unedited)».
3.  agy-ТЕСТ-ІНЖЕНЕР (окремий виклик): за diff'ом і схемами параметрів
    запропонувати 5-10 додаткових кейсів для зачепленої ділянки
    (граничні значення, negative cases) з очікуваннями →
    inputs/testcases-issue-N.md. ВЕРИФІКУЙ кожен кейс проти
    схем/валідаторів (verify-then-write); осмислені — оформи кодом
    у гілку фікса окремим комітом test(issue-N): additional cases
    (Gemini-proposed, Claude-verified); відхилені — перелічи з причиною
    у коментарі. Тести мають ПРОЙТИ; кейс, що падає = знахідка бага →
    коментар у PR + STOP (не «підганяй» тест під поведінку).
4.  git status після кожного agy-виклику; журнал agy-stats.md.
5.  Підсумковий коментар: вердикт agy + прийнято/відхилено кейсів +
    твоя незгода окремо (якщо є). Merge — yurii.»
    F. docs/17_AI_BUGFIX_FLOW.md — інструкція yurii: життєвий цикл лейблів
    (ai-fix → ai-plan-ready → ai-approved → PR → локальне рев'ю → merge),
    як читати тріаж-план і опитування, правило «digest/Sentry-пункт →
    issue → ai-fix», межа скоупу (ARCHITECTURAL → звичайний трек), розділ
    «Конфлікт з Run 7»: поки йде Registry-міграція, фікси у файлах студій/
    шаблонів тріаж зобов'язаний класифікувати ARCHITECTURAL (уникнути
    зустрічних правок).
    G. Цей файл — включити у PR.

МАНУАЛЬНІ КРОКИ YURII (чеклист у PR description + issue #78)

1. claude setup-token → GitHub Secret CLAUDE_CODE_OAUTH_TOKEN.
2. gh label create: ai-fix, ai-plan-ready, ai-approved, ai-architectural,
   ai-need-info (готові команди у PR).
3. Merge setup-PR.
4. ACCEPTANCE — повний цикл на РЕАЛЬНОМУ дрібному базі з твого списку:
   issue за формою → ai-fix → прочитати план → ai-approved → дочекатись
   draft PR → запустити ai-review-local.md → прочитати вердикт agy +
   тест-звіт → merge → перевірити фікс очима на staging.

ТЕСТИ SETUP-RUN'У
actionlint (npx) по workflows; prettier зелений; нуль секретів у файлах
(лише ${{ secrets.* }}); verification-step заборонених шляхів має unit-прогін
(скрипт з тестовим diff'ом).

ФІНАЛ: PR-таблиця + консолідоване «Опитування» + чеклист yurii. STOP.
