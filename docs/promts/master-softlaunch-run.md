[MASTER RUN — critical path до публічного soft-launch: 3 автономні work-packages]

РЕЖИМ АВТОНОМІЇ (пріоритет над усім)

- Працюй БЕЗ пауз на погодження. Gate «план → OK» перенесено на PR-review
  (патерн docs/16_AUTONOMOUS_RUNS.md): перший commit кожної гілки — PLAN.md
  з планом пакета; фінал пакета — DRAFT PR. НІКОЛИ не мержиш.
- НІЧОГО не вигадуй. Якщо факту бракує або є ≥2 варіанти: обери задокументований
  дефолт (CLAUDE.md, ADR, docs/11/14) і ЗАНЕСИ питання у розділ «Питання до
  yurii» у PR description. Hard-STOP лише якщо: стан репо розходиться з описаним;
  локальні перевірки червоні і фікс поза скоупом; потрібна міграція drizzle;
  потрібен файл поза скоупом пакета.
- Кожен PR description ОБОВ'ЯЗКОВО містить розділ «Як перевірити очима» —
  покрокова перевірка ГОТОВОГО ПРОДУКТУ для нетехнічного рев'юера (URL → що
  побачити → що клікнути). yurii оцінює результат, не код.
- Головний вектор (перевіряй кожне рішення): масштабованість (нічого
  sheet-metal-специфічного у спільні шари), ефективність (нуль нових важких
  залежностей; RAM-бюджет MS21 4 GB), самовдосконалення (мета всього запуску —
  жива телеметрія і ритм digest → issues).
- Гілки незалежні, КОЖНА від origin/main (не стекати — урок Phase 3.3 з
  авто-закритим #57). Пакети виконуй ПОСЛІДОВНО: 1 → 2 → 3.
- Перед кожним PR: pnpm lint + typecheck + test (задіяні workspace) зелені.
- Conventional Commits. Force-push заборонено.

ОБОВ'ЯЗКОВИЙ КОНТЕКСТ (прочитай до старту)
CLAUDE.md (§6-8, §13), AGENTS.md, ADR-032, docs/11_OBSERVABILITY.md,
docs/14_ARCHITECTURE_EVOLUTION.md (§4-6), docs/08_DEPLOYMENT.md,
docs/promts/phase-3-3-b-activation.md, docs/02_ROADMAP.md (Phase 5.3-5.5, 5.10),
docs/04_RISKS.md (R-04, R-05, R-09).

ОЧІКУВАНИЙ СТАН (розходження = STOP): Phase 3.3 у main (CLAUDE.md §13 містить
Feature 3.3); в infra/ НЕМАЄ umami; у дереві untracked autorun-файли.

──────────────────────────────────────────────
WP1 — autorun-тулінг (гілка docs/autonomous-runs)

Включити: docs/16_AUTONOMOUS_RUNS.md, docs/promts/autorun/,
tools/scripts/autorun.sh, .claude/settings.json,
docs/promts/phase-3-3-b-activation.md, docs/promts/master-softlaunch-run.md
(цей файл). Порожній .github/workflows/ai-cloud-developer.yml — ВИДАЛИТИ.
Нічого не редагувати. У PR description: перелік deny-правил settings.json
(для рев'ю) + «Як перевірити очима»: git status чистий після merge.

──────────────────────────────────────────────
WP2 — активація телеметрії + launch-runbook (гілка infra/phase-3-3b-umami-deploy)

Виконай ПОВНІСТЮ docs/promts/phase-3-3-b-activation.md (деліверабли A-G;
його ПОЧАТОК-розділ ігноруй — діє режим автономії цього master-промпту).
ДОДАТКОВО у docs/08_DEPLOYMENT.md — розділ «Go-live checklist (soft-launch)»:
перемикання бойового домену hart.crimea.ua на стек (DNS + Caddy vhost),
smoke-тести після перемикання (5 пунктів: головна, каталог, студія, експорт
DXF+PDF, подія в Umami), KPI першого тижня (з Roadmap: ≥10 користувачів
з експортом, p95 export <5с — де дивитись: digest + Umami), rollback-крок.
«Як перевірити очима» = мануальний чеклист активації (7 кроків з промпту)

- недільний acceptance (digest у Discord, події в Umami, тест-помилка у Sentry).

──────────────────────────────────────────────
WP3 — legal-мінімум перед публічним запуском (гілка feat/legal-minimum)

Roadmap 5.3-5.4. Створити:
A. apps/web: сторінки /privacy та /terms (UA основна + EN, патерн локалізації —
як /about; дизайн-токени docs/10). Зміст МАЄ відповідати реальності коду:
мінімум PII (події без email/IP, session_hash з добовим salt — ADR-032);
Umami self-hosted cookie-less (без трекінг-cookies); Sentry (технічні звіти
про помилки, PII фільтрується); дані — ДЦ в Україні (ADR-011), шифровані
бекапи у Cloudflare R2 (поза Україною); донати — добровільний внесок на ЗСУ
напряму у фонди, платформа коштів не приймає (формулювання R-05); креслення
рекомендаційні, перевірка перед виробництвом на користувачеві (R-09);
best-effort uptime без SLA. КОЖНА сторінка — помітний блок:
«Драфт. Не є юридичною консультацією; фінальна версія — після рев'ю юристом
(Roadmap 5.4)». НЕ вигадуй юридичних деталей поза цим переліком.
B. Cookie-нотис: Umami cookie-less → повноцінний banner НЕ потрібен; додай
стислий рядок про відсутність трекінг-cookies у /privacy і згадку в Footer
(«Без трекінг-cookies»). Жодних consent-бібліотек.
C. Footer (@flatcraft/ui або SiteLinks): лінки Privacy / Terms.
D. docs/02_ROADMAP.md: 5.3-5.4 → позначити виконаними-як-драфт (з приміткою
про юриста); 5.5 (DSR endpoints) → явно «відкладено до Phase 3 auth —
без акаунтів даних для export/delete немає».
E. Тести: e2e — обидві сторінки рендеряться (UA+EN), лінки з Footer працюють,
console-clean; unit за потреби.
«Як перевірити очима»: відкрити /privacy і /terms на телефоні й десктопі,
перевірити 8 змістовних пунктів (список у PR description), клікнути лінки
з футера.

──────────────────────────────────────────────
ФІНАЛ RUN'У
Підсумкове повідомлення: таблиця 3 PR (номер, гілка, статус checks, зібрані
«Питання до yurii»), консолідований мануальний чеклист yurii у порядку
виконання (merge WP1 → merge WP2 → 7 кроків активації → недільний acceptance →
merge WP3 → рішення про go-live за runbook'ом docs/08). STOP.
