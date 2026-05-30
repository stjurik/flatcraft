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

---

## 7. Контракт з Phase 2.12+

Phase 2.11 створила фундамент. Адаптація реальних екранів (`/templates`, `/templates/[slug]`, hero на `/`) — окремими PR'ами під трекерами:

- **Phase 2.12** — home page redesign на токенах.
- **Phase 2.13** — каталог `/templates` → cards з shadow-md, primary CTA на кожній.
- **Phase 2.14** — studio editor → mobile-friendly layout, progressive 3D (виконує план з R-02).
- **Phase 2.15** — Logo + UkraineStripe + Footer вписуються у layout root.

Старий emerald-700 / zinc-950 zoo буде прибрано саме у цих фазах. Phase 2.11 свідомо їх не чіпає (PR scope = фундамент).
