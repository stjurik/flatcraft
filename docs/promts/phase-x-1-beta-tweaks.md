[Phase X.1 — soft-launch beta tweaks: rate-limit, PDF watermark, ЗСУ-CTA, /about]
АВТОНОМНИЙ РЕЖИМ: послідовно, без user-OK чекпойнтів, self-verify тестами.
3-ітерації stop-rule. ПЕРЕДУМОВА: Hotfix 2.10.e уже змерджений у main.

КОНТЕКСТ
Прочитай:

1. CLAUDE.md §9, §13 (поточний стан)
2. AGENTS.md
3. docs/02_ROADMAP.md (для Phase X.1 sequence)
4. docs/03_DECISIONS.md — особливо ADR-016, ADR-019
5. docs/04_RISKS.md — R-02 (mobile), R-12 (validator)
6. docs/06_API_CONTRACT.md §0 (rate-limit поточний)
7. docs/10_DESIGN_SYSTEM.md (warm industrial tokens, Phase 2.11+)
8. apps/api/src/plugins/ — де налаштований @fastify/rate-limit
9. apps/web/src/components/export-button.tsx (success state)
10. workers/cad/flatcraft*cad/export/pdf.py (\_draw*\*, footer rendering)
11. apps/web/src/app/about/page.tsx (можливо існує як заглушка → /soon)
12. apps/web/src/app/soon/page.tsx (placeholder з Phase 2.12.b)
13. packages/ui/src/components/footer.tsx (ЗСУ-button уже є — реюзаєш)

СТРАТЕГІЧНИЙ КОНТЕКСТ
Замовник свідомо пропускає Phase 3 (Auth) і Phase 4 (Donations) у MVP-релізі.
Soft-launch модель: «безкоштовно для всіх, донати на ЗСУ — почесна система, без
блокування експорту». Phase 3+4 переноситься у v1.1 з тригером «коли реальні
цифри покажуть необхідність».

МЕТА
Підготувати продукт до публічного soft-launch'у без auth/donations інфраструктури:

1. IP-based rate-limit достатній для guest-mode (захист від abuse, толерантний до NAT).
2. PDF watermark «BETA» — знижує репутаційний ризик ранніх помилок.
3. Post-export ЗСУ-CTA на UI — ненавʼязливе нагадування про підтримку.
4. `/about` — справжня сторінка з оголошенням моделі (BETA, безкоштовно, ЗСУ).
5. Документація і roadmap re-sequence (Phase 3+4 → conditional v1.1).

КОНСТРЕЙНТИ

- НЕ додавай Auth.js, JWT, реєстрацію, login, refresh tokens.
- НЕ додавай /v1/auth/_, /v1/account/_, /v1/donations/_, /v1/uploads, /v1/admin/_
  endpoints. Вони лишаються у docs/06_API_CONTRACT.md як `v1.1+ planned`.
- НЕ створюй БД-таблиці users, oauth_accounts, sessions, donation_claims, usage_quota.
  Усі ці таблиці лишаються в docs/05_DATA_MODEL.md як «schema for v1.1+».
- НЕ міняй валідацію або експорт-pipeline (Hotfix 2.10.e — окрема PR, уже зроблено).
- НЕ запускай release.yml / deploy-staging.yml — auto-deploy на merge у main.
- Conventional Commits. Гілка: feat/phase-x-1-beta-mode-tweaks.

ЕТАПИ (виконуй автономно)

═══════════════════════════════════════════════════════════════
A. RATE-LIMIT для guest-mode
═══════════════════════════════════════════════════════════════
A1. Створи feature branch.

A2. Знайди де налаштований @fastify/rate-limit. Імовірно apps/api/src/plugins/
rate-limit.ts або у server.ts напряму.

A3. Замість поточного «5/хв на користувача» (per-user, але користувача нема) —
зроби IP-based з більш human-friendly лімітом:

    Глобально на api: max 100, timeWindow: '1 minute' (лишається як було).

    `POST /v1/exports`: max 30, timeWindow: '1 hour', keyGenerator: req.ip,
    errorResponseBuilder: повертає 429 з RFC 9457 problem details
    (`{type: '.../rate-limit', title: 'Rate limit exceeded', status: 429,
    detail: 'Перевищено ліміт 30 експортів на годину з вашої IP-адреси.
    Спробуйте через X хвилин.', instance: '/v1/exports'}`).

    Аргумент за 30/год: одна людина за день не зробить >30 експортів (тестуємо
    DIY-users, не bots); NAT-офіси з 10 співробітниками теж укладуться; bots
    блокуються після 30 спроб (на IP).

    Burst protection: ban-window 5 minutes if >50 in 10 minutes (через
    `ban: 50, max: 30` у @fastify/rate-limit).

A4. Vitest unit: rate-limit config обчислюється правильно (max=30, window=1h).
Vitest integration: post 30 запитів з одного IP → 30й = 200, 31й = 429
з очікуваним RFC 9457 problem detail.

A5. Закомить: feat(api): IP-based rate limit 30/h для /v1/exports (Phase X.1 A)

═══════════════════════════════════════════════════════════════
B. PDF WATERMARK «BETA»
═══════════════════════════════════════════════════════════════
B1. У workers/cad/flatcraft_cad/export/pdf.py знайди де рендериться footer
кожної сторінки (canvas.drawString або \_draw_footer helper).

B2. Додай pure-функцію `_draw_beta_watermark(canvas, page_width, page_height)`: - Центрований текст у footer над «Сторінка X з Y» (якщо така є):
`BETA · Знайшли помилку? feedback@hart.crimea.ua або Discord: <посилання>` - Шрифт: Helvetica-Oblique (курсив), 7pt, колір #707070 (subtle gray, читається але не кричить). - Y-позиція: 18pt від нижнього краю сторінки. - НЕ перекриває реальний контент (тестуй на найдовшій deталі — Z-bracket з max параметрами).

B3. Викликай у кожній сторінці PDF — точка інтеграції залежить від існуючого
layout-code. Шукай де canvas.showPage() або def render_pdf(canvas).

B4. У `compute_bom` або поряд: додай константу `BETA_WATERMARK = True` як модуль-level
flag (для майбутнього вимкнення при v1.0 повноцінного релізу).

B5. Snapshot-test: pytest з фіксованими параметрами Z-bracket → байт-PDF містить
рядок «BETA ·» у text content (через pdftotext або PyPDF2 text extraction).

B6. Закомить: feat(cad): PDF footer watermark «BETA · feedback» (Phase X.1 B)

═══════════════════════════════════════════════════════════════
C. POST-EXPORT ЗСУ-CTA у UI
═══════════════════════════════════════════════════════════════
C1. У apps/web/src/components/export-button.tsx (або де живе ExportSuccess
state) знайди блок який рендериться після успіху (з посиланнями DXF/PDF).

C2. ПІД блоком завантаження файлів додай новий компонент `<PostExportDonateNudge>`
(app-local, не у @flatcraft/ui):

    Structure:
      - <div className="mt-6 p-4 rounded-md bg-surface-sunken border border-border">
      - <p className="text-sm text-fg-muted mb-3">Платформа була корисною? Підтримайте ЗСУ:</p>
      - Flex row 2 buttons:
        a. <a href="https://send.monobank.ua/jar/A1u3M7VqQz" target="_blank" rel="noopener"
              className="bg-ua-blue text-zsu-fg ..."> (зсу-blue, ваш token)
              <Heart icon /> Monobank банка ↗
        b. <a href="https://u24.gov.ua/" target="_blank" rel="noopener"
              className="border border-border ...">
              UNITED24 ↗
      - min-h-tap на обох (Phase 2.11 інваріант)

C3. ВАЖЛИВО: жодного auto-redirect, modal, blocking-overlay. Користувач уже отримав
свої файли, CTA лише ненав'язливе нагадування.

C4. Playwright e2e: повний цикл екс- порту → блок «Платформа була корисною?» видимий →
обидві кнопки мають правильні href і target="\_blank".
Console-clean × 3 viewports (360/768/1280).

C5. Закомить: feat(web): post-export ЗСУ-CTA у success state (Phase X.1 C)

═══════════════════════════════════════════════════════════════
D. `/about` СТОРІНКА — справжня замість заглушки
═══════════════════════════════════════════════════════════════
D1. Якщо apps/web/src/app/about/page.tsx редиректить на /soon (з Phase 2.12.b
SiteLinks placeholder) — заміни на справжню сторінку.

D2. Структура:

    Hero:
      - Headline: «Креслення листового металу — безкоштовно і без CAD»
      - Sub: «BETA-проєкт для DIY-спільноти, малого бізнесу і архітекторів.»
      - text-fg, font-display.

    Section 1 — «Що це таке»:
      - 2-колонна (md+): зліва текст, справа маленький схематичний рендер
        (можна <TemplateThumb slug="l_bracket"/> з Phase 2.13).
      - Текст: 2-3 абзаци про продукт, для кого, чому без CAD-навичок.

    Section 2 — «Безкоштовно. Чому?»:
      - 3 коротких bullet-cards (Gift / Heart / Github icons):
        1. «BETA-релізе — все безкоштовно, без обмежень. Реєстрація не потрібна.»
        2. «Платформа неприбуткова. Якщо хочете подякувати — задонатіть на ЗСУ.»
        3. «Open Source MIT. Код на github.com/stjurik/flatcraft»

    Section 3 — «Підтримати ЗСУ»:
      - 2 великі кнопки (стиль як post-export CTA з C):
        a. Monobank банка (bg-ua-blue token)
        b. UNITED24
      - Маленька нота: «Платформа не виступає одержувачем коштів — донати йдуть
        напряму через офіційні фонди.»

    Section 4 — «Зворотний зв'язок»:
      - Discord (поки # placeholder або реальний коли буде)
      - GitHub issues link
      - feedback@hart.crimea.ua

D3. Метадані: title «Про hart.crimea.ua», description «BETA-платформа параметричного
CAD для листового металу. Безкоштовно. На підтримку ЗСУ.»

D4. Playwright e2e: - / і Footer SiteLinks мають active link на /about (не /soon). - /about рендериться без console-errors на 360/768/1280. - 4 секції видимі, обидва ЗСУ-buttons мають правильні href. - tap-targets ≥44px на всіх кнопках/посиланнях.

D5. Закомить: feat(web): справжня /about замість /soon заглушки (Phase X.1 D)

═══════════════════════════════════════════════════════════════
E. ДОКУМЕНТАЦІЯ
═══════════════════════════════════════════════════════════════
E1. docs/03_DECISIONS.md: новий ADR-020 «Soft-launch без auth/donations» - Контекст: Phase 3 (Auth) і Phase 4 (Donations) — 3 тижні роботи на
монетизацію, продакт-маркет-фіт ще не валідовано. - Рішення: пропускаємо обидві фази у MVP. Замість них — Phase X.1
(1-2 дні): IP rate-limit + PDF watermark + post-export CTA + /about copy. - Наслідки:
✓ Швидший public launch (днів замість тижнів).
✓ Сильніший меседж «безкоштовно для всіх».
✗ Нема персоналізації (нема "моїх чернеток", drafts у localStorage).
✗ Нема quota → потенційний abuse (mitigation: IP rate-limit, CF WAF). - Тригери перегляду: - >5 ботів/тиждень на CF WAF Analytics → Phase 3 (auth для quota). - Discord-фідбек «хочу зберегти свій draft» від >3 unique users → Phase 3. - >$50/міс приходить на ЗСУ через банку → Phase 4 (auto-acknowledge donate flow). - Альтернативи: повна Phase 3+4 одразу (відхилено — overinvestment перед PMF).

E2. docs/06_API_CONTRACT.md: - §0 Rate limit: оновити цифри під A3. - Усі §1 Auth, §2 Account, §6 Donations, §7 Admin → позначити header'ом
«🚧 v1.1+ planned — не реалізовано у MVP. Див. ADR-020.»

E3. docs/02_ROADMAP.md: - Phase 3 і Phase 4 перейменувати у «**Phase 3 — Auth & Limits (v1.1, conditional)**»
і «**Phase 4 — Donations (v1.1, conditional)**» з нотою «активуються лише
коли тригери з ADR-020 спрацюють». - Додати «**Phase X.1 — Beta-mode tweaks (завершено YYYY-MM-DD)**» між Phase 2.16
і Phase 5 trekом.

E4. CLAUDE.md §13: додай рядок «Phase X.1 завершено (YYYY-MM-DD з `date +%Y-%m-%d`):
IP rate-limit 30/h на /v1/exports, PDF footer watermark «BETA · feedback»,
post-export ЗСУ-CTA, справжня /about. Phase 3+4 → v1.1 conditional (ADR-020).»

E5. docs/04_RISKS.md: оновити R-03 «Анти-зловживання» — додати абзац: «У soft-launch
моделі (без auth, ADR-020) ліміт лише IP-based 30/h. Mitigation посилено через
Cloudflare WAF country block + CF rate-limit як другий рубіж. Якщо CF Analytics
покаже >5 ботів/тиждень — тригер для Phase 3.»

E6. Закомить: docs: ADR-020 + Phase X.1 done + Roadmap re-sequence + RISKS R-03

═══════════════════════════════════════════════════════════════
F. PR + ЗВІТ
═══════════════════════════════════════════════════════════════
F1. Push: git push origin feat/phase-x-1-beta-mode-tweaks

F2. gh pr create --base main --head feat/phase-x-1-beta-mode-tweaks \
 --title "feat: Phase X.1 — soft-launch beta tweaks" \
 --body-file /tmp/phase-x-1-pr-body.md

F3. PR body має містити: - "## Контекст" — посилання на ADR-020, чому пропускаємо Phase 3+4. - "## Що змінилось" — bullets A-E. - "## Що НЕ робимо тут" — Auth, Donations, БД-таблиці users/etc, /unlock page. - "## Перевірка після мерджу" (для yurii):
a. Manual: відкрити staging.hart.crimea.ua, зробити повний цикл export,
перевірити що ЗСУ-CTA з'являється після завантаження файлів.
b. Завантажити PDF, перевірити footer-watermark.
c. Manual: 31 раз POST /v1/exports з cURL з однієї IP → 31й = 429.
d. /about: усі 4 секції рендеряться. - "## Cloudflare action item (yurii, поза цим PR)":
«У CF Dashboard додати Custom WAF rule: Rate limit `/api/v1/exports*`
10 req/min/IP як другий рубіж. Це не у коді, бо CF WAF керується у dashboard.» - "## Тестова перевірка": числа total tests до vs після, нові вtest per A/B/C/D.

F4. Зведений підсумок у консоль: - PR URL - кількість нових тестів (vitest unit/int + playwright + pytest snapshot) - які docs оновлено

ЗАВЕРШЕННЯ
Якщо все пройшло — yurii ревʼюрить, мерджить, staging auto-deploys.
Після перевірки на staging — анонсує у Discord/Facebook/профільних форумах.

Якщо застряг — стоп, виведи у консоль:

- етап (A/B/C/D/E)
- який тест червоніє або яка несумісність з існуючим кодом
- 3 спроби фіксу
