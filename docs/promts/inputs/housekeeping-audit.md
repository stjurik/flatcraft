# WP1 — Аудит: docs housekeeping (master-run 4)

> Вхід для WP2-WP5 цього run'у. Кожен рядок — перевірений git/gh-факт
> (verify-then-write), джерело вказано explicitly. Дата аудиту: 2026-07-17.

## 1. Доля PR #69 (QR-фідбек) і issue #70

| Що | Факт | Джерело |
| --- | --- | --- |
| PR #69 | **OPEN / DRAFT**, НЕ merged. `mergedAt: null`. HARD-STOP на ручній drizzle-міграції (`export_feedback` таблиця) — сам PR це документує у власному описі. | `gh pr view 69 --json state,mergedAt` |
| Issue #70 | **OPEN**, НЕ closed. Follow-up (QR URL → `/f/{export_id}` у PDF) навіть не розпочато — залежить від merge #69. | `gh issue view 70 --json state,closedAt` |
| docs/04 R-01 mitigation 4 | Досі "v1.1: API «report deviation» …" — без позначки ✅, бо не merged. | `docs/04_RISKS.md` поточний вміст на main |

**Висновок:** Phase 3.4 (QR-фідбек) на 2026-07-17 **не в main**. Форма/API/схема існують лише на гілці `feat/phase-3-4-qr-feedback` (PR #69, draft). WP4/WP5.A з майстер-промпту (умовні на "якщо WP1 підтвердив merge") **НЕ виконуються** — умова хибна. Це не «частково», а «ще не розпочато на main».

## 2. ADR-027

| Крок | Факт | Джерело |
| --- | --- | --- |
| Чи існував текст | **Так**, повний текст (343 рядки, 7 рішень з ALT/CHOICE/RATIONALE/CONSEQUENCES) закомічено `90f1639 docs(adr): додати ADR-027 — Products як preset базового шаблону` (2026-06-22). | `git show 90f1639 -- docs/03_DECISIONS.md` |
| Чи це PR "1" з Phase 3.0 | Так — це саме комміт з гілки `docs/phase-3-architecture` = **PR #28** "docs: Phase 3.0 architecture — ADR-027 + Roadmap + previews". | `git log --all --contains 90f1639` |
| **Чи "втрачено при merge"?** | **Ні.** PR #28 **ніколи не мержився** — досі `OPEN`, `isDraft:false`, `mergeable:UNKNOWN`, останнє оновлення 2026-06-22. Текст не зникав з main — він просто ніколи туди не потрапляв через цей PR. | `gh pr view 28 --json state,isDraft,mergeable,updatedAt` |
| Чи ADR-027 все ж є на main іншим шляхом | **Ні.** `docs/03_DECISIONS.md` на main іде ADR-026 → ADR-028 напряму (номер пропущено). | `git show origin/main:docs/03_DECISIONS.md \| grep '^## ADR-'` |
| **Чи Phase 3.0 (Products Catalog) сама реалізація зроблена?** | **Так, повністю**, але **не через PR #28-31** (усі 4 лишились OPEN/stale, дата останнього руху 2026-06-22) — а через окрему серію merged PR, що почалась з #32 і фактично поглинула/переробила зміст #29 (data model)/#30 (catalog toggle)/#31 (studio mode prop): PR #32 (Phase 3.0 PR 5, merged 2026-06-23) вже містить `TemplateStudio mode='part'` та посилання на catalog toggle як готові передумови. Далі #37, #38, #39, #40, #41, #42, #43, #44 (всі merged 2026-06-23) — products, enclosed_shelf, catalog "Виріб" flow. `products` drizzle-таблиця, `packages/types/src/products/*`, `apps/api/src/routes/products.ts`, `apps/web/src/app/products/[slug]/page.tsx` — усе присутнє на main. | `git ls-tree -r origin/main --name-only \| grep products`; `gh pr list --state merged --search "Phase 3.0 PR"` |

**Висновок:** ADR-027 текст **існує дослівно** в комміті `90f1639` (гілка `docs/phase-3-architecture`, PR #28). Відновлюємо ДОСЛІВНО (WP2.A перший case), з приміткою, що коректна — не «втрачено при merge», а «PR #28 ніколи не мержився; текст перенесено з його гілки цим housekeeping-PR». Окрема рекомендація yurii: **закрити PR #28, #29, #30, #31 як superseded** (їх зміст реалізовано інакше і вже в main) — див. «Опитування» у PR description.

## 3. OQ у docs/00, потенційно вирішені пізнішими ADR

| OQ | Кандидат-рішення | Перевірка | Висновок |
| --- | --- | --- | --- |
| OQ-9 (паттерн перфорації: квадратна/шестикутна/кругла сітка) | ADR-031 (уніфікація hole_shape) | ADR-031 вирішує **форму отвору** (circle\|square) як параметр — це ADR-029→031 тема. Питання OQ-9 — про **паттерн сітки** (default: квадратна сітка кругл. отворів) — інша вісь, досі не має альтернативної реалізації (hex-сітка не імплементована). | **НЕ закривати** — різні питання, пряме рішення відсутнє. |
| OQ-17 (Discord — створено? лінк у README) | ADR-023 (Discord IaC) | ADR-023 фіксує **метод** (declarative TS-config), не факт live-деплою. CLAUDE.md §13 явно каже: «Discord IaC (ADR-023) чекає manual-setup» — сервер ще не живий, лінк лишається placeholder. | **НЕ закривати** — manual-setup ще не виконано. |
| OQ-19 (EN-локалізація) | вже відповідь у тексті OQ (не потребує ADR) | Відповідь вже вписана прямим текстом у сам OQ-19 у docs/00 («Замовник підтвердив UA+EN… Лишаємо обидві»), без ADR/PR-посилання — це рішення product-owner'а, не архітектурне. Формат docs/01 (`OQ-15`/`OQ-16`) використовує strikethrough+ADR-посилання лише для **архітектурних** рішень (ADR-011). У OQ-19 немає ADR — переносити нема на що посилатись понад те, що вже написано. | **Не чіпати** — вже де-факто відповідь, немає ADR-факту для строгого формату закриття; ризик вигадати посилання, якого нема. |
| OQ-21 (`@flatcraft/ui` build emit structure, латентна пастка) | — | `packages/ui/tsconfig.build.json` досі без `rootDir`/`paths→dist` фіксу (на відміну від `api`/`db`, див. `ffed953`). Пастка досі активна. | **НЕ закривати** — не виправлено. |

**Висновок WP1.3:** жоден OQ не має прямого підтвердженого рішення, придатного для закриття за конвенцією файлу (strikethrough + ADR-посилання). `docs/00_OPEN_QUESTIONS.md` **без змін** у цьому run'і.

## 4. Додаткові знахідки (поза явним scope WP1, але релевантні)

- **docs/15 A2** (ADR-033 Template Registry, Phase 3.5 docs-gate) — **виконано**: ADR-033 і `docs/12_TEMPLATE_CONTRACT.md` присутні на main. `git blame` на заголовок ADR-033 показує `74ff1c0` (PR #71, 2026-07-14) — це, ймовірно, побічний ефект squash-merge PR #71 з невірної бази (стара гілка з ще не змердженими docs-змінами ADR-033) — той самий клас помилки, який адресує `chore/guard-branch-base` (branch-base guard, PR #73). Зафіксовано як спостереження, не виправляється в цьому docs-only run'і.
- **docs/15 B3** (QR-фідбек, Phase 3.4) — **НЕ виконано**, узгоджується з п.1 вище (PR #69 draft).
- **Phase 3.0 Products Catalog не має власного запису у `docs/13_PROGRESS_LOG.md`**, хоча повністю реалізована на main (9 merged PR, 2026-06-23). Це поза формальним scope WP4 (який називає лише Phase 3.4), тому запис **не додається** цим run'ом — фіксується як окремий борг для наступного housekeeping-run'у.
