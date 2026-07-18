[MASTER RUN 3 — AI bugfix flow на GitHub Actions: issue → triage → fix → review]

МЕТА
Конвеєр дрібних виправлень без локальних сесій: yurii описує баг/покращення
в issue і ставить лейбл → сильна модель робить ТРІАЖ (чи можна виправити без
зміни архітектури; план; рівень моделі; опитування за потреби) → після
approve-лейбла модель потрібного рівня імплементує фікс draft-PR'ом → сильна
модель рев'юїть результат проти плану й інваріантів → yurii перевіряє готовий
продукт і мержить. НІЩО не мержиться автоматично.

РЕЖИМ АВТОНОМІЇ (патерн docs/16)

- БАЗА ГІЛКИ (перший крок, до правок): гілка fix/issue-{N} відгалужується ЛИШЕ
  від свіжого origin/main. Перевір механічно, інакше squash затягне чуже в main:
  git fetch origin main
  test "$(git merge-base HEAD origin/main)" = "$(git rev-parse origin/main)" \
   || { echo "STOP: невірна база"; exit 1; }
  Не збіглось → СТОП (git checkout -B fix/issue-{N} origin/main, повтори).
- Фінал draft PR — завжди з явним --base main (gh pr create --draft ... --base main).
- Без пауз; план — у PR description; фінал — 1 draft PR. НІКОЛИ не мержиш.
- Нічого не вигадуй: невідоме — перевір; ≥2 варіанти — розділ «Опитування»
  (питання / варіанти / ★рекомендація / дефолт-при-merge).
- «Як перевірити очима» — обов'язковий розділ PR (тут: тестовий прогін флоу).
- ЯВНА ЗГОДА yurii: у межах ЦЬОГО завдання дозволено створювати файли у
  .github/workflows/ та .github/ISSUE_TEMPLATE/ (CLAUDE.md §6).
- Гілка feat/ai-bugfix-flow, Conventional Commits, нуль нових npm/py залежностей.

КОНТЕКСТ (прочитати)
CLAUDE.md (§2, §5-8), AGENTS.md, docs/16_AUTONOMOUS_RUNS.md, docs/14 (§1.2,
§4.4 — цикл digest→issue живить цей флоу), docs/04_RISKS.md, наявні
.github/workflows/\*.yml (стиль, pinned versions), docs/03_DECISIONS.md
(формат ADR). Актуальну документацію anthropics/claude-code-action@v1 —
прочитай через WebFetch (README + docs/usage.md): точний синтаксис inputs
(prompt, claude_args, allowed_tools), тригери, permissions. НЕ вигадуй
параметрів action — тільки з офіційних доків.

РІШЕННЯ YURII (зафіксовані, не переглядати)

- Авторизація: CLAUDE_CODE_OAUTH_TOKEN (підписка; GitHub Secret, створює yurii).
- Тригер: лейбл ai-fix на issue (лейбли ставить лише власник — вбудований гейт
  проти prompt-injection з чужих issue у публічному репо).
- Двостадійність: triage-коментар → yurii ставить ai-approved → fix.
- Роутинг моделей: triage/review — найсильніша доступна; fix — за рекомендацією
  тріажу (sonnet за замовчуванням, haiku для тривіального).

ДЕЛІВЕРАБЛИ
A. ADR-035 «AI bugfix flow (GitHub Actions)» у docs/03_DECISIONS.md:
рішення (лейбл-гейт; двостадійність; OAuth-токен; model routing; guardrails)
у форматі ALT/CHOICE/RATIONALE/CONSEQUENCES. Окремий підрозділ SECURITY:
issue-текст = untrusted input (відомий клас атак на CI-агентів);
мітигації: (1) запуск ЛИШЕ з лейбла (права на лейбли = write-access),
(2) permissions workflow мінімальні (contents/pull-requests/issues: write,
БЕЗ secrets поза токеном), (3) pinned версія action (@v1 + конкретний SHA),
(4) заборонені шляхи для fix-стадії (див. C), (5) concurrency: 1 run,
(6) ліміт ходів (max turns) проти runaway-витрат ліміту підписки.
B. .github/workflows/ai-triage.yml — on: issues [labeled: ai-fix]:
claude-code-action, СИЛЬНА модель. Промпт тріажу (вбудуй у workflow):
прочитати issue + CLAUDE.md §7 + релевантні ADR + docs/promts/inputs/
c1-template-inventory.md (відомі розбіжності шаблонів — багато «багів»
уже там); класифікувати:

- LOCAL-FIX → коментар: root-cause гіпотеза, план фікса (файли у скоупі,
  які тести додати — кожен фікс ЗОБОВ'ЯЗАНИЙ додати регресійний тест,
  культура 2.10.e), рекомендована модель, «Опитування» за потреби;
  лейбл ai-plan-ready.
- ARCHITECTURAL (зачіпає інваріанти §7/ADR, спільні шари, схему БД,
  infra) → коментар «потребує архітектурного треку» з посиланням на
  відповідний розділ docs/14/15; лейбл ai-architectural; СТОП — це
  свідомий захист від костилів.
- NEED-INFO → 1-3 конкретні питання yurii; лейбл ai-need-info.
  C. .github/workflows/ai-fix.yml — on: issues [labeled: ai-approved]:
  імплементація за планом з triage-коментаря, TDD, гілка fix/issue-{N},
  draft PR (лінк на issue, «Як перевірити очима», «Опитування» якщо
  лишились варіанти). ЗАБОРОНЕНІ шляхи (у промпті + перевір як step):
  packages/db/src/migrations/, infra/, .github/workflows/, CLAUDE.md,
  docs/03_DECISIONS.md — якщо фікс їх потребує → коментар + лейбл
  ai-architectural + СТОП без PR.
  D. .github/workflows/ai-review.yml — on: PR від fix-стадії (ready або
  лейбл ai-review): СИЛЬНА модель порівнює diff проти плану з issue +
  інваріантів CLAUDE.md §7/§13 → коментар-вердикт: ✅ відповідає /
  ⚠️ зауваження (список) / ❌ відхилити з причиною. Merge — тільки yurii.
  E. .github/ISSUE_TEMPLATE/bug_report.yml + improvement.yml — форми під
  нетехнічний опис: Де (URL/шаблон) / Кроки / Очікував / Побачив /
  Скріншот / Пристрій+браузер. UA-мовою.
  F. docs/17_AI_BUGFIX_FLOW.md — інструкція yurii: як писати issue, що
  означають лейбли (ai-fix → ai-plan-ready → ai-approved → PR →
  ai-architectural/ai-need-info), як читати triage-план і опитування,
  правило «телеметрія → issue»: пункти недільного digest і Sentry-issues
  заводяться цим самим флоу. Межа скоупу: ARCHITECTURAL-випадки йдуть у
  звичайний трек docs/14/15, НЕ фіксяться поспіхом.
  G. Цей файл — включити у PR (конвенція docs/promts).

МАНУАЛЬНІ КРОКИ YURII (чеклист у PR description)

1. Локально: claude setup-token → скопіювати токен.
2. GitHub → Settings → Secrets and variables → Actions → New secret:
   CLAUDE_CODE_OAUTH_TOKEN.
3. Створити лейбли: ai-fix, ai-plan-ready, ai-approved, ai-architectural,
   ai-need-info (кольори на розсуд; можна gh label create — дай команди).
4. Merge цього PR.
5. ТЕСТОВИЙ ПРОГІН: завести дріб'язковий справжній issue (з твого списку
   багів) → лейбл ai-fix → пройти повний цикл до merge фікса. Це acceptance.

ТЕСТИ

- actionlint (або аналог, без нових deps — можна npx) на workflows.
- yamllint-рівень: prettier по yml зелений.
- Секретів у файлах нуль (тільки ${{ secrets.* }}).

ФІНАЛ: PR-таблиця + консолідоване опитування + чеклист вище. STOP.
