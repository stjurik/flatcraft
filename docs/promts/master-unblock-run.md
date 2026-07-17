[MASTER RUN 5 — розблокування: merge-борги housekeeping + Phase 3.4 до повного закриття]

ЯВНА ЗГОДА YURII (виняток цього run'у — і ТІЛЬКИ його)

1. Дозволено МЕРЖИТИ перелічені нижче PR (звичайне правило «мержить лише
   yurii» тимчасово знято — інструкція yurii від 2026-07-14).
2. Дозволено згенерувати drizzle-міграцію export_feedback — це і є «явна
   інструкція» за CLAUDE.md §6.
   Дозвіл діє ЛИШЕ на кроки нижче. Будь-яка дія поза списком — STOP.

GUARD-ПРАВИЛА

- Verify-then-act: перед кожним merge — gh pr checks (дочекатись завершення);
  червоний CI або конфлікт → STOP з логом, нічого не «дотискати».
- Force-push заборонено (для оновлення гілки — git merge origin/main,
  НЕ rebase).
- Нічого не вигадуй; після кожного кроку — статус одним рядком.
- Працюєш один: yurii не запускає паралельних сесій.

КРОКИ

0. git checkout main && git pull. Перевір: git status показує НЕЗАКОМІЧЕНУ
   правку CLAUDE.md (§12-посилання, внесена архітектором, погоджена у #74).
   Якщо її нема — STOP. НЕ чіпай її до кроку 2.
1. PR #74 (housekeeping): CI зелений → gh pr merge 74 --squash --delete-branch.
2. git pull, потім закоміть готову правку: git add CLAUDE.md &&
   git commit -m "docs: sync CLAUDE.md §12 (housekeeping #74)" && git push.
   (Файл уже відредаговано архітектором — ти ЛИШЕ комітиш; сам CLAUDE.md
   не редагуй.)
3. Stale-дублікати: gh pr close 28 29 30 31 --comment
   "Absorbed by #32, #37-#44 — див. housekeeping audit (PR #74)".
4. Phase 3.4 — міграція (явна інструкція, див. згоду):
   a. git checkout feat/phase-3-4-qr-feedback && git pull;
   git merge origin/main (конфлікт поза docs → STOP).
   b. pnpm --filter @flatcraft/db generate.
   c. ІНСПЕКЦІЯ згенерованого SQL: дозволено ЛИШЕ CREATE TABLE
   export_feedback (+ індекси, + FK на exports). Будь-який DROP або
   ALTER інших таблиць → STOP і покажи SQL повністю.
   d. pnpm --filter @flatcraft/db migrate — якщо локальний Postgres
   недоступний (docker під deny) — пропусти: CI int-тести
   (testcontainers) перевірять міграцію.
   e. Тести задіяних workspace зелені → git add packages/db →
   commit "chore(db): drizzle migration export_feedback (Phase 3.4,
   explicit instruction)" → push.
5. PR #69: зняти draft → дочекатись ПОВНОГО зеленого CI (int-тести мають
   пройти з міграцією) → merge --squash --delete-branch.
6. Issue #70 (QR-URL follow-up) — виконай за scope/DoD з самого issue:
   гілка fix/issue-70 від свіжого origin/main (merge-base guard з docs/16);
   QR у PDF → {BASE_URL}/f/{export_id}; regen DXF/PDF-снапшотів — ОКРЕМИМ
   комітом з поясненням «свідома зміна QR-URL, детермінізм збережено»;
   pytest зелені → draft PR --base main → CI зелений → зняти draft →
   merge --squash → перевір, що #70 закрився (closes-лінк), інакше закрий
   з коментарем.
7. Docs-закриття фази 3.4 — гілка docs/phase-3-4-progress-log:
   a. docs/13: повний запис «Feature 3.4 — QR-фідбек з виробництва» нагору
   (факти ЛИШЕ з merged #69/#70 + PR-обговорень: дати, SHA, рішення
   Q1-Q5, інваріанти: 404 на невідомий export_id, rate-limit, подія
   feedback_submitted, digest-секція deviation; снапшоти QR — свідомий
   regen у follow-up).
   b. docs/04: R-01 mitigation 4 → реалізовано (дата, PR #69/#70).
   c. docs/02: секція Phase 3.4 → done з датою.
   d. Включи цей файл (docs/promts/master-unblock-run.md) у PR.
   e. PR → CI зелений → merge --squash.
8. Ротація CLAUDE.md §13 — тобі заборонена: у фінальному звіті дай ГОТОВИЙ
   текст (новий снапшот-рядок про 3.4; milestone-запис 3.4 зверху списку,
   видалити найстаріший 3.1; footer-дата) — застосує архітектор.
9. ФІНАЛЬНИЙ ЗВІТ: таблиця крок → результат (SHA merge-комітів); стан:
   відкритих PR/issues з переліку — нуль; що лишилось yurii/архітектору
   (лише §13-текст + недільний digest-acceptance). STOP.
