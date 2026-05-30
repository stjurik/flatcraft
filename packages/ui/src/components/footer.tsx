import { Button } from "../primitives/button.js";
import { Logo } from "./logo.js";
import { UkraineStripe } from "./ukraine-stripe.js";

interface FooterProps {
  /** Monobank Banka або UNITED24 — посилання на банку ЗСУ. */
  zsuDonateUrl?: string;
}

const DEFAULT_ZSU_URL = "https://send.monobank.ua/jar/A1u3M7VqQz";

/**
 * Базовий футер: UkraineStripe (2px) одразу над content-блоком, далі
 * — лого, короткий positioning, donate-CTA, copyright. Mobile-first:
 * stack на xs, two-col на md+.
 */
export function Footer({ zsuDonateUrl = DEFAULT_ZSU_URL }: FooterProps = {}) {
  const year = new Date().getFullYear();

  return (
    <footer data-testid="footer" className="mt-auto">
      <UkraineStripe />
      <div className="bg-bg-elevated">
        <div className="mx-auto flex max-w-6xl flex-col gap-6 px-4 py-8 md:flex-row md:items-center md:justify-between md:gap-4">
          <div className="flex flex-col gap-2">
            <Logo size="md" />
            <p className="text-fg-muted max-w-md text-sm">
              Соціальна платформа для виробів з листового металу. Без CAD-навичок — DXF, PDF, STEP
              безкоштовно.
            </p>
            <p className="text-fg-subtle text-xs">© {year} hart.crimea.ua · MIT License</p>
          </div>
          <Button asChild variant="zsu" size="md">
            <a
              href={zsuDonateUrl}
              target="_blank"
              rel="noopener noreferrer"
              data-testid="zsu-donate"
            >
              Підтримати ЗСУ
            </a>
          </Button>
        </div>
      </div>
    </footer>
  );
}
