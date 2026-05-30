import type { Config } from "tailwindcss";

/**
 * Tailwind theme — mapping для design tokens з globals.css.
 * Mobile-first: дефолтні утиліти = smallest viewport, breakpoints розширюють.
 * Single light theme (без .dark). Див. docs/10_DESIGN_SYSTEM.md і ADR-016.
 */
const tokenColor = (name: string): string => `oklch(var(${name}) / <alpha-value>)`;

const config: Config = {
  content: ["./src/**/*.{ts,tsx}", "../../packages/ui/src/**/*.{ts,tsx}"],
  theme: {
    // НЕ extend для screens — переписуємо повністю, щоб ввести `xs`
    // як baseline-mobile (360px), без дефолтного 640px-старту.
    screens: {
      xs: "360px",
      sm: "640px",
      md: "768px",
      lg: "1024px",
      xl: "1280px",
      "2xl": "1536px",
    },
    extend: {
      fontFamily: {
        sans: ["var(--font-inter)", "system-ui", "sans-serif"],
        display: ["var(--font-inter)", "system-ui", "sans-serif"],
        mono: ["var(--font-jetbrains-mono)", "ui-monospace", "monospace"],
      },
      colors: {
        bg: tokenColor("--color-bg"),
        "bg-elevated": tokenColor("--color-bg-elevated"),
        "surface-sunken": tokenColor("--color-surface-sunken"),
        "surface-muted": tokenColor("--color-surface-muted"),
        overlay: tokenColor("--color-overlay"),
        fg: tokenColor("--color-fg"),
        "fg-muted": tokenColor("--color-fg-muted"),
        "fg-subtle": tokenColor("--color-fg-subtle"),
        primary: {
          DEFAULT: tokenColor("--color-primary"),
          hover: tokenColor("--color-primary-hover"),
          foreground: tokenColor("--color-primary-fg"),
        },
        accent: {
          DEFAULT: tokenColor("--color-accent"),
          foreground: tokenColor("--color-accent-fg"),
        },
        border: tokenColor("--color-border"),
        "border-strong": tokenColor("--color-border-strong"),
        ring: tokenColor("--color-ring"),
        success: {
          DEFAULT: tokenColor("--color-success"),
          foreground: tokenColor("--color-success-fg"),
          surface: tokenColor("--color-success-surface"),
        },
        warning: {
          DEFAULT: tokenColor("--color-warning"),
          foreground: tokenColor("--color-warning-fg"),
          surface: tokenColor("--color-warning-surface"),
        },
        danger: {
          DEFAULT: tokenColor("--color-danger"),
          foreground: tokenColor("--color-danger-fg"),
          surface: tokenColor("--color-danger-surface"),
        },
        info: {
          DEFAULT: tokenColor("--color-info"),
          foreground: tokenColor("--color-info-fg"),
          surface: tokenColor("--color-info-surface"),
        },
        // UA-flag і ЗСУ — точні sRGB hex; alpha через rgba-utility не
        // потрібна (плашки суцільні).
        "ua-blue": "var(--color-ua-blue)",
        "ua-yellow": "var(--color-ua-yellow)",
        "zsu-bg": "var(--color-zsu-bg)",
        "zsu-bg-hover": "var(--color-zsu-bg-hover)",
        "zsu-fg": "var(--color-zsu-fg)",
      },
      borderRadius: {
        xs: "var(--radius-xs)",
        sm: "var(--radius-sm)",
        md: "var(--radius-md)",
        lg: "var(--radius-lg)",
      },
      boxShadow: {
        sm: "var(--shadow-sm)",
        md: "var(--shadow-md)",
        lg: "var(--shadow-lg)",
      },
      transitionDuration: {
        fast: "var(--duration-fast)",
        base: "var(--duration-base)",
        slow: "var(--duration-slow)",
      },
      transitionTimingFunction: {
        out: "var(--ease-out)",
      },
      minHeight: {
        tap: "var(--tap-target-min)",
      },
      minWidth: {
        tap: "var(--tap-target-min)",
      },
    },
  },
  plugins: [],
};

export default config;
