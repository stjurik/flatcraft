# WP3 — Legal-мінімум (feat/legal-minimum)

Package 3 з master-run'у (`docs/promts/master-softlaunch-run.md`). Виконує §WP3 (Roadmap 5.3-5.4 draft, 5.5 defer).

## Deliverables

| ID     | Файл                                     | Зміна                                                                                                    |
| ------ | ---------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| **A1** | `apps/web/src/app/privacy/page.tsx`      | UA — Privacy Policy draft (8 змістовних пунктів; блок «драфт, не є юрконсультацією»)                     |
| **A2** | `apps/web/src/app/privacy/en/page.tsx`   | EN — Privacy Policy draft (переклад п.1 без розширень)                                                   |
| **A3** | `apps/web/src/app/terms/page.tsx`        | UA — Terms of Service draft                                                                              |
| **A4** | `apps/web/src/app/terms/en/page.tsx`     | EN — Terms of Service draft                                                                              |
| **B**  | `apps/web/src/components/site-links.tsx` | Privacy/Terms → реальні href; Cookies → `/privacy#cookies`; +рядок «Без трекінг-cookies» під сіткою      |
| **C**  | (обмежено, той самий SiteLinks)          | Footer вже вміє `linksSlot` — не чіпаю `packages/ui`                                                     |
| **D**  | `docs/02_ROADMAP.md`                     | 5.3 → `[x] draft (Umami cookie-less)`; 5.4 → `[x] draft`; 5.5 → чітка нотка «відкладено до Phase 3 auth» |
| **E1** | `apps/web/tests/e2e/privacy.spec.ts`     | new — рендер UA+EN, 8 пунктів, links from Footer, console-clean                                          |
| **E2** | `apps/web/tests/e2e/terms.spec.ts`       | new — рендер UA+EN, ключові пункти, console-clean                                                        |

## Локалізація UA + EN

Проєкт **не використовує i18n-фреймворк** (`next-intl`/`i18next`) — `/about` теж UA-only. Master §WP3.A каже «UA основна + EN, патерн як /about» — розходження. **Приймаю**: UA-канонічне `/privacy` + окремий route `/privacy/en` (та `/terms/en`) з дублем компонента. Це найпростіший спосіб дати EN без введення i18n-фреймворку у цьому PR.

Мінус: два дублікати контенту (UA + EN). Плюс: без нової залежності, легко видалити або замінити на `next-intl` пізніше (Phase 3.5+, коли поставите auth і буде реальний i18n-scope).

**Питання до yurii:** OK з цим `/privacy/en`-паттерном, чи хочеш і18n-фреймворк одразу?

## Зміст (8 пунктів, які МАЄ покривати /privacy — з master §WP3.A)

1. Мінімум PII: `events` без email/IP; `session_hash` з добовим salt (ADR-032).
2. Умами self-hosted cookie-less — жодних трекінг-cookies (ADR-032 §4).
3. Sentry — технічні звіти про помилки, PII фільтрується `beforeSend` (CLAUDE.md §8).
4. Дані застосунку — ДЦ в Україні (Mirohost Kyiv, ADR-011).
5. Шифровані бекапи у Cloudflare R2 (поза Україною) — age-encryption.
6. Донати — добровільний внесок на ЗСУ напряму у фонди (Monobank Banka / UNITED24); платформа коштів не приймає (R-05).
7. Креслення — рекомендаційні; перевірка перед виробництвом на користувачеві (R-09).
8. Best-effort uptime без SLA.

**Драфт-блок на КОЖНІЙ сторінці**: «Драфт. Не є юридичною консультацією; фінальна версія — після рев'ю юристом (Roadmap 5.4).»

## Cookie-нотис

- Ніякого banner (Umami cookie-less → GDPR consent не потрібен, ADR-006 + ADR-032).
- Явна згадка «Без трекінг-cookies» у Footer/SiteLinks.
- Секція `#cookies` у `/privacy` з 2-3 рядками — "ми не ставимо трекінг-cookies; технічні cookies (auth, CSRF) з'являться коли додамо auth (Phase 3, ADR-020)".

## Тести

- `pnpm --filter @flatcraft/web test` (unit) — має пройти без нових unit-тестів (компоненти прості).
- `pnpm --filter @flatcraft/web lint / typecheck / build` — pass.
- Playwright: 2 нові spec'и (privacy + terms) з ~6 тестами кожен (UA render / EN render / 8 пунктів / Footer link / console-clean × 3 viewports). Загалом ~12 нових e2e.

## Обмеження

- Гілка `feat/legal-minimum` від `origin/main`.
- НЕ вигадувати юридичних деталей поза 8 пунктами.
- Жодних змін у `packages/ui` (Footer лишається як є — SiteLinks у apps/web).
- Draft PR, **НЕ merge**.

## Питання до yurii

Preview:

1. Локалізація `/privacy/en` — OK як окремий route, чи одразу `next-intl`/i18n-фреймворк?
2. Cookies-anchor `/privacy#cookies` у SiteLinks — чи достатньо, чи потрібна окрема сторінка `/cookies` (роздубьована з privacy)?
3. Draft-блок «не юрконсультація» — чи достатньо цього формулювання, чи потрібне сильніше застереження (напр. посилання на майбутнього юриста-рев'юера)?
