# i18n-inventory — зведена інвентаризація UA-текстів (Стадія 1, Master Run 8)

> Вхід для Стадії 2 (ADR-037 + імплементація етапу A). Джерело — 4 сканування `agy`
> (Розвідник, Паттерн 2 з `docs/promts/agy-orchestration-recommendations.md`):
> `i18n-scan-zone{1,2,3,4}.md`. Кожна зона верифікована вибірково проти реального коду
> (мін. 5 рядків/зона, verify-then-write) — розбіжностей **не знайдено** (§Верифікація).

## Зона 1 — лендінг + /about + /soon

| Файл:рядок                                | UA-текст                                                                                                                                                                                                                            | Тип      |
| ----------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- |
| `apps/web/src/app/page.tsx:37`            | Креслення листового металу за 60 секунд. Без CAD-навичок.                                                                                                                                                                           | static   |
| `apps/web/src/app/page.tsx:40-41`         | Оберіть шаблон, налаштуйте розміри, скачайте DXF + PDF. Безкоштовно до 10 експортів на місяць.                                                                                                                                      | static   |
| `apps/web/src/app/page.tsx:45`            | Переглянути шаблони →                                                                                                                                                                                                               | static   |
| `apps/web/src/app/page.tsx:53`            | Як це працює ↓                                                                                                                                                                                                                      | static   |
| `apps/web/src/app/page.tsx:77`            | Оберіть шаблон                                                                                                                                                                                                                      | static   |
| `apps/web/src/app/page.tsx:78`            | 5 готових виробів: L- і Z-кронштейни, кутник, настінна полиця, перфо-панель. Кожен — з валідним bend-allowance і шарами під лазер.                                                                                                  | static   |
| `apps/web/src/app/page.tsx:82`            | Налаштуйте розміри                                                                                                                                                                                                                  | static   |
| `apps/web/src/app/page.tsx:83`            | Повзунки і поля з обмеженнями вашої виробничої машини. Зміна параметра — миттєвий 3D-прев'ю; помилка валідації — підсвічене червоним поле.                                                                                          | static   |
| `apps/web/src/app/page.tsx:87`            | Скачайте креслення                                                                                                                                                                                                                  | static   |
| `apps/web/src/app/page.tsx:88`            | DXF з 5 шарами для лазерної різки + PDF з розгорткою, таблицею гибів і BOM. STEP — за запитом.                                                                                                                                      | static   |
| `apps/web/src/app/page.tsx:97`            | Як це працює                                                                                                                                                                                                                        | static   |
| `apps/web/src/app/page.tsx:98`            | Від ідеї до креслення — 60 секунд.                                                                                                                                                                                                  | static   |
| `apps/web/src/app/page.tsx:133`           | 10 експортів/міс безкоштовно                                                                                                                                                                                                        | static   |
| `apps/web/src/app/page.tsx:137`           | Донати йдуть на ЗСУ                                                                                                                                                                                                                 | static   |
| `apps/web/src/app/about/page.tsx:6`       | Про hart.crimea.ua                                                                                                                                                                                                                  | metadata |
| `apps/web/src/app/about/page.tsx:7-8`     | BETA-платформа параметричного CAD для листового металу. Безкоштовно. На підтримку ЗСУ.                                                                                                                                              | metadata |
| `apps/web/src/app/about/page.tsx:26`      | BETA — без обмежень                                                                                                                                                                                                                 | static   |
| `apps/web/src/app/about/page.tsx:27`      | На час BETA-релізу все безкоштовно. Реєстрація не потрібна — відкрив, налаштував, скачав.                                                                                                                                           | static   |
| `apps/web/src/app/about/page.tsx:31`      | Неприбутковий проєкт                                                                                                                                                                                                                | static   |
| `apps/web/src/app/about/page.tsx:32`      | Платформа не заробляє на вас. Якщо хочете подякувати — задонатіть напряму на ЗСУ.                                                                                                                                                   | static   |
| `apps/web/src/app/about/page.tsx:37`      | Код відкритий: github.com/stjurik/flatcraft. Можна форкнути, вивчати, контриб'ютити.                                                                                                                                                | static   |
| `apps/web/src/app/about/page.tsx:48-49`   | Креслення листового металу — безкоштовно і без CAD                                                                                                                                                                                  | static   |
| `apps/web/src/app/about/page.tsx:51-52`   | BETA-проєкт для DIY-спільноти, малого бізнесу і архітекторів.                                                                                                                                                                       | static   |
| `apps/web/src/app/about/page.tsx:62`      | Що це таке                                                                                                                                                                                                                          | static   |
| `apps/web/src/app/about/page.tsx:64-66`   | hart — це веб-конструктор типових виробів з листового металу: кронштейнів, полиць, кутників, перфорованих панелей. Ви задаєте розміри повзунками й полями, бачите 3D-прев'ю у реальному часі — і одразу отримуєте готові креслення. | static   |
| `apps/web/src/app/about/page.tsx:69-70`   | CAD-навички не потрібні. Усю «важку» геометрію — розгортку з урахуванням k-фактора, перевірку радіусів гибки під вашу товщину й матеріал — платформа рахує сама.                                                                    | static   |
| `apps/web/src/app/about/page.tsx:73-74`   | На виході — DXF (для лазерного різання) і PDF (з розгорткою, таблицею гибів і специфікацією). Файли можна нести на будь-яке виробництво лазерного різання та гибки.                                                                 | static   |
| `apps/web/src/app/about/page.tsx:84`      | Безкоштовно. Чому?                                                                                                                                                                                                                  | static   |
| `apps/web/src/app/about/page.tsx:104`     | Підтримати ЗСУ                                                                                                                                                                                                                      | static   |
| `apps/web/src/app/about/page.tsx:114`     | Monobank банка ↗                                                                                                                                                                                                                    | static   |
| `apps/web/src/app/about/page.tsx:126-127` | Платформа не виступає одержувачем коштів — донати йдуть напряму через офіційні фонди.                                                                                                                                               | static   |
| `apps/web/src/app/about/page.tsx:133`     | Зворотний зв'язок                                                                                                                                                                                                                   | static   |
| `apps/web/src/app/about/page.tsx:134-135` | Знайшли помилку в кресленні чи маєте ідею? Напишіть — у BETA кожен відгук цінний.                                                                                                                                                   | static   |
| `apps/web/src/app/about/page.tsx:166`     | Discord-спільнота ↗                                                                                                                                                                                                                 | static   |
| `apps/web/src/app/soon/page.tsx:4`        | Скоро з'явиться · hart                                                                                                                                                                                                              | metadata |
| `apps/web/src/app/soon/page.tsx:15`       | Скоро з'явиться                                                                                                                                                                                                                     | static   |
| `apps/web/src/app/soon/page.tsx:17`       | Запланована сторінка                                                                                                                                                                                                                | static   |
| `apps/web/src/app/soon/page.tsx:19-20`    | Ця секція ще не активна. Слідкуйте за оновленнями у нашому                                                                                                                                                                          | static   |
| `apps/web/src/app/soon/page.tsx:28-29`    | — там видно, що зараз у розробці.                                                                                                                                                                                                   | static   |
| `apps/web/src/app/soon/page.tsx:35`       | ← На головну                                                                                                                                                                                                                        | static   |
| `apps/web/src/app/layout.tsx:30`          | hart.crimea.ua — параметричний CAD для листового металу                                                                                                                                                                             | metadata |
| `apps/web/src/app/layout.tsx:31-33`       | Креслення листового металу за 60 секунд. Без CAD-навичок. 10 експортів/міс безкоштовно. Соціальний проєкт на підтримку ЗСУ.                                                                                                         | metadata |

## Зона 2 — каталог /templates + картки + states + Footer/SiteLinks

| Файл:рядок                                          | UA-текст                                                                                                                          | Тип                                       |
| --------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------- |
| `apps/web/src/app/templates/page.tsx:9`             | Каталог · hart                                                                                                                    | static                                    |
| `apps/web/src/app/templates/page.tsx:10-12`         | Каталог готових виробів і параметричних шаблонів з листового металу. Налаштуйте розміри, скачайте DXF + PDF.                      | static                                    |
| `apps/web/src/app/templates/page.tsx:48`            | шаблони                                                                                                                           | static                                    |
| `apps/web/src/app/templates/page.tsx:50`            | вироби                                                                                                                            | static                                    |
| `apps/web/src/app/templates/page.tsx:60`            | Каталог                                                                                                                           | static                                    |
| `apps/web/src/app/templates/page.tsx:65`            | Каталог                                                                                                                           | static                                    |
| `apps/web/src/app/templates/page.tsx:68-69`         | Готові вироби з мінімальною конфігурацією або параметричні шаблони для повної свободи — у будь-якому випадку отримаєте DXF + PDF. | static                                    |
| `apps/web/src/app/templates/page.tsx:98`            | API повернув ${reason.status} (${kind}).                                                                                          | static                                    |
| `apps/web/src/app/templates/page.tsx:100`           | Не вдалося завантажити ${kind} з API.                                                                                             | static                                    |
| `apps/web/src/app/templates/page.tsx:147`           | Не вдалося завантажити каталог                                                                                                    | static                                    |
| `apps/web/src/app/templates/page.tsx:151`           | dev hint: запустіть                                                                                                               | static                                    |
| `apps/web/src/app/templates/page.tsx:161`           | Поки немає опублікованих виробів.                                                                                                 | static                                    |
| `apps/web/src/app/templates/page.tsx:162`           | Поки немає опублікованих шаблонів.                                                                                                | static                                    |
| `apps/web/src/app/templates/page.tsx:165`           | Перший продукт додамо у PR 6 — декоративну перфо-панель.                                                                          | static                                    |
| `apps/web/src/app/templates/page.tsx:166`           | Зайдіть пізніше — ми постійно додаємо нові шаблони.                                                                               | static                                    |
| `apps/web/src/app/templates/page.tsx:176`           | dev hint: запустіть                                                                                                               | static                                    |
| `apps/web/src/app/templates/[slug]/page.tsx:35`     | ${template.nameUk} · hart                                                                                                         | **DB**                                    |
| `apps/web/src/app/templates/[slug]/page.tsx:35`     | Шаблон не знайдено · hart                                                                                                         | static                                    |
| `apps/web/src/app/templates/[slug]/page.tsx:49`     | ← Усі шаблони                                                                                                                     | static                                    |
| `apps/web/src/app/templates/[slug]/page.tsx:55`     | {template.nameUk}                                                                                                                 | **DB**                                    |
| `apps/web/src/app/templates/[slug]/page.tsx:58`     | {template.descriptionUk}                                                                                                          | **DB**                                    |
| `apps/web/src/app/templates/[slug]/page.tsx:142`    | Студія для slug «${slug}» з'явиться у наступних фазах.                                                                            | static                                    |
| `apps/web/src/app/products/[slug]/page.tsx:34`      | ${product.name} · hart                                                                                                            | **DB (не локалізоване — див. §DB нижче)** |
| `apps/web/src/app/products/[slug]/page.tsx:34`      | Виріб не знайдено · hart                                                                                                          | static                                    |
| `apps/web/src/app/products/[slug]/page.tsx:47`      | ← Усі вироби                                                                                                                      | static                                    |
| `apps/web/src/app/products/[slug]/page.tsx:53`      | {product.name}                                                                                                                    | **DB (не локалізоване)**                  |
| `apps/web/src/app/products/[slug]/page.tsx:56`      | {product.description}                                                                                                             | **DB (не локалізоване)**                  |
| `apps/web/src/app/products/[slug]/page.tsx:119-120` | Студія для базового шаблону «{product.baseTemplateSlug}» з'явиться у наступних PR Phase 3.0.                                      | static                                    |
| `apps/web/src/components/template-card.tsx:30`      | Налаштувати: ${template.nameUk}                                                                                                   | **DB**                                    |
| `apps/web/src/components/template-card.tsx:38`      | {template.nameUk}                                                                                                                 | **DB**                                    |
| `apps/web/src/components/template-card.tsx:55`      | {template.nameUk}                                                                                                                 | **DB**                                    |
| `apps/web/src/components/template-card.tsx:60`      | {template.descriptionUk}                                                                                                          | **DB**                                    |
| `apps/web/src/components/template-card.tsx:66`      | Налаштувати →                                                                                                                     | static                                    |
| `apps/web/src/components/site-links.tsx:19`         | Продукт                                                                                                                           | static                                    |
| `apps/web/src/components/site-links.tsx:21`         | Шаблони                                                                                                                           | static                                    |
| `apps/web/src/components/site-links.tsx:22`         | Про проєкт                                                                                                                        | static                                    |
| `apps/web/src/components/site-links.tsx:23`         | Розблокувати                                                                                                                      | static                                    |
| `apps/web/src/components/site-links.tsx:27`         | Спільнота                                                                                                                         | static                                    |
| `apps/web/src/components/site-links.tsx:35`         | Юридичне                                                                                                                          | static                                    |
| `apps/web/src/components/site-links.tsx:54`         | Карта сайту                                                                                                                       | static                                    |
| `apps/web/src/components/site-links.tsx:88`         | Без трекінг-cookies (аналітика Umami self-hosted, cookie-less).                                                                   | static                                    |
| `packages/ui/src/components/footer.tsx:40-41`       | Соціальна платформа для виробів з листового металу. Без CAD-навичок — DXF, PDF, STEP безкоштовно.                                 | static                                    |
| `packages/ui/src/components/footer.tsx:52`          | Підтримати ЗСУ                                                                                                                    | static                                    |

## Зона 3 — export-flow UI + OG/layout metadata

| Файл:рядок                                                | UA-текст                                                                   | Тип     |
| --------------------------------------------------------- | -------------------------------------------------------------------------- | ------- |
| `apps/web/src/components/export-button.tsx:38`            | Експорт не вдався                                                          | dynamic |
| `apps/web/src/components/export-button.tsx:67`            | Невідома помилка                                                           | dynamic |
| `apps/web/src/components/export-button.tsx:87`            | Експорт… ${progress}%                                                      | dynamic |
| `apps/web/src/components/export-button.tsx:87`            | Експортувати DXF + PDF                                                     | static  |
| `apps/web/src/components/export-button.tsx:114`           | Завантажити DXF ({…} КБ)                                                   | dynamic |
| `apps/web/src/components/export-button.tsx:123`           | Завантажити PDF ({…} КБ)                                                   | dynamic |
| `apps/web/src/components/post-export-donate-nudge.tsx:19` | Платформа була корисною? Підтримайте ЗСУ:                                  | static  |
| `apps/web/src/components/post-export-donate-nudge.tsx:29` | Monobank банка ↗                                                           | static  |
| `apps/web/src/components/post-export-donate-nudge.tsx:38` | UNITED24 ↗                                                                 | static  |
| `apps/web/src/app/opengraph-image.tsx:25`                 | hart.crimea.ua — Креслення листового металу за 60 секунд. Без CAD-навичок. | static  |
| `apps/web/src/app/opengraph-image.tsx:113`                | Креслення листового металу за 60 секунд.                                   | static  |
| `apps/web/src/app/opengraph-image.tsx:124`                | Без CAD-навичок · DXF + PDF · 10 експортів/міс безкоштовно                 | static  |

## Зона 4 — /privacy + /terms (готовий прецедент двомовності)

**Патерн (уже в проді, працює):**

1. **Роутинг:** окрема підпапка `/en` всередині існуючого route (`app/privacy/page.tsx` uk, `app/privacy/en/page.tsx` en) — той самий підхід, який ADR-037 має або підтвердити, або замінити на `next-intl`/dictionary-роутинг для решти сайту.
2. **Спільні дані:** ПОВНЕ дублювання JSX і масивів (напр. `SECTIONS`) — нуль спільного коду/словника між uk і en. Явно свідомий вибір «без i18n-фреймворку» (коментар у коді).
3. **Перемикач мови:** інлайн-лінк `<Link href="/privacy/en">` у тексті `<header>` — не окремий UI-компонент перемикача.
4. **Metadata/hreflang:** `title`/`description` захардкоджені окремо в кожному файлі; **hreflang/alternates відсутні** — прогалина, яку ADR-037 має закрити (SEO-зв'язування мовних версій).

| Файл:рядок                              | UA-текст                                                                                  | EN-відповідник (з `en/page.tsx`)                                                  |
| --------------------------------------- | ----------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| `apps/web/src/app/privacy/page.tsx:103` | Драфт. Не є юридичною консультацією; фінальна версія — після рев'ю юристом (Roadmap 5.4). | Draft. Not legal advice; the final version follows a lawyer review (Roadmap 5.4). |
| `apps/web/src/app/privacy/page.tsx:108` | Політика приватності                                                                      | Privacy Policy                                                                    |
| `apps/web/src/app/privacy/page.tsx:29`  | 1. Мінімум персональних даних                                                             | 1. Minimum personal data                                                          |
| `apps/web/src/app/terms/page.tsx:107`   | Умови користування                                                                        | Terms of Service                                                                  |
| `apps/web/src/app/terms/page.tsx:64`    | Платформа НЕ приймає жодних коштів…                                                       | The platform does NOT accept any funds…                                           |
| `apps/web/src/app/terms/page.tsx:88`    | Це соціальний проєкт на одному сервері…                                                   | This is a social project on a single server…                                      |
| `apps/web/src/app/terms/page.tsx:133`   | Останнє оновлення: 2026-07-12. Політика приватності —                                     | Last updated: 2026-07-12. Privacy Policy —                                        |

---

## Готові DB-поля локалізації (перевірено `packages/db/src/schema.ts`)

| Таблиця     | UA-поле                     | EN-поле                     | Статус                                                                                                                                                                                                                                                                                                                                    |
| ----------- | --------------------------- | --------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `materials` | `name_uk` (`nameUk`)        | `name_en` (`nameEn`)        | ✅ обидва `notNull()` — готово до споживання                                                                                                                                                                                                                                                                                              |
| `templates` | `name_uk`, `description_uk` | `name_en`, `description_en` | ✅ `name*` `notNull()`, `description*` nullable — готово                                                                                                                                                                                                                                                                                  |
| `products`  | `name`, `description`       | — **немає**                 | ⚠️ **прогалина**: `products` НЕ має `name_en`/`description_en` (одне поле `name`/`description`, де зараз лежить UA-текст). Якщо етап A/B чіпає `/products/[slug]`, це потребує або нової колонки (drizzle-міграція — вручну, CLAUDE.md §6), або відкладення products-сторінок з EN до окремого PR. **→ занести в «Опитування» Стадії 2.** |

## НЕ входить в етап A (явно поза scope — фіксація для ADR-037 §5)

Промпт Master Run 8 фіксує: «Етап A СВІДОМО не чіпає студії/форми/валідацію — вони підуть
етапом B ПІСЛЯ Registry (Run 7)». Обсяг того, що лишається за межами:

| Категорія                               | Обсяг (грубо)                                       | Приклад                                                                           |
| --------------------------------------- | --------------------------------------------------- | --------------------------------------------------------------------------------- |
| Студії (`*-studio.tsx`)                 | 7 файлів у `apps/web/src/components/`               | `l-bracket-studio.tsx` та ін. — кожна студія власний editor+viewport, українською |
| AutoForm `.describe()`-лейбли (ADR-017) | 7 файлів схем у `packages/types/src/templates/*.ts` | `.describe("group:Розміри\|label:Довжина полиці")` — group/label-метадані форми   |
| Zod error-messages (UA)                 | 7 файлів у `packages/types/src/templates/*.ts`      | `.refine(..., { message: "Ширина полиці після гиба має бути ≥ 7.5 мм" })`         |
| PDF-генерація (worker)                  | 6 файлів у `workers/cad/flatcraft_cad/export/*.py`  | bend-table заголовки, BOM-рядки, UA-одиниці — ADR-021                             |

Причина відкладення (з промпту): ці поверхні мігрують на Template Registry в Run 7
(`docs/promts/master-registry-track.md`) — локалізувати їх зараз означало б подвійну
роботу (переклад згорить у міграції).

---

## Верифікація (verify-then-write)

Кожна зона звірена вибірково проти реального коду (≥5 рядків/зона, мін. вимога промпту):

- **Зона 1** (5 рядків): `page.tsx:37,40-41,45,53`; `layout.tsx:30-33` — **точний збіг**, включно з переносами рядків у `SITE_DESCRIPTION`.
- **Зона 2** (10 рядків): `template-card.tsx:30,38,55,60,66`; `site-links.tsx:19-23,88` — **точний збіг**.
- **Зона 3** (12/12 рядків, повний файл): `export-button.tsx:38,67,87,114,123` — **точний збіг**, підтверджено побайтовим diff усього `i18n-scan-zone3.md` проти чату-відповіді agy.
- **Зона 4** (5 рядків): `privacy/page.tsx:29,103,108`; `terms/page.tsx:64,88,107,133` — **точний збіг**, включно з EN-відповідниками.

**Розбіжностей скан-vs-код не знайдено на жодній із 4 зон** — перша метрика якості `agy`
у ролі Розвідника (ADR-036 §3): 0/32 верифікованих рядків розійшлися з кодом.

**Додаткова знахідка verify-кроку (не в жодному скані agy):** `products` не має
`name_en`/`description_en` на відміну від `materials`/`templates` (§DB вище) — виявлено
ручною перевіркою схеми, а не agy-сканом. Заносити в Опитування Стадії 2.
