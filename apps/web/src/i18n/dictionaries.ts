/**
 * i18n-словники Etap A (ADR-037 §1/§4). `uk` — byte-identical до наявних
 * hardcoded рядків (жоден наявний e2e не змінюється); `en` — природна
 * інженерна англійська для DIY/maker-аудиторії, не дослівний переклад.
 *
 * TS-компілятор гарантує паритет КЛЮЧІВ (не значень) між `uk`/`en` —
 * обидва типізовані як `Dictionary` (звичайні `string`, без `as const`,
 * інакше кожен `uk`-рядок став би власним literal-типом і `en` не
 * скомпілювався б). Сильніша гарантія за окремі JSON + ручний type-файл.
 * DB-контент (`template.nameUk`/`nameEn`) сюди НЕ дублюється — читається
 * напряму з API.
 *
 * Межа Etap A (ADR-037 §5): студії (`*-studio.tsx`) не споживають цей файл.
 */

export interface Dictionary {
  readonly common: {
    readonly siteTitle: string;
    readonly siteDescription: string;
    readonly ogLocale: string;
    readonly homeAriaLabel: string;
    readonly footerTagline: string;
    readonly footerDonate: string;
    readonly cookieNote: string;
    readonly siteLinks: {
      readonly sitemapAria: string;
      readonly productTitle: string;
      readonly templates: string;
      readonly about: string;
      readonly unlock: string;
      readonly communityTitle: string;
      readonly github: string;
      readonly discord: string;
      readonly telegram: string;
      readonly legalTitle: string;
      readonly privacy: string;
      readonly terms: string;
      readonly cookies: string;
    };
    readonly localeSwitcher: {
      readonly toEnAria: string;
      readonly toUkAria: string;
      readonly toEnLabel: string;
      readonly toUkLabel: string;
    };
  };
  readonly home: {
    readonly heroHeadline: string;
    readonly heroSub: string;
    readonly heroCta: string;
    readonly heroAnchorHow: string;
    readonly heroDemoAria: string;
    readonly heroReducedCaption: string;
    readonly howTitle: string;
    readonly howSub: string;
    readonly steps: ReadonlyArray<{ readonly title: string; readonly desc: string }>;
    readonly trustExports: string;
    readonly trustDonate: string;
    readonly trustDonateLink: string;
    readonly trustOpenSource: string;
    readonly trustGithubLink: string;
  };
  readonly about: {
    readonly metaTitle: string;
    readonly metaDescription: string;
    readonly badge: string;
    readonly heroTitle: string;
    readonly heroSubtitle: string;
    readonly whatTitle: string;
    readonly whatP1: string;
    readonly whatP2: string;
    readonly whatP3: string;
    readonly freeTitle: string;
    readonly freeCards: ReadonlyArray<{ readonly title: string; readonly body: string }>;
    readonly zsuTitle: string;
    readonly zsuMonobankLabel: string;
    readonly zsuUnited24Label: string;
    readonly zsuNote: string;
    readonly feedbackTitle: string;
    readonly feedbackBody: string;
    readonly feedbackGithubLabel: string;
    readonly feedbackDiscordLabel: string;
  };
  readonly soon: {
    readonly metaTitle: string;
    readonly eyebrow: string;
    readonly title: string;
    readonly body1: string;
    readonly githubLabel: string;
    readonly body2: string;
    readonly backHome: string;
  };
  readonly catalog: {
    readonly metaTitle: string;
    readonly metaDescription: string;
    readonly eyebrow: string;
    readonly title: string;
    readonly subtitle: string;
    readonly toggleAria: string;
    readonly toggleProductsLabel: (count: number) => string;
    readonly toggleProductsAria: (count: number) => string;
    readonly togglePartsLabel: (count: number) => string;
    readonly togglePartsAria: (count: number) => string;
    readonly kindTemplates: string;
    readonly kindProducts: string;
    readonly apiErrorStatus: (status: number, kind: string) => string;
    readonly apiErrorGeneric: (kind: string) => string;
    readonly errorTitle: string;
    readonly devHintApi: string;
    readonly emptyProducts: string;
    readonly emptyParts: string;
    readonly emptyProductsHint: string;
    readonly emptyPartsHint: string;
    readonly devHintSeed: string;
  };
  readonly templateCard: {
    readonly configureAria: (name: string) => string;
    readonly cta: string;
  };
  readonly productCard: {
    readonly configureAria: (name: string) => string;
    readonly basedOnLabel: string;
    readonly cta: string;
    readonly placeholderSoon: string;
  };
  readonly templateDetail: {
    readonly back: string;
    readonly notFoundTitle: string;
    readonly unsupported: (slug: string) => string;
  };
  readonly productDetail: {
    readonly back: string;
    readonly notFoundTitle: string;
    readonly unsupportedBase: (baseSlug: string) => string;
  };
  readonly exportFlow: {
    readonly exportFailed: string;
    readonly unknownError: string;
    readonly exporting: (progress: number) => string;
    readonly exportCta: string;
    readonly downloadDxf: (kb: number) => string;
    readonly downloadPdf: (kb: number) => string;
    readonly donateQuestion: string;
    readonly donateMonobank: string;
    readonly donateUnited24: string;
  };
  readonly og: {
    readonly alt: string;
    readonly headline: string;
    readonly sub: string;
  };
}

const uk: Dictionary = {
  common: {
    siteTitle: "hart.crimea.ua — параметричний CAD для листового металу",
    siteDescription:
      "Креслення листового металу за 60 секунд. Без CAD-навичок. " +
      "10 експортів/міс безкоштовно. Соціальний проєкт на підтримку ЗСУ.",
    ogLocale: "uk_UA",
    homeAriaLabel: "Перейти на головну",
    footerTagline:
      "Соціальна платформа для виробів з листового металу. Без CAD-навичок — DXF, PDF, STEP безкоштовно.",
    footerDonate: "Підтримати ЗСУ",
    cookieNote: "Без трекінг-cookies (аналітика Umami self-hosted, cookie-less).",
    siteLinks: {
      sitemapAria: "Карта сайту",
      productTitle: "Продукт",
      templates: "Шаблони",
      about: "Про проєкт",
      unlock: "Розблокувати",
      communityTitle: "Спільнота",
      github: "GitHub ↗",
      discord: "Discord ↗",
      telegram: "Telegram",
      legalTitle: "Юридичне",
      privacy: "Privacy",
      terms: "Terms",
      cookies: "Cookies",
    },
    localeSwitcher: {
      toEnAria: "Switch to English",
      toUkAria: "Переключити на українську",
      toEnLabel: "EN",
      toUkLabel: "UA",
    },
  },
  home: {
    heroHeadline: "Креслення листового металу за 60 секунд. Без CAD-навичок.",
    heroSub:
      "Оберіть шаблон, налаштуйте розміри, скачайте DXF + PDF. Безкоштовно до 10 експортів на місяць.",
    heroCta: "Переглянути шаблони →",
    heroAnchorHow: "Як це працює ↓",
    heroDemoAria: "Демо: автоматична зміна параметрів L-кронштейна",
    heroReducedCaption:
      "Параметри інтерактивні у редакторі — а тут показуємо статичний бракет (ваш браузер просить менше анімації).",
    howTitle: "Як це працює",
    howSub: "Від ідеї до креслення — 60 секунд.",
    steps: [
      {
        title: "Оберіть шаблон",
        desc: "5 готових виробів: L- і Z-кронштейни, кутник, настінна полиця, перфо-панель. Кожен — з валідним bend-allowance і шарами під лазер.",
      },
      {
        title: "Налаштуйте розміри",
        desc: "Повзунки і поля з обмеженнями вашої виробничої машини. Зміна параметра — миттєвий 3D-прев'ю; помилка валідації — підсвічене червоним поле.",
      },
      {
        title: "Скачайте креслення",
        desc: "DXF з 5 шарами для лазерної різки + PDF з розгорткою, таблицею гибів і BOM. STEP — за запитом.",
      },
    ],
    trustExports: "10 експортів/міс безкоштовно",
    trustDonate: "Донати йдуть на ЗСУ",
    trustDonateLink: "UNITED24 ↗",
    trustOpenSource: "Open Source · MIT",
    trustGithubLink: "github.com/stjurik/flatcraft ↗",
  },
  about: {
    metaTitle: "Про hart.crimea.ua",
    metaDescription:
      "BETA-платформа параметричного CAD для листового металу. Безкоштовно. На підтримку ЗСУ.",
    badge: "BETA",
    heroTitle: "Креслення листового металу — безкоштовно і без CAD",
    heroSubtitle: "BETA-проєкт для DIY-спільноти, малого бізнесу і архітекторів.",
    whatTitle: "Що це таке",
    whatP1:
      "hart — це веб-конструктор типових виробів з листового металу: кронштейнів, полиць, кутників, перфорованих панелей. Ви задаєте розміри повзунками й полями, бачите 3D-прев'ю у реальному часі — і одразу отримуєте готові креслення.",
    whatP2:
      "CAD-навички не потрібні. Усю «важку» геометрію — розгортку з урахуванням k-фактора, перевірку радіусів гибки під вашу товщину й матеріал — платформа рахує сама.",
    whatP3:
      "На виході — DXF (для лазерного різання) і PDF (з розгорткою, таблицею гибів і специфікацією). Файли можна нести на будь-яке виробництво лазерного різання та гибки.",
    freeTitle: "Безкоштовно. Чому?",
    freeCards: [
      {
        title: "BETA — без обмежень",
        body: "На час BETA-релізу все безкоштовно. Реєстрація не потрібна — відкрив, налаштував, скачав.",
      },
      {
        title: "Неприбутковий проєкт",
        body: "Платформа не заробляє на вас. Якщо хочете подякувати — задонатіть напряму на ЗСУ.",
      },
      {
        title: "Open Source MIT",
        body: "Код відкритий: github.com/stjurik/flatcraft. Можна форкнути, вивчати, контриб'ютити.",
      },
    ],
    zsuTitle: "Підтримати ЗСУ",
    zsuMonobankLabel: "Monobank банка ↗",
    zsuUnited24Label: "UNITED24 ↗",
    zsuNote:
      "Платформа не виступає одержувачем коштів — донати йдуть напряму через офіційні фонди.",
    feedbackTitle: "Зворотний зв'язок",
    feedbackBody:
      "Знайшли помилку в кресленні чи маєте ідею? Напишіть — у BETA кожен відгук цінний.",
    feedbackGithubLabel: "GitHub Issues ↗",
    feedbackDiscordLabel: "Discord-спільнота ↗",
  },
  soon: {
    metaTitle: "Скоро з'явиться · hart",
    eyebrow: "Скоро з'явиться",
    title: "Запланована сторінка",
    body1: "Ця секція ще не активна. Слідкуйте за оновленнями у нашому",
    githubLabel: "GitHub",
    body2: "— там видно, що зараз у розробці.",
    backHome: "← На головну",
  },
  catalog: {
    metaTitle: "Каталог · hart",
    metaDescription:
      "Каталог готових виробів і параметричних шаблонів з листового металу. Налаштуйте розміри, скачайте DXF + PDF.",
    eyebrow: "Каталог",
    title: "Каталог",
    subtitle:
      "Готові вироби з мінімальною конфігурацією або параметричні шаблони для повної свободи — у будь-якому випадку отримаєте DXF + PDF.",
    toggleAria: "Вид каталогу",
    toggleProductsLabel: (count: number) => `Вироби · ${count}`,
    toggleProductsAria: (count: number) => `Готові вироби (${count})`,
    togglePartsLabel: (count: number) => `Деталі · ${count}`,
    togglePartsAria: (count: number) => `Параметричні шаблони деталей (${count})`,
    kindTemplates: "шаблони",
    kindProducts: "вироби",
    apiErrorStatus: (status: number, kind: string) => `API повернув ${status} (${kind}).`,
    apiErrorGeneric: (kind: string) => `Не вдалося завантажити ${kind} з API.`,
    errorTitle: "Не вдалося завантажити каталог",
    devHintApi: "dev hint: запустіть",
    emptyProducts: "Поки немає опублікованих виробів.",
    emptyParts: "Поки немає опублікованих шаблонів.",
    emptyProductsHint: "Перший продукт додамо у PR 6 — декоративну перфо-панель.",
    emptyPartsHint: "Зайдіть пізніше — ми постійно додаємо нові шаблони.",
    devHintSeed: "dev hint: запустіть",
  },
  templateCard: {
    configureAria: (name: string) => `Налаштувати: ${name}`,
    cta: "Налаштувати →",
  },
  productCard: {
    configureAria: (name: string) => `Налаштувати: ${name}`,
    basedOnLabel: "На основі:",
    cta: "Налаштувати →",
    placeholderSoon: "рендер скоро",
  },
  templateDetail: {
    back: "← Усі шаблони",
    notFoundTitle: "Шаблон не знайдено · hart",
    unsupported: (slug: string) => `Студія для slug «${slug}» з'явиться у наступних фазах.`,
  },
  productDetail: {
    back: "← Усі вироби",
    notFoundTitle: "Виріб не знайдено · hart",
    unsupportedBase: (baseSlug: string) =>
      `Студія для базового шаблону «${baseSlug}» з'явиться у наступних PR Phase 3.0.`,
  },
  exportFlow: {
    exportFailed: "Експорт не вдався",
    unknownError: "Невідома помилка",
    exporting: (progress: number) => `Експорт… ${progress}%`,
    exportCta: "Експортувати DXF + PDF",
    downloadDxf: (kb: number) => `Завантажити DXF (${kb} КБ)`,
    downloadPdf: (kb: number) => `Завантажити PDF (${kb} КБ)`,
    donateQuestion: "Платформа була корисною? Підтримайте ЗСУ:",
    donateMonobank: "Monobank банка ↗",
    donateUnited24: "UNITED24 ↗",
  },
  og: {
    alt: "hart.crimea.ua — Креслення листового металу за 60 секунд. Без CAD-навичок.",
    headline: "Креслення листового металу за 60 секунд.",
    sub: "Без CAD-навичок · DXF + PDF · 10 експортів/міс безкоштовно",
  },
};

const en: Dictionary = {
  common: {
    siteTitle: "hart.crimea.ua — parametric CAD for sheet metal",
    siteDescription:
      "Sheet-metal drawings in 60 seconds. No CAD skills needed. " +
      "10 free exports/month. A social project supporting Ukraine's defense.",
    ogLocale: "en_US",
    homeAriaLabel: "Go to homepage",
    footerTagline: "A social platform for sheet-metal parts. No CAD skills — DXF, PDF, STEP, free.",
    footerDonate: "Support Ukraine",
    cookieNote: "No tracking cookies (analytics via self-hosted, cookie-less Umami).",
    siteLinks: {
      sitemapAria: "Sitemap",
      productTitle: "Product",
      templates: "Templates",
      about: "About",
      unlock: "Unlock",
      communityTitle: "Community",
      github: "GitHub ↗",
      discord: "Discord ↗",
      telegram: "Telegram",
      legalTitle: "Legal",
      privacy: "Privacy",
      terms: "Terms",
      cookies: "Cookies",
    },
    localeSwitcher: {
      toEnAria: "Switch to English",
      toUkAria: "Switch to Ukrainian",
      toEnLabel: "EN",
      toUkLabel: "UA",
    },
  },
  home: {
    heroHeadline: "Sheet-metal drawings in 60 seconds. No CAD skills needed.",
    heroSub:
      "Pick a template, set your dimensions, download DXF + PDF. Free for up to 10 exports a month.",
    heroCta: "Browse templates →",
    heroAnchorHow: "How it works ↓",
    heroDemoAria: "Demo: auto-cycling parameters of an L-bracket",
    heroReducedCaption:
      "Parameters are interactive in the editor — here we show a static bracket (your browser asked for less motion).",
    howTitle: "How it works",
    howSub: "From idea to drawing — 60 seconds.",
    steps: [
      {
        title: "Pick a template",
        desc: "5 ready-made parts: L- and Z-brackets, corner angle, wall shelf, perforated panel. Each ships with valid bend-allowance and laser-cut layers.",
      },
      {
        title: "Set your dimensions",
        desc: "Sliders and fields constrained to your production machine. Change a parameter — instant 3D preview; a validation error highlights the field in red.",
      },
      {
        title: "Download the drawing",
        desc: "DXF with 5 laser-cutting layers + PDF with the unfold, bend table, and BOM. STEP on request.",
      },
    ],
    trustExports: "10 free exports/month",
    trustDonate: "Donations go to Ukraine's defense",
    trustDonateLink: "UNITED24 ↗",
    trustOpenSource: "Open Source · MIT",
    trustGithubLink: "github.com/stjurik/flatcraft ↗",
  },
  about: {
    metaTitle: "About hart.crimea.ua",
    metaDescription:
      "A BETA parametric CAD platform for sheet metal. Free. Supporting Ukraine's defense.",
    badge: "BETA",
    heroTitle: "Sheet-metal drawings — free, no CAD needed",
    heroSubtitle: "A BETA project for the DIY community, small businesses, and architects.",
    whatTitle: "What this is",
    whatP1:
      "hart is a web-based configurator for common sheet-metal parts: brackets, shelves, corner angles, perforated panels. You set the dimensions with sliders and fields, see a live 3D preview — and get finished drawings right away.",
    whatP2:
      "No CAD skills required. The platform handles all the tricky geometry itself — unfolding with k-factor, checking bend radii against your thickness and material.",
    whatP3:
      "The output is DXF (for laser cutting) and PDF (with the unfold, bend table, and spec sheet). Take the files to any laser-cutting and bending shop.",
    freeTitle: "Free. Why?",
    freeCards: [
      {
        title: "BETA — no limits",
        body: "Everything is free during the BETA release. No sign-up needed — open it, configure it, download it.",
      },
      {
        title: "Non-profit project",
        body: "The platform doesn't make money off you. If you'd like to say thanks, donate directly to Ukraine's defense.",
      },
      {
        title: "Open Source MIT",
        body: "The code is open: github.com/stjurik/flatcraft. Fork it, study it, contribute.",
      },
    ],
    zsuTitle: "Support Ukraine's defense",
    zsuMonobankLabel: "Monobank jar ↗",
    zsuUnited24Label: "UNITED24 ↗",
    zsuNote:
      "The platform never receives funds itself — donations go directly through official funds.",
    feedbackTitle: "Feedback",
    feedbackBody:
      "Found a drawing bug or have an idea? Let us know — every bit of feedback matters during BETA.",
    feedbackGithubLabel: "GitHub Issues ↗",
    feedbackDiscordLabel: "Discord community ↗",
  },
  soon: {
    metaTitle: "Coming soon · hart",
    eyebrow: "Coming soon",
    title: "Planned page",
    body1: "This section isn't active yet. Follow updates on our",
    githubLabel: "GitHub",
    body2: "— it shows what's currently in progress.",
    backHome: "← Back home",
  },
  catalog: {
    metaTitle: "Catalog · hart",
    metaDescription:
      "A catalog of ready-made parts and parametric sheet-metal templates. Set your dimensions, download DXF + PDF.",
    eyebrow: "Catalog",
    title: "Catalog",
    subtitle:
      "Ready-made parts with minimal configuration, or fully parametric templates for complete freedom — either way you get DXF + PDF.",
    toggleAria: "Catalog view",
    toggleProductsLabel: (count: number) => `Parts · ${count}`,
    toggleProductsAria: (count: number) => `Ready-made parts (${count})`,
    togglePartsLabel: (count: number) => `Templates · ${count}`,
    togglePartsAria: (count: number) => `Parametric part templates (${count})`,
    kindTemplates: "templates",
    kindProducts: "parts",
    apiErrorStatus: (status: number, kind: string) => `The API returned ${status} (${kind}).`,
    apiErrorGeneric: (kind: string) => `Couldn't load ${kind} from the API.`,
    errorTitle: "Couldn't load the catalog",
    devHintApi: "dev hint: run",
    emptyProducts: "No published parts yet.",
    emptyParts: "No published templates yet.",
    emptyProductsHint: "We'll add the first part in PR 6 — a decorative perforated panel.",
    emptyPartsHint: "Check back later — we're steadily adding new templates.",
    devHintSeed: "dev hint: run",
  },
  templateCard: {
    configureAria: (name: string) => `Configure: ${name}`,
    cta: "Configure →",
  },
  productCard: {
    configureAria: (name: string) => `Configure: ${name}`,
    basedOnLabel: "Based on:",
    cta: "Configure →",
    placeholderSoon: "preview coming soon",
  },
  templateDetail: {
    back: "← All templates",
    notFoundTitle: "Template not found · hart",
    unsupported: (slug: string) => `The studio for slug "${slug}" is coming in a future phase.`,
  },
  productDetail: {
    back: "← All parts",
    notFoundTitle: "Part not found · hart",
    unsupportedBase: (baseSlug: string) =>
      `The studio for the "${baseSlug}" base template is coming in a future Phase 3.0 PR.`,
  },
  exportFlow: {
    exportFailed: "Export failed",
    unknownError: "Unknown error",
    exporting: (progress: number) => `Exporting… ${progress}%`,
    exportCta: "Export DXF + PDF",
    downloadDxf: (kb: number) => `Download DXF (${kb} KB)`,
    downloadPdf: (kb: number) => `Download PDF (${kb} KB)`,
    donateQuestion: "Found this useful? Support Ukraine's defense:",
    donateMonobank: "Monobank jar ↗",
    donateUnited24: "UNITED24 ↗",
  },
  og: {
    alt: "hart.crimea.ua — Sheet-metal drawings in 60 seconds. No CAD skills needed.",
    headline: "Sheet-metal drawings in 60 seconds.",
    sub: "No CAD skills · DXF + PDF · 10 free exports/month",
  },
};

export const dictionaries = { uk, en } as const;
