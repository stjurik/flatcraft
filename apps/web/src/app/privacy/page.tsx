/**
 * /privacy — Politica приватності (UA, драфт до legal-review).
 *
 * Зміст будується з 8 фактичних інваріантів платформи (ADR-032, ADR-011,
 * CLAUDE.md §8, docs/04_RISKS.md R-05/R-09). НЕ юридичний документ —
 * помітний драфт-банер попереджає користувача. Фінальна версія — після
 * рев'ю юристом (Roadmap 5.4).
 *
 * EN-версія — `/privacy/en` (окремий route з дублем контенту; i18n-фреймворк
 * не введено у цьому PR — див. PLAN.md WP3).
 */
import Link from "next/link";

import { localeAlternates } from "../../i18n/hreflang";

export const metadata = {
  title: "Політика приватності · hart.crimea.ua",
  description:
    "Як платформа поводиться з даними: без трекінг-cookies, без обов'язкової реєстрації, дані в Україні.",
  alternates: localeAlternates("uk", "/privacy", "/privacy/en"),
};

interface Section {
  readonly id: string;
  readonly title: string;
  readonly body: string;
}

const SECTIONS: ReadonlyArray<Section> = [
  {
    id: "pii",
    title: "1. Мінімум персональних даних",
    body:
      "Ми не збираємо email, IP-адреси чи будь-які персональні дані у продуктовій телеметрії. " +
      "Кожна подія (запит на експорт, помилка валідації, завершення експорту) записується без ідентифікатора " +
      "користувача. Замість цього — псевдонім `session_hash` з денним salt'ом: технічна метрика унікальності " +
      "сесій, яка не дозволяє нас або третіх сторін відстежувати конкретну людину між днями.",
  },
  {
    id: "cookies",
    title: "2. Без трекінг-cookies",
    body:
      "Аналітика — Umami self-hosted у нашому ДЦ (cookie-less: жоден трекінг-cookie не встановлюється, " +
      "жоден зовнішній сервіс не отримує ваш браузерний fingerprint). GDPR consent-banner тут не потрібен. " +
      "Єдина cookie на платформі — `hart_locale` (функціональна, не аналітична): запам'ятовує вибір мови " +
      "(українська/англійська), термін дії 1 рік, без персональних даних. Технічні cookies " +
      "(auth-сесія, CSRF-токен) з'являться пізніше, коли додамо реєстрацію (Roadmap Phase 3).",
  },
  {
    id: "sentry",
    title: "3. Технічні звіти про помилки",
    body:
      "Коли щось ламається в браузері/сервері, ми надсилаємо технічний звіт у Sentry (SaaS). Перед відправкою " +
      "спеціальний фільтр `beforeSend` викидає з звіту email, IP, cookies і будь-які потенційно чутливі " +
      "заголовки. У звіті лишається лише stack-trace і технічний контекст — не персональні дані.",
  },
  {
    id: "location",
    title: "4. Де живуть дані застосунку",
    body:
      "База даних, кеш, черга завдань, згенеровані креслення тимчасово — усе на єдиному сервері у ДЦ Mirohost " +
      "у Києві (Україна). Ми свідомо обрали українського хостера для суверенітету даних (ADR-011).",
  },
  {
    id: "backups",
    title: "5. Шифровані бекапи у Cloudflare R2",
    body:
      "Щоденні бекапи бази даних (03:00 за Києвом) шифруються локально (age-encryption) перед заливкою у " +
      "Cloudflare R2 (S3-сумісне об'єктне сховище). Cloudflare — поза Україною, але дані у R2 нечитабельні " +
      "без нашого приватного ключа, який зберігається окремо від vault'у.",
  },
  {
    id: "donations",
    title: "6. Донати — напряму у фонди ЗСУ",
    body:
      "Платформа неприбуткова і НЕ приймає жодних коштів. Кнопки «Підтримати ЗСУ» ведуть напряму на " +
      "Monobank Banka або UNITED24 — офіційні збори з прозорою звітністю. Ми лише посередник посилання; " +
      "жодна транзакція не проходить через наш банківський рахунок (бо його немає).",
  },
  {
    id: "drawings",
    title: "7. Креслення — рекомендаційні",
    body:
      "DXF/PDF/STEP, які генерує платформа, — це стартова точка для замовлення на виробництві, а не готовий " +
      "інженерний документ. Перед виготовленням креслення має перевірити людина, яка розуміє матеріал, гибку " +
      "і специфіку конкретного верстата. Ми не несемо відповідальності за брак, викликаний невідповідністю " +
      "згенерованих параметрів реальному виробничому процесу.",
  },
  {
    id: "uptime",
    title: "8. Best-effort uptime, без SLA",
    body:
      "Це соціальний проєкт, який працює на одному сервері (2 vCPU / 4 GB) без failover. Ми стараємось " +
      "тримати платформу доступною цілодобово, але не даємо жодних гарантій щодо часу відповіді, аптайму, " +
      "цілісності даних чи довговічності креслень у сховищі. Якщо ваш процес вимагає SLA — використовуйте " +
      "локальний CAD або замовляйте у промислового підрядника.",
  },
];

export default function PrivacyPage() {
  return (
    <div className="bg-bg mx-auto flex w-full max-w-3xl flex-col gap-8 px-4 py-10 md:py-16">
      <div
        data-testid="privacy-draft-banner"
        className="border-warning bg-warning-surface rounded-lg border-2 p-4"
      >
        <p className="text-warning-foreground text-sm font-semibold">
          Драфт. Не є юридичною консультацією; фінальна версія — після рев'ю юристом (Roadmap 5.4).
        </p>
      </div>

      <header data-testid="privacy-hero" className="flex flex-col gap-3">
        <h1 className="text-fg text-3xl font-bold md:text-4xl">Політика приватності</h1>
        <p className="text-fg-muted">
          Як ця платформа поводиться з вашими даними — сформульовано з реального стану коду, а не за
          абстрактним шаблоном. English:{" "}
          <Link href="/privacy/en" className="underline">
            /privacy/en
          </Link>
          .
        </p>
      </header>

      <div className="flex flex-col gap-6">
        {SECTIONS.map((section) => (
          <section
            key={section.id}
            id={section.id}
            data-testid={`privacy-section-${section.id}`}
            className="flex flex-col gap-2"
          >
            <h2 className="text-fg text-xl font-semibold">{section.title}</h2>
            <p className="text-fg-muted leading-relaxed">{section.body}</p>
          </section>
        ))}
      </div>

      <footer className="border-border border-t pt-6">
        <p className="text-fg-subtle text-sm">
          Останнє оновлення: 2026-07-12. Питання —{" "}
          <a
            href="mailto:feedback@hart.crimea.ua"
            className="underline"
            data-testid="privacy-contact-email"
          >
            feedback@hart.crimea.ua
          </a>
          .
        </p>
      </footer>
    </div>
  );
}
