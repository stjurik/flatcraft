# 10. Design System — warm industrial, single light theme, mobile-first

> Phase 2.11 (2026-05-30). Цей документ — закон для UI: токени, правила вибору, mobile-first гайдлайни. Усі рішення зафіксовано в **ADR-016** (`docs/03_DECISIONS.md`).
> Жива демо-сторінка: `/styleguide` (доступна лише з `NEXT_PUBLIC_ENV=dev`).

---

## 1. Принципи

1. **Warm industrial.** Палітра створює асоціації з майстернею: тепле «креслярське» тло (off-white з помаранчевим відтінком), warm-charcoal текст (а не чорний), `ember` primary (помаранчево-амбра, як розпечений метал). Уникаємо холодних сіро-синіх → бренд не «корпоративний».
2. **Тільки світла тема.** Без перемикача. Цільовий контекст — майстерня/гараж зі змішаним освітленням, де world-readable light-on-bg працює стабільніше за dark. Перегляд → ребрендинг, або скарги з аналітики.
3. **Mobile-first.** Усі утиліти Tailwind за дефолтом маленькі, breakpoints розширюють. Студія має бути повноцінно редаговною на смартфоні — це інваріант (R-02 у `docs/04_RISKS.md`).
4. **Tap targets ≥ 44×44px.** Усі інтерактивні елементи — WCAG 2.5.5 (Enhanced). Перевіряється у Playwright.
5. **WCAG AA.** Body text ≥ 4.5:1, large text ≥ 3:1. У `/styleguide` контраст обчислюється inline через `contrastRatio()`.
6. **Respect prefers-reduced-motion.** Глобальний `@media` у `globals.css` знімає декоративні анімації; це default, не opt-in.
7. **OKLCH.** Перцептуально-рівномірний колір-простір — `--primary-hover` як `−6% L` від `primary` дає **однаковий візуальний відскок** на будь-якому відтінку, чого HSL не гарантує.

---

## 2. Токени (всі живуть у `apps/web/src/app/globals.css`)

Зберігаються як `L C H` (space-separated, без обгортки), щоб Tailwind міг застосувати `<alpha-value>`:

```ts
oklch(var(--color-primary) / <alpha-value>)
```

### 2.1 Surfaces

| Token                    | OKLCH            | Tailwind utility    | Де використовувати        |
| ------------------------ | ---------------- | ------------------- | ------------------------- |
| `--color-bg`             | `0.985 0.005 80` | `bg-bg`             | Body, page background     |
| `--color-bg-elevated`    | `1 0 0`          | `bg-bg-elevated`    | Cards, dialogs            |
| `--color-surface-sunken` | `0.965 0.008 80` | `bg-surface-sunken` | Inputs, textareas         |
| `--color-surface-muted`  | `0.945 0.01 80`  | `bg-surface-muted`  | Code блоки, table stripes |
| `--color-overlay`        | `0.22 0.015 50`  | `bg-overlay/60`     | Dialog backdrop (з alpha) |

### 2.2 Brand

| Token                   | OKLCH           | Tailwind                             | Де                          |
| ----------------------- | --------------- | ------------------------------------ | --------------------------- |
| `--color-primary`       | `0.66 0.17 50`  | `bg-primary text-primary-foreground` | Основні CTA, brand-elements |
| `--color-primary-hover` | `0.6 0.18 48`   | `hover:bg-primary-hover`             | Hover state primary         |
| `--color-accent`        | `0.55 0.08 220` | `bg-accent text-accent-foreground`   | Другорядні CTA (не donate)  |

### 2.3 Foreground

| Token               | OKLCH           | Tailwind         | Де                     |
| ------------------- | --------------- | ---------------- | ---------------------- |
| `--color-fg`        | `0.22 0.015 50` | `text-fg`        | Body text (AAA до bg)  |
| `--color-fg-muted`  | `0.42 0.012 50` | `text-fg-muted`  | Captions, secondary    |
| `--color-fg-subtle` | `0.55 0.01 50`  | `text-fg-subtle` | Placeholders, disabled |

### 2.4 Lines

| Token                   | OKLCH           | Tailwind               | Де                       |
| ----------------------- | --------------- | ---------------------- | ------------------------ |
| `--color-border`        | `0.88 0.008 70` | `border-border`        | Тонкі розділювачі (1px)  |
| `--color-border-strong` | `0.78 0.01 70`  | `border-border-strong` | Input borders            |
| `--color-ring`          | `0.66 0.17 50`  | `outline-ring`         | Focus ring (через alpha) |

### 2.5 Feedback

| Token                                  | Tailwind                                                                     | Де                                      |
| -------------------------------------- | ---------------------------------------------------------------------------- | --------------------------------------- |
| `success` / `-foreground` / `-surface` | `bg-success` / `text-success-foreground` / `bg-success-surface text-success` | Підтвердження, успішний експорт         |
| `warning` / `-foreground` / `-surface` | те саме                                                                      | Попередження (k-фактор не калібрований) |
| `danger` / `-foreground` / `-surface`  | те саме                                                                      | Помилки, destructive CTA                |
| `info` / `-foreground` / `-surface`    | те саме                                                                      | Підказки, нейтральні нотатки            |

### 2.6 Україна

| Token                               | Value                             | Де                               |
| ----------------------------------- | --------------------------------- | -------------------------------- |
| `--color-ua-blue`                   | `#0057B7`                         | `<UkraineStripe>`, ЗСУ-button bg |
| `--color-ua-yellow`                 | `#FFD700`                         | `<UkraineStripe>`                |
| `--color-zsu-bg` / `-hover` / `-fg` | `#0057B7` / `#004A99` / `#FFFFFF` | `<Button variant="zsu">`         |

> Зберігаємо як hex, а не OKLCH — точність державних кольорів важлива (OKLCH-апроксимація дає видиме зміщення).

### 2.7 Radii / Shadows / Motion / Tap

| Token                         | Value                            | Де                                         |
| ----------------------------- | -------------------------------- | ------------------------------------------ |
| `--radius-xs`                 | `2px`                            | Бейджі                                     |
| `--radius-sm`                 | `4px`                            | Buttons, inputs                            |
| `--radius-md`                 | `8px`                            | Cards                                      |
| `--radius-lg`                 | `12px`                           | Dialogs, hero-блоки                        |
| `--shadow-{sm,md,lg}`         | warm-charcoal base               | Cards, dialogs                             |
| `--ease-out`                  | `cubic-bezier(0.2, 0.8, 0.2, 1)` | UI feedback                                |
| `--duration-{fast,base,slow}` | `120ms / 200ms / 400ms`          | hover / dropdown / page transitions        |
| `--tap-target-min`            | `44px`                           | `min-h-tap min-w-tap` на всіх інтерактивах |

---

## 3. Правила (коли що використовувати)

### 3.1 Колір

- **Primary** — лише головний CTA на екрані. Один на view. «Export DXF», «Download», «Підтвердити».
- **Accent** — для secondary CTA, які не destructive і не donate. «Save draft», «Edit».
- **ZSU** — лише для donate-кнопки у Footer (і нікуди більше).
- **Destructive** — лише для дій з ризиком втрати даних: «Delete», «Reset».
- **Ghost / Outline** — повторювані toolbar-дії, де primary був би шумом.
- **Surface-sunken** — input fields. **Surface-muted** — code, табличні zebra-stripe.

### 3.2 Типографіка

- **Inter sans** — все body, UI.
- **Inter display** (той самий шрифт, але через `font-display` utility з `tracking-tight`) — `h1`/`h2`, hero-заголовки, лого.
- **JetBrains Mono** — лише real code, числові значення параметрів (`thickness: 2.0`), HTTP-методи у документації.

### 3.3 Radii

- `xs` — бейджі, тонкі індикатори.
- `sm` — інтерактиви (buttons, inputs). Industrial вигляд — без overly-rounded.
- `md` — content cards.
- `lg` — dialogs, hero-блоки.

---

## 4. Mobile-first

### 4.1 Breakpoints

| Name | Width    | Призначення                                |
| ---- | -------- | ------------------------------------------ |
| `xs` | `360px`  | Baseline mobile (Galaxy Fold, iPhone SE 1) |
| `sm` | `640px`  | Великі смартфони у landscape               |
| `md` | `768px`  | Tablets                                    |
| `lg` | `1024px` | Малий десктоп / tablet landscape           |
| `xl` | `1280px` | Десктоп                                    |

**Правило:** усі утиліти **за дефолтом** = `xs`. `md:` і вище розширюють. Якщо ловите себе на тому, що пишете `xs:px-2 md:px-8` — задумайтесь, чи не варто базовий `px-2` без префіксу.

### 4.2 Tap targets

Інваріант: **усі** клікабельні елементи ≥ 44×44px. Реалізовано через `min-h-tap min-w-tap` у нашому `<Button>`. Чекбокси/радіо — мінімум 20px з 24px padding-ом у label. Slider — `h-tap`.

### 4.3 Progressive 3D (буде в Phase 2.14)

R-02 у `docs/04_RISKS.md` фіксує план: на mobile сцена R3F спрощується — без HDR-env, без shadows, low-poly mesh, debounce параметрів збільшується до 250мс. Десктоп отримує повну якість.

### 4.4 Density

Mobile: вертикальний layout, кожен control — окремий рядок. Desktop: 2-колонний grid editor + viewport. **Не** дублюємо контент у mobile — те саме DOM, інша CSS-grid конфігурація.

---

## 5. Що НЕ робимо

- ❌ **Dark mode.** Власник рішення (ADR-016).
- ❌ **Кастомні кольори у компонентах.** Лише токени. `bg-emerald-700` (з попередньої версії home page) — anti-pattern.
- ❌ **`!important` у Tailwind utilities.** Виняток — глобальний `prefers-reduced-motion` reset.
- ❌ **Інлайн стилі для кольорів.** Тільки через CSS-variable у `style={{ background: "var(--color-...)" }}` (як у `<UkraineStripe>`), де gradient вимагає рантайм-композиції.
- ❌ **Шрифти з runtime-CDN.** Тільки `next/font/google` (self-hosted) — інакше CLS і третя сторона у CF/Google.
- ❌ **Іконки інших library, окрім lucide.** Один источник стилю.
- ❌ **Storybook як залежність.** `/styleguide` живе всередині app, без додаткового тулчейну.

---

## 6. Як додавати новий токен / компонент

1. **Токен** — у `apps/web/src/app/globals.css` з inline-коментарем «навіщо». Замапити у `tailwind.config.ts`. Додати рядок у `COLOR_TOKENS` у `/styleguide/page.tsx` (contrast рахується автоматом). Оновити цей файл.
2. **Компонент primitive** — у `packages/ui/src/primitives/`. Має використовувати лише токени-utility (`bg-primary`, `text-fg-muted` тощо), без hard-coded кольорів. `min-h-tap min-w-tap` на інтерактивах.
3. **Композитний компонент** (Logo, Footer, …) — у `packages/ui/src/components/`. Експорт через `index.ts`.
4. Додайте візуальний приклад на `/styleguide`.

### 6.1 Файлові конвенції

У `@flatcraft/ui` файли React-компонентів — **kebab-case** (`logo.tsx`, `ukraine-stripe.tsx`, `button.tsx`), експортовані імена — **PascalCase** (`Logo`, `UkraineStripe`, `Button`). Це свідоме рішення для консистентності з усіма іншими TS-файлами пакета (`schema-inspector.ts`, `use-debounced-value.ts`, `geometry.ts`). CLAUDE.md §5 — оригінальна конвенція PascalCase для `.tsx` — лишається у силі для `apps/web/src/components/`, якщо ми колись додамо там app-local компоненти.

### 6.2 Form patterns (Phase 2.12)

Студія шаблону складається з трьох рівнів секцій, кожна — `<fieldset>` з `<legend>`:

1. **Матеріал і товщина** — `<MaterialSection>` з `@flatcraft/ui/parameter-form`, перша секція форми. Дані матеріалів вантажить server component через `GET /materials`, передає у студію як prop. Дефолт: `cold_rolled_steel` + 2.0 мм.
2. **Доменні групи параметрів шаблону** — згруповані через **Zod `.describe("group:G|label:L")`** (ADR-017). AutoForm читає метадані з `_def.description` і рендерить кожну групу окремим fieldset'ом, у порядку появи першого поля. Незгруповані поля — у дефолтну «Загальне» внизу.
3. **Допоміжна інформація** (summary, validation banners, dev-debug) — поза fieldset'ами.

**Tokenized стилі** (повторювані для MaterialSection і AutoForm):

| Елемент                               | Tailwind utility                                                                                             |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| Fieldset                              | `mb-6 rounded-md border border-border bg-bg-elevated p-4 space-y-3`                                          |
| Legend                                | `px-2 text-base font-semibold text-fg`                                                                       |
| Label (текст)                         | `text-fg text-sm font-medium`                                                                                |
| Input/Select base                     | `min-h-tap w-full rounded-sm border border-border bg-surface-sunken px-3 py-2 text-sm text-fg`               |
| Input focus                           | `focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:border-border-strong` |
| Input invalid (`aria-invalid="true"`) | `border-danger ring-2 ring-danger/20`                                                                        |
| Input disabled                        | `disabled:bg-surface-muted disabled:text-fg-subtle disabled:cursor-not-allowed`                              |
| Error message `<ul>`                  | `text-xs text-danger`                                                                                        |
| Success banner                        | `border border-success/40 bg-success-surface text-success`                                                   |
| Error banner                          | `border border-danger/40 bg-danger-surface text-danger`                                                      |

**Чого НЕ робимо:**

- ❌ Hardcoded zinc/red/emerald класи у формах — лише токени (Phase 2.11 cleanup).
- ❌ Дублювання labels у `LABELS` map'і клієнтського editor'а, якщо `describe()` уже виставлений у схемі — `descriptor.label` має пріоритет над `props.labels?.[name]` тільки коли labels prop НЕ передано (precedence: `labels[name] → descriptor.label → name`).
- ❌ Debug-блоки (`<details>Параметри (JSON)</details>`) у prod — обгортайте в `{IS_DEV && ...}` де `IS_DEV = process.env.NEXT_PUBLIC_ENV === "dev"`.

---

## 7. Hero pattern (Phase 2.12.b)

Шаблон для marketing-сторінок (лендінг + майбутні `/about`, `/unlock`).

### Структура

```tsx
<section className="border-border bg-bg border-b">
  <div className="mx-auto grid max-w-7xl grid-cols-1 items-center gap-8 px-4 py-12 md:grid-cols-2 md:px-6 md:py-20 lg:gap-12">
    <header>
      <h1 className="font-display text-fg xs:text-5xl text-4xl font-semibold leading-tight md:text-6xl">
        ...
      </h1>
      <p className="text-fg-muted mt-6 text-lg md:text-xl">...</p>
      <Button asChild variant="default" size="lg" className="mt-8 self-start">
        <Link href="..." prefetch>
          ...
        </Link>
      </Button>
    </header>
    <div className="bg-bg-elevated border-border aspect-square overflow-hidden rounded-lg border shadow-md md:aspect-[4/3]">
      {/* живий або статичний візуальний приклад */}
    </div>
  </div>
</section>
```

### Правила

- **Типографічна шкала hero-h1**: `text-4xl xs:text-5xl md:text-6xl` (36→48→60px). Не йдемо вище `6xl` — на 4K візуально шум.
- **Grid breakpoint** — `md:` (768px). На xs/sm — стек, на md+ — 2 колонки. `lg:gap-12` додає простір на десктопі.
- **CTA** — Button primitive `variant="default" size="lg"`, з `prefetch` на `<Link>`. Secondary anchor (наприклад «↓ Як це працює») — окремий `<a>` під CTA, з `text-sm underline-offset-4`, опційний.
- **Візуальна частина** — `aspect-square` на xs/sm (квадрат заповнює ширину), `md:aspect-[4/3]` на десктопі (співвідношення під природній crop). Контейнер уже з shadow/border — внутрішній компонент НЕ дублює фон.

### Живий 3D у hero

- **Heavy bundle (R3F ~300КБ) — `dynamic(() => ..., { ssr: false })`** з Suspense skeleton того самого aspect-ratio (`animate-pulse bg-surface-muted`), щоб не було CLS.
- **Driver — pure helper** (наш `nextDemoParams(tMs)`) детермінований, тестується unit'ами. RAF лише вирішує, чи минув tick-інтервал; setState — у tick boundary, не на кожен frame.
- **Tick interval**: 100мс desktop, 200мс mobile (`matchMedia("(max-width: 767px)").matches`). Це йде у пакеті з R-02 mitigation.
- **Hover паузує** через `useRef<boolean>` (cancelAnimationFrame не потрібно — просто пропускаємо setState у tick). Touch — без паузи.
- **prefers-reduced-motion** — НЕ запускати RAF, рендерити статичний стан + caption «параметри інтерактивні у редакторі». Використовуйте `useReducedMotion` з `@flatcraft/ui`.

### Чого НЕ робимо у hero

- ❌ Декоративні градієнти/тіні навколо headline — типографіка має нести вагу сама.
- ❌ Кілька CTA на одному екрані — лише ОДИН primary CTA + опційний secondary anchor (link, не button).
- ❌ Auto-scroll, parallax — псує читання і конфліктує з reduced-motion.

---

## 8. Card pattern (Phase 2.13)

Шаблон для cards-сіток (каталог шаблонів, майбутні drafts-list, exports-history).

### Структура

```tsx
<article className="bg-bg-elevated border-border hover:border-border-strong duration-base group overflow-hidden rounded-lg border shadow-md transition-shadow ease-out hover:shadow-lg">
  <div className="bg-surface-sunken border-border text-fg-subtle group-hover:text-primary duration-base flex aspect-[4/3] items-center justify-center border-b transition-colors">
    {/* thumb: inline SVG (для каталога) або <img> з previewImageUrl */}
  </div>
  <div className="flex flex-col gap-2 p-5">
    <h3 className="font-display text-fg text-xl font-semibold">
      <Link href={href} prefetch className="hover:text-primary">
        {title}
      </Link>
    </h3>
    <p className="text-fg-muted text-sm">{description}</p>
    <div className="mt-3 flex items-center justify-between gap-3">
      <Button asChild variant="default" size="md">
        <Link href={href} prefetch data-testid="card-cta">
          {ctaText}
        </Link>
      </Button>
      <span className="text-fg-subtle font-mono text-xs">{meta}</span>
    </div>
  </div>
</article>
```

### Правила

- **Wrapper — `<article>`, не `<a>`.** HTML5 не дозволяє вкладені анкори. Замість картки-link маємо ДВА окремі лінки: clickable title (`<h3><Link>`) + explicit CTA-Button. Це краще для a11y (клавіатурна навігація по обох) і не ламає screen-reader heading-tree.
- **`group` + `group-hover:`** — hover на article додає `shadow-lg` і змінює `text-fg-subtle → text-primary` у thumb-області. Один semantic state на 3 візуальні зміни.
- **`aspect-[4/3]` thumb-region** — фіксований ratio запобігає CLS при lazy-load preview-зображень.
- **Schematic SVG-thumbs** (`apps/web/src/components/template-thumb.tsx`) — pure-presentational, `stroke="currentColor"` для тонального керування. Дешеві (~200 байт), без бандл-витрат. Реальні preview-PNG зʼявляться окремо (Phase 2.16).
- **Meta-text у фути** (slug у моно, версія, кількість) — `text-fg-subtle font-mono text-xs`. Меньше шуму, ніж badge-pills.

### Чого НЕ робимо

- ❌ Картка-link з вкладеною CTA-Button (`<a>` всередині `<a>` — HTML5 invalid).
- ❌ Drag-handles / sortable на cards у MVP — Phase post-MVP (drafts manager).
- ❌ Прев'ю на ходу через R3F — 5 одночасних canvas'ів вбиватимуть GPU. Лишаємо SVG до PNG-snapshot pipeline.

---

## 9. Adaptive 3D viewport (Phase 2.14.a)

R-02 mitigation реалізована через **pure helper** `viewportQuality({ isMobile, reduced })` у `@flatcraft/ui/lib/`. Споживачі викликають два React-хуки (`useIsMobile`, `useReducedMotion` з `@flatcraft/ui/hooks`) і передають їх result у helper — він повертає immutable `{ dpr, enableZoom, enableRotate, debounceMs, curveSegments }`.

### Матриця

| Сигнал          | `dpr`      | `enableZoom`                                | `enableRotate`                  | `debounceMs` | `curveSegments` |
| --------------- | ---------- | ------------------------------------------- | ------------------------------- | ------------ | --------------- |
| desktop         | `[1, 2]`   | true                                        | true                            | 100          | 12              |
| mobile (≤767px) | `[1, 1.5]` | **false** (pinch-zoom конфлікт з браузером) | true                            | 250          | 8               |
| reduced-motion  | `[1, 1]`   | false                                       | **false** (no camera animation) | 400          | 6               |

`reduced-motion` має пріоритет над `mobile` — користувач явно просив менше руху, незалежно від девайсу.

### Правила

- **`Canvas dpr={[...quality.dpr]}`** — обмежує `pixelRatio` згори; на retina mobile без cap'a отримуємо 9× pixel-load.
- **`OrbitControls enableZoom={quality.enableZoom}`** — на mobile вимикаємо, бо pinch-zoom 3D-сцени конфліктує з pinch-zoom сторінки iOS Safari (canvas-area стає недоступна для зум-сторінки).
- **`useDebouncedValue(parameters, quality.debounceMs)`** у студіях замість раніше hardcoded `100`.
- **`ExtrudeGeometry({ curveSegments })`** — поки тільки L-bracket (інші 4 scenes на BoxGeometry без arcs; round-bend rewrite — Phase 2.14.b).

### Mobile UX shortcut

`<StudioPreviewAnchor>` (`apps/web/src/components/studio-preview-anchor.tsx`) — кнопка-anchor `↓ Подивитися 3D-прев'ю`, видима лише на xs/sm/md (`lg:hidden`). Скрол до `#studio-viewport` (id на root-обгортці кожного `XViewport`). Дешевий перехід editor→preview без sticky-FAB (sticky → Phase 2.16+).

### Чого НЕ робимо

- ❌ Sticky thumbnail-FAB на mobile — overkill для MVP, потребує WebGL state preservation на route navigation.
- ❌ "Desktop required" повідомлення на mobile — повноцінне редагування інваріант (ADR-016, R-02).
- ❌ Адаптивний rendering quality, що міняється у відповідь на FPS — preventive matrix дешевша і передбачувана.

---

## 10. Контракт з Phase 2.12+

Phase 2.11 створила фундамент. Phase 2.12+ розбита на дрібні PR'и:

- ✅ **Phase 2.12.a** — editor form polish (grouping, MaterialSection, token cleanup, ADR-017+018).
- ✅ **Phase 2.12.b** — landing redesign (hero + loop-demo + how-it-works + trust + SiteLinks).
- ✅ **Phase 2.13** — каталог `/templates` з токенізованими cards (shadow-md, primary CTA, SVG-thumbs).
- ✅ **Phase 2.14.a** — mobile-friendly studio + progressive 3D (viewportQuality, anchor, R-02 mitigation).
- **Phase 2.14.b** — round-bend geometry для Z/corner_angle/wall_shelf scenes (ExtrudeGeometry rewrite).
- **Phase 2.15** — Logo + Footer вписуються у layout root (зроблено у Phase 2.11 hotfix).
- **Phase 2.16** — `og-default.png` + Open Graph metadata + реальні preview-PNG для каталога.

Старий emerald-700 / zinc-950 zoo прибирається покроково у цих фазах.
