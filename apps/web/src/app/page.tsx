import {
  Button,
  FileDown,
  Gift,
  Github,
  Heart,
  LayoutGrid,
  Sliders,
  type LucideIcon,
} from "@flatcraft/ui";
import Link from "next/link";

import { HeroLoopDemoLazy } from "../components/hero-loop-demo-lazy";

const GITHUB_URL = "https://github.com/stjurik/flatcraft";
const UNITED24_URL = "https://u24.gov.ua/";

export default function HomePage() {
  return (
    <>
      <Hero />
      <HowItWorks />
      <TrustRow />
    </>
  );
}

function Hero() {
  return (
    <section data-testid="hero" className="border-border bg-bg border-b">
      <div className="mx-auto grid max-w-7xl grid-cols-1 items-center gap-8 px-4 py-12 md:grid-cols-2 md:px-6 md:py-20 lg:gap-12">
        <header className="flex flex-col">
          <h1
            data-testid="hero-headline"
            className="font-display text-fg xs:text-5xl text-4xl font-semibold leading-tight md:text-6xl"
          >
            Креслення листового металу за 60 секунд. Без CAD-навичок.
          </h1>
          <p className="text-fg-muted mt-6 text-lg md:text-xl">
            Оберіть шаблон, налаштуйте розміри, скачайте DXF + PDF. Безкоштовно до 10 експортів на
            місяць.
          </p>
          <Button asChild variant="default" size="lg" className="mt-8 self-start">
            <Link href="/templates" prefetch data-testid="hero-cta">
              Переглянути шаблони →
            </Link>
          </Button>
          <a
            href="#how"
            data-testid="hero-anchor-how"
            className="text-fg-muted hover:text-fg min-h-tap mt-3 inline-flex items-center self-start text-sm underline-offset-4 hover:underline"
          >
            Як це працює ↓
          </a>
        </header>

        <div
          data-testid="hero-demo-frame"
          className="bg-bg-elevated border-border aspect-square overflow-hidden rounded-lg border shadow-md md:aspect-[4/3]"
        >
          <HeroLoopDemoLazy />
        </div>
      </div>
    </section>
  );
}

interface Step {
  readonly icon: LucideIcon;
  readonly title: string;
  readonly desc: string;
}

const STEPS: ReadonlyArray<Step> = [
  {
    icon: LayoutGrid,
    title: "Оберіть шаблон",
    desc: "5 готових виробів: L- і Z-кронштейни, кутник, настінна полиця, перфо-панель. Кожен — з валідним bend-allowance і шарами під лазер.",
  },
  {
    icon: Sliders,
    title: "Налаштуйте розміри",
    desc: "Повзунки і поля з обмеженнями вашої виробничої машини. Зміна параметра — миттєвий 3D-прев'ю; помилка валідації — підсвічене червоним поле.",
  },
  {
    icon: FileDown,
    title: "Скачайте креслення",
    desc: "DXF з 5 шарами для лазерної різки + PDF з розгорткою, таблицею гибів і BOM. STEP — за запитом.",
  },
];

function HowItWorks() {
  return (
    <section id="how" data-testid="section-how" className="bg-surface-sunken py-16 md:py-24">
      <div className="mx-auto max-w-7xl px-4 md:px-6">
        <div className="text-center">
          <h2 className="font-display text-fg text-3xl font-semibold md:text-4xl">Як це працює</h2>
          <p className="text-fg-muted mt-3 text-lg">Від ідеї до креслення — 60 секунд.</p>
        </div>
        <div className="mt-12 grid grid-cols-1 gap-6 md:grid-cols-3 md:gap-8">
          {STEPS.map((step, idx) => (
            <StepCard key={step.title} step={step} index={idx} />
          ))}
        </div>
      </div>
    </section>
  );
}

function StepCard({ step, index }: { step: Step; index: number }) {
  const Icon = step.icon;
  return (
    <div
      data-testid={`step-card-${index}`}
      className="bg-bg-elevated border-border hover:border-border-strong duration-fast rounded-lg border p-6 transition-colors ease-out md:p-8"
    >
      <Icon className="text-primary mb-4 h-10 w-10" aria-hidden="true" />
      <h3 className="text-fg mb-2 text-xl font-semibold">{step.title}</h3>
      <p className="text-fg-muted">{step.desc}</p>
    </div>
  );
}

interface Trust {
  readonly icon: LucideIcon;
  readonly text: string;
  readonly link?: { readonly label: string; readonly href: string };
}

const TRUSTS: ReadonlyArray<Trust> = [
  {
    icon: Gift,
    text: "10 експортів/міс безкоштовно",
  },
  {
    icon: Heart,
    text: "Донати йдуть на ЗСУ",
    link: { label: "UNITED24 ↗", href: UNITED24_URL },
  },
  {
    icon: Github,
    text: "Open Source · MIT",
    link: { label: "github.com/stjurik/flatcraft ↗", href: GITHUB_URL },
  },
];

function TrustRow() {
  return (
    <section data-testid="section-trust" className="bg-bg py-12 md:py-16">
      <div className="mx-auto flex max-w-5xl flex-wrap justify-center gap-8 px-4 md:gap-12">
        {TRUSTS.map((t, idx) => (
          <TrustBlock key={t.text} trust={t} index={idx} />
        ))}
      </div>
    </section>
  );
}

function TrustBlock({ trust, index }: { trust: Trust; index: number }) {
  const Icon = trust.icon;
  return (
    <div
      data-testid={`trust-block-${index}`}
      className="flex max-w-xs flex-col items-center text-center"
    >
      <Icon className="text-fg-muted mb-3 h-8 w-8" aria-hidden="true" />
      <span className="text-fg font-medium">{trust.text}</span>
      {trust.link ? (
        <a
          href={trust.link.href}
          target="_blank"
          rel="noopener noreferrer"
          className="text-fg-muted hover:text-fg min-h-tap mt-1 inline-flex items-center text-sm"
        >
          {trust.link.label}
        </a>
      ) : null}
    </div>
  );
}
