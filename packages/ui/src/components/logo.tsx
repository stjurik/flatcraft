import { cn } from "../lib/cn.js";

interface LogoProps {
  className?: string;
  /** Розмір wordmark: sm (16px), md (20px, default), lg (28px). */
  size?: "sm" | "md" | "lg";
}

const SIZE_CLASS: Record<NonNullable<LogoProps["size"]>, string> = {
  sm: "text-base",
  md: "text-xl",
  lg: "text-2xl xs:text-3xl",
};

/**
 * Wordmark `hart.crimea.ua`. Перша частина (hart) — semibold у foreground,
 * друга (.crimea.ua) — regular з opacity 60%, того ж кегля.
 * Без іконки/символу: чистий типографський знак на старті бренду.
 */
export function Logo({ className, size = "md" }: LogoProps) {
  return (
    <span
      data-testid="logo"
      aria-label="hart.crimea.ua"
      className={cn(
        "font-display text-fg inline-flex items-baseline tracking-tight",
        SIZE_CLASS[size],
        className,
      )}
    >
      <span className="font-semibold">hart</span>
      <span className="font-normal opacity-60">.crimea.ua</span>
    </span>
  );
}
