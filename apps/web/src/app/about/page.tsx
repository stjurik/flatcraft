import { Gift, Github, Heart, type LucideIcon } from "@flatcraft/ui";

import { TemplateThumb } from "../../components/template-thumb";

export const metadata = {
  title: "Про hart.crimea.ua",
  description:
    "BETA-платформа параметричного CAD для листового металу. Безкоштовно. На підтримку ЗСУ.",
};

const GITHUB_ISSUES_URL = "https://github.com/stjurik/flatcraft/issues";
const MONOBANK_JAR_URL = "https://send.monobank.ua/jar/A1u3M7VqQz";
const UNITED24_URL = "https://u24.gov.ua/";
const FEEDBACK_EMAIL = "feedback@hart.crimea.ua";
const DISCORD_URL = "https://discord.gg/Zx88FAFtkS";

interface FreeCard {
  readonly icon: LucideIcon;
  readonly title: string;
  readonly body: string;
}

const FREE_CARDS: ReadonlyArray<FreeCard> = [
  {
    icon: Gift,
    title: "BETA — без обмежень",
    body: "На час BETA-релізу все безкоштовно. Реєстрація не потрібна — відкрив, налаштував, скачав.",
  },
  {
    icon: Heart,
    title: "Неприбутковий проєкт",
    body: "Платформа не заробляє на вас. Якщо хочете подякувати — задонатіть напряму на ЗСУ.",
  },
  {
    icon: Github,
    title: "Open Source MIT",
    body: "Код відкритий: github.com/stjurik/flatcraft. Можна форкнути, вивчати, контриб'ютити.",
  },
];

export default function AboutPage() {
  return (
    <main className="bg-bg">
      <div className="mx-auto flex max-w-5xl flex-col gap-16 px-4 py-12 sm:py-16">
        {/* Hero */}
        <section data-testid="about-hero" className="flex flex-col gap-4">
          <p className="text-fg-subtle text-xs font-semibold uppercase tracking-wide">BETA</p>
          <h1 className="font-display text-fg text-3xl font-semibold sm:text-4xl">
            Креслення листового металу — безкоштовно і без CAD
          </h1>
          <p className="text-fg-muted max-w-2xl text-lg">
            BETA-проєкт для DIY-спільноти, малого бізнесу і архітекторів.
          </p>
        </section>

        {/* Section 1 — Що це таке */}
        <section
          data-testid="about-what"
          className="grid grid-cols-1 items-center gap-8 md:grid-cols-2"
        >
          <div className="flex flex-col gap-4">
            <h2 className="font-display text-fg text-2xl font-semibold">Що це таке</h2>
            <p className="text-fg-muted">
              hart — це веб-конструктор типових виробів з листового металу: кронштейнів, полиць,
              кутників, перфорованих панелей. Ви задаєте розміри повзунками й полями, бачите
              3D-прев'ю у реальному часі — і одразу отримуєте готові креслення.
            </p>
            <p className="text-fg-muted">
              CAD-навички не потрібні. Усю «важку» геометрію — розгортку з урахуванням k-фактора,
              перевірку радіусів гибки під вашу товщину й матеріал — платформа рахує сама.
            </p>
            <p className="text-fg-muted">
              На виході — DXF (для лазерного різання) і PDF (з розгорткою, таблицею гибів і
              специфікацією). Файли можна нести на будь-яке виробництво лазерного різання та гибки.
            </p>
          </div>
          <div className="text-fg-muted bg-surface-sunken border-border mx-auto aspect-[4/3] w-full max-w-sm rounded-md border p-6">
            <TemplateThumb slug="l_bracket" />
          </div>
        </section>

        {/* Section 2 — Безкоштовно. Чому? */}
        <section data-testid="about-free" className="flex flex-col gap-6">
          <h2 className="font-display text-fg text-2xl font-semibold">Безкоштовно. Чому?</h2>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
            {FREE_CARDS.map(({ icon: Icon, title, body }) => (
              <div
                key={title}
                className="border-border bg-bg-elevated flex flex-col gap-3 rounded-md border p-5"
              >
                <Icon className="text-primary h-6 w-6" aria-hidden="true" />
                <h3 className="text-fg font-semibold">{title}</h3>
                <p className="text-fg-muted text-sm">{body}</p>
              </div>
            ))}
          </div>
        </section>

        {/* Section 3 — Підтримати ЗСУ */}
        <section
          data-testid="about-zsu"
          className="border-border bg-surface-sunken flex flex-col gap-5 rounded-md border p-6 sm:p-8"
        >
          <h2 className="font-display text-fg text-2xl font-semibold">Підтримати ЗСУ</h2>
          <div className="flex flex-col gap-3 sm:flex-row">
            <a
              data-testid="about-donate-monobank"
              href={MONOBANK_JAR_URL}
              target="_blank"
              rel="noopener noreferrer"
              className="bg-zsu-bg text-zsu-fg hover:bg-zsu-bg-hover min-h-tap inline-flex items-center justify-center gap-2 rounded-md px-6 py-3 text-base font-medium"
            >
              <Heart className="h-5 w-5" aria-hidden="true" />
              Monobank банка ↗
            </a>
            <a
              data-testid="about-donate-united24"
              href={UNITED24_URL}
              target="_blank"
              rel="noopener noreferrer"
              className="border-border-strong text-fg hover:bg-surface-muted min-h-tap inline-flex items-center justify-center gap-2 rounded-md border px-6 py-3 text-base font-medium"
            >
              UNITED24 ↗
            </a>
          </div>
          <p className="text-fg-subtle text-sm">
            Платформа не виступає одержувачем коштів — донати йдуть напряму через офіційні фонди.
          </p>
        </section>

        {/* Section 4 — Зворотний зв'язок */}
        <section data-testid="about-feedback" className="flex flex-col gap-4">
          <h2 className="font-display text-fg text-2xl font-semibold">Зворотний зв'язок</h2>
          <p className="text-fg-muted">
            Знайшли помилку в кресленні чи маєте ідею? Напишіть — у BETA кожен відгук цінний.
          </p>
          <ul className="flex flex-col gap-2">
            <li>
              <a
                data-testid="about-feedback-email"
                href={`mailto:${FEEDBACK_EMAIL}`}
                className="text-primary hover:text-primary-hover min-h-tap inline-flex items-center text-sm font-medium"
              >
                {FEEDBACK_EMAIL}
              </a>
            </li>
            <li>
              <a
                data-testid="about-feedback-github"
                href={GITHUB_ISSUES_URL}
                target="_blank"
                rel="noopener noreferrer"
                className="text-primary hover:text-primary-hover min-h-tap inline-flex items-center text-sm font-medium"
              >
                GitHub Issues ↗
              </a>
            </li>
            <li>
              <a
                data-testid="about-feedback-discord"
                href={DISCORD_URL}
                target="_blank"
                rel="noopener noreferrer"
                className="text-primary hover:text-primary-hover min-h-tap inline-flex items-center text-sm font-medium"
              >
                Discord-спільнота ↗
              </a>
            </li>
          </ul>
        </section>
      </div>
    </main>
  );
}
