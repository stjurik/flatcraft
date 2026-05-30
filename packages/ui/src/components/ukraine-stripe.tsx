import { cn } from "../lib/cn.js";

interface UkraineStripeProps {
  className?: string;
}

/**
 * 2px український прапор як тонка стрічка — за стандартом розміщується
 * безпосередньо над <Footer>. Inline-style потрібен, щоб гарантувати
 * саме 2px заввишки (інваріант, перевіряється у Playwright).
 *
 * `role="img"` + aria-label — щоб screen-reader не пропускав декорацію
 * мовчки (це смисловий елемент: позиція платформи).
 */
export function UkraineStripe({ className }: UkraineStripeProps) {
  return (
    <div
      data-testid="ukraine-stripe"
      role="img"
      aria-label="Прапор України"
      className={cn("w-full", className)}
      style={{
        height: "2px",
        background:
          "linear-gradient(to right, var(--color-ua-blue) 50%, var(--color-ua-yellow) 50%)",
      }}
    />
  );
}
