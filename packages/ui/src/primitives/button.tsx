import { Slot } from "@radix-ui/react-slot";
import { cva, type VariantProps } from "class-variance-authority";
import { forwardRef, type ButtonHTMLAttributes } from "react";

import { cn } from "../lib/cn.js";

/**
 * Base Button — варіанти + розміри. min-h-tap/min-w-tap = WCAG 2.5.5 (44×44).
 * Variant `zsu` — для donate-CTA у Footer (UA-blue, white text).
 */
const buttonVariants = cva(
  [
    "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-sm",
    "text-sm font-semibold transition-colors duration-fast ease-out",
    "focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2",
    "focus-visible:outline-ring/60",
    "disabled:pointer-events-none disabled:opacity-50",
    "min-h-tap min-w-tap",
  ],
  {
    variants: {
      variant: {
        default: "bg-primary text-primary-foreground hover:bg-primary-hover",
        secondary: "bg-surface-muted text-fg hover:bg-surface-sunken",
        outline: "border border-border-strong bg-bg text-fg hover:bg-surface-sunken",
        ghost: "text-fg hover:bg-surface-muted",
        destructive: "bg-danger text-danger-foreground hover:bg-danger/90",
        zsu: "bg-zsu-bg text-zsu-fg hover:bg-zsu-bg-hover",
      },
      size: {
        // "sm" все ще ≥ tap-target через base class (min-h-tap).
        sm: "px-3 text-xs",
        md: "px-4 py-2",
        lg: "px-6 py-3 text-base",
        icon: "h-tap w-tap p-0",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "md",
    },
  },
);

export type ButtonVariant = NonNullable<VariantProps<typeof buttonVariants>["variant"]>;

export interface ButtonProps
  extends ButtonHTMLAttributes<HTMLButtonElement>, VariantProps<typeof buttonVariants> {
  asChild?: boolean;
}

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(function Button(
  { className, variant, size, asChild = false, ...props },
  ref,
) {
  const Comp = asChild ? Slot : "button";
  return <Comp ref={ref} className={cn(buttonVariants({ variant, size, className }))} {...props} />;
});

export { buttonVariants };
