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

import { dictionaries } from "../i18n/dictionaries";
import { DEFAULT_LOCALE, type Locale } from "../i18n/locale";
import { HeroLoopDemoLazy } from "./hero-loop-demo-lazy";

const GITHUB_URL = "https://github.com/stjurik/flatcraft";
const UNITED24_URL = "https://u24.gov.ua/";

interface HomeContentProps {
  readonly locale?: Locale;
}

/**
 * Лендінг (ADR-037 §2) — спільний presentational-компонент, споживають
 * `app/page.tsx` (uk) і `app/en/page.tsx`. uk-текст byte-identical до
 * попереднього hardcoded варіанту (наявні e2e лишаються зеленими).
 */
export function HomeContent({ locale = DEFAULT_LOCALE }: HomeContentProps = {}) {
  const dict = dictionaries[locale].home;
  const templatesHref = locale === "en" ? "/en/templates" : "/templates";

  return (
    <>
      <Hero dict={dict} templatesHref={templatesHref} locale={locale} />
      <HowItWorks dict={dict} />
      <TrustRow dict={dict} />
    </>
  );
}

type HomeDict = (typeof dictionaries)["uk"]["home"];

function Hero({
  dict,
  templatesHref,
  locale,
}: {
  dict: HomeDict;
  templatesHref: string;
  locale: Locale;
}) {
  return (
    <section data-testid="hero" className="border-border bg-bg border-b">
      <div className="mx-auto grid max-w-7xl grid-cols-1 items-center gap-8 px-4 py-12 md:grid-cols-2 md:px-6 md:py-20 lg:gap-12">
        <header className="flex flex-col">
          <h1
            data-testid="hero-headline"
            className="font-display text-fg xs:text-5xl text-4xl font-semibold leading-tight md:text-6xl"
          >
            {dict.heroHeadline}
          </h1>
          <p className="text-fg-muted mt-6 text-lg md:text-xl">{dict.heroSub}</p>
          <Button asChild variant="default" size="lg" className="mt-8 self-start">
            <Link href={templatesHref} prefetch data-testid="hero-cta">
              {dict.heroCta}
            </Link>
          </Button>
          <a
            href="#how"
            data-testid="hero-anchor-how"
            className="text-fg-muted hover:text-fg min-h-tap mt-3 inline-flex items-center self-start text-sm underline-offset-4 hover:underline"
          >
            {dict.heroAnchorHow}
          </a>
        </header>

        <div
          data-testid="hero-demo-frame"
          className="bg-bg-elevated border-border aspect-square overflow-hidden rounded-lg border shadow-md md:aspect-[4/3]"
        >
          <HeroLoopDemoLazy locale={locale} />
        </div>
      </div>
    </section>
  );
}

interface StepView {
  readonly icon: LucideIcon;
  readonly title: string;
  readonly desc: string;
}

function HowItWorks({ dict }: { dict: HomeDict }) {
  const icons: readonly LucideIcon[] = [LayoutGrid, Sliders, FileDown];
  const steps: readonly StepView[] = dict.steps.map((s, i) => ({
    icon: icons[i] ?? LayoutGrid,
    title: s.title,
    desc: s.desc,
  }));

  return (
    <section id="how" data-testid="section-how" className="bg-surface-sunken py-16 md:py-24">
      <div className="mx-auto max-w-7xl px-4 md:px-6">
        <div className="text-center">
          <h2 className="font-display text-fg text-3xl font-semibold md:text-4xl">
            {dict.howTitle}
          </h2>
          <p className="text-fg-muted mt-3 text-lg">{dict.howSub}</p>
        </div>
        <div className="mt-12 grid grid-cols-1 gap-6 md:grid-cols-3 md:gap-8">
          {steps.map((step, idx) => (
            <StepCard key={step.title} step={step} index={idx} />
          ))}
        </div>
      </div>
    </section>
  );
}

function StepCard({ step, index }: { step: StepView; index: number }) {
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

interface TrustView {
  readonly icon: LucideIcon;
  readonly text: string;
  readonly link?: { readonly label: string; readonly href: string };
}

function TrustRow({ dict }: { dict: HomeDict }) {
  const trusts: readonly TrustView[] = [
    { icon: Gift, text: dict.trustExports },
    {
      icon: Heart,
      text: dict.trustDonate,
      link: { label: dict.trustDonateLink, href: UNITED24_URL },
    },
    {
      icon: Github,
      text: dict.trustOpenSource,
      link: { label: dict.trustGithubLink, href: GITHUB_URL },
    },
  ];

  return (
    <section data-testid="section-trust" className="bg-bg py-12 md:py-16">
      <div className="mx-auto flex max-w-5xl flex-wrap justify-center gap-8 px-4 md:gap-12">
        {trusts.map((t, idx) => (
          <TrustBlock key={t.text} trust={t} index={idx} />
        ))}
      </div>
    </section>
  );
}

function TrustBlock({ trust, index }: { trust: TrustView; index: number }) {
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
