import {
  AlertCircle,
  ArrowRight,
  Button,
  Check,
  ChevronDown,
  Download,
  Edit3,
  FileDown,
  Footer,
  Info,
  Logo,
  Minus,
  Plus,
  RotateCcw,
  Settings,
  Square,
  Trash2,
  Undo2,
  UkraineStripe,
  X,
  XCircle,
  contrastRatio,
} from "@flatcraft/ui";
import type { Metadata } from "next";
import { notFound } from "next/navigation";

import { DialogDemo } from "./dialog-demo";
import { MotionDemo } from "./motion-demo";
import { ViewportSwitcher } from "./viewport-switcher";

export const metadata: Metadata = {
  title: "Styleguide · hart",
  robots: { index: false, follow: false },
};

// Build-time inlined; в production цей page стає статичним 404.
const IS_DEV = process.env.NEXT_PUBLIC_ENV === "dev";

const SECTIONS: Array<{ id: string; title: string }> = [
  { id: "brand", title: "1. Brand & Logo" },
  { id: "typography", title: "2. Typography" },
  { id: "colors", title: "3. Color tokens" },
  { id: "buttons", title: "4. Buttons" },
  { id: "forms", title: "5. Forms" },
  { id: "cards", title: "6. Cards & Surfaces" },
  { id: "badges", title: "7. Badges & Tags" },
  { id: "overlays", title: "8. Overlays" },
  { id: "icons", title: "9. Icons" },
  { id: "motion", title: "10. Motion" },
  { id: "footer", title: "11. Footer & UA stripe" },
  { id: "viewport", title: "12. Viewport switcher" },
];

/**
 * `oklch(L C H)` помічник: токен у `globals.css` зберігається як
 * "L C H" (без обгортки) — тут перетворюємо назад у валідний CSS-color
 * для перевірки контрасту через contrastRatio().
 */
const oklch = (lch: string): string => `oklch(${lch})`;

const COLOR_TOKENS: Array<{ name: string; value: string; usage: string }> = [
  { name: "--color-bg", value: "0.985 0.005 80", usage: "Page background" },
  { name: "--color-bg-elevated", value: "1 0 0", usage: "Cards, header bar" },
  { name: "--color-surface-sunken", value: "0.965 0.008 80", usage: "Input fields" },
  { name: "--color-surface-muted", value: "0.945 0.01 80", usage: "Code, table stripes" },
  { name: "--color-fg", value: "0.22 0.015 50", usage: "Body text" },
  { name: "--color-fg-muted", value: "0.42 0.012 50", usage: "Secondary text" },
  { name: "--color-fg-subtle", value: "0.55 0.01 50", usage: "Placeholders, captions" },
  { name: "--color-primary", value: "0.66 0.17 50", usage: "Primary CTA, brand" },
  { name: "--color-primary-hover", value: "0.6 0.18 48", usage: "Primary hover" },
  { name: "--color-accent", value: "0.55 0.08 220", usage: "Secondary CTA" },
  { name: "--color-border", value: "0.88 0.008 70", usage: "Thin dividers" },
  { name: "--color-border-strong", value: "0.78 0.01 70", usage: "Input borders" },
  { name: "--color-success", value: "0.5 0.14 145", usage: "Success badges/buttons" },
  { name: "--color-warning", value: "0.78 0.14 85", usage: "Warning highlights" },
  { name: "--color-danger", value: "0.52 0.18 25", usage: "Destructive, errors" },
  { name: "--color-info", value: "0.5 0.11 240", usage: "Info banners" },
];

const HEX_TOKENS: Array<{ name: string; hex: string; usage: string }> = [
  { name: "--color-ua-blue", hex: "#0057B7", usage: "UA flag, ЗСУ button bg" },
  { name: "--color-ua-yellow", hex: "#FFD700", usage: "UA flag" },
  { name: "--color-zsu-bg-hover", hex: "#004A99", usage: "ЗСУ hover" },
];

function ContrastBadge({ ratio }: { ratio: number }) {
  const passAA = ratio >= 4.5;
  const passLarge = ratio >= 3;
  const label = passAA ? "AA" : passLarge ? "AA Large" : "Fail";
  const className = passAA
    ? "bg-success-surface text-success"
    : passLarge
      ? "bg-warning-surface text-warning-foreground"
      : "bg-danger-surface text-danger";
  return (
    <span
      className={`rounded-xs inline-flex items-center px-1.5 py-0.5 font-mono text-xs ${className}`}
    >
      {ratio.toFixed(2)}:1 · {label}
    </span>
  );
}

function SectionHeader({ id, title }: { id: string; title: string }) {
  return (
    <h2
      id={id}
      className="border-border font-display text-fg scroll-mt-20 border-b pb-2 text-2xl font-semibold"
    >
      {title}
    </h2>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="flex flex-col gap-1.5">
      <span className="text-fg text-sm font-medium">{label}</span>
      {children}
    </label>
  );
}

const INPUT_BASE =
  "min-h-tap w-full rounded-sm border border-border-strong bg-bg-elevated px-3 text-sm text-fg placeholder:text-fg-subtle focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring/60 disabled:cursor-not-allowed disabled:bg-surface-muted disabled:text-fg-subtle";

const ICONS = [
  { Icon: Download, name: "download" },
  { Icon: FileDown, name: "file-down" },
  { Icon: Edit3, name: "edit" },
  { Icon: Settings, name: "settings" },
  { Icon: Plus, name: "plus" },
  { Icon: Minus, name: "minus" },
  { Icon: X, name: "x" },
  { Icon: Check, name: "check" },
  { Icon: ChevronDown, name: "chevron-down" },
  { Icon: ArrowRight, name: "arrow-right" },
  { Icon: AlertCircle, name: "alert-circle" },
  { Icon: Info, name: "info" },
  { Icon: XCircle, name: "x-circle" },
  { Icon: Undo2, name: "undo" },
  { Icon: RotateCcw, name: "rotate" },
  { Icon: Trash2, name: "trash" },
  { Icon: Square, name: "square" },
];

export default function StyleguidePage() {
  if (!IS_DEV) {
    notFound();
  }

  // Контрасти обчислюються на сервері й вшиваються у HTML.
  const bgColor = oklch("0.985 0.005 80");
  const elevatedColor = oklch("1 0 0");

  return (
    <div className="bg-bg text-fg min-h-screen">
      <div className="mx-auto grid max-w-6xl gap-8 px-4 py-8 md:grid-cols-[200px_1fr]">
        {/* — Side nav (md+) / sticky top (xs/sm) — */}
        <nav
          aria-label="Sections"
          className="border-border bg-bg/95 sticky top-0 z-10 -mx-4 flex flex-wrap gap-2 border-b px-4 py-3 backdrop-blur md:static md:mx-0 md:flex-col md:gap-1 md:border-0 md:bg-transparent md:px-0 md:py-0 md:backdrop-blur-none"
        >
          {SECTIONS.map((s) => (
            <a
              key={s.id}
              href={`#${s.id}`}
              className="rounded-xs text-fg-muted duration-fast hover:text-fg px-2 py-1 text-xs transition-colors ease-out md:text-sm"
            >
              {s.title}
            </a>
          ))}
        </nav>

        <main className="flex flex-col gap-12">
          <header className="flex flex-col gap-2">
            <p className="text-fg-subtle text-xs uppercase tracking-wide">Phase 2.11</p>
            <h1 className="font-display xs:text-4xl text-3xl font-semibold">Design System</h1>
            <p className="text-fg-muted max-w-2xl">
              Warm industrial · single light theme · mobile-first. Внутрішня сторінка, доступна лише
              у dev (NEXT_PUBLIC_ENV=dev).
            </p>
          </header>

          {/* 1 ─────────── Brand & Logo ─────────────────────── */}
          <section className="flex flex-col gap-4">
            <SectionHeader id="brand" title="1. Brand & Logo" />
            <div className="border-border bg-bg-elevated flex flex-col gap-6 rounded-md border p-6">
              <Logo size="sm" />
              <Logo size="md" />
              <Logo size="lg" />
            </div>
          </section>

          {/* 2 ─────────── Typography ────────────────────────── */}
          <section className="flex flex-col gap-4">
            <SectionHeader id="typography" title="2. Typography" />
            <div className="border-border bg-bg-elevated grid gap-4 rounded-md border p-6">
              <p className="font-display text-4xl font-semibold leading-tight">
                H1 / Display 4xl · 36/40 · 600
              </p>
              <p className="font-display text-3xl font-semibold leading-tight">
                H2 / Display 3xl · 30/36 · 600
              </p>
              <p className="text-2xl font-semibold">H3 · 24/32 · 600</p>
              <p className="text-xl font-semibold">H4 · 20/28 · 600</p>
              <p className="text-base">Body · Inter 16/24 · 400</p>
              <p className="text-fg-muted text-sm">Small · 14/20 · text-fg-muted</p>
              <p className="text-fg-subtle text-xs">Caption · 12/16 · text-fg-subtle</p>
              <code className="bg-surface-muted text-fg rounded-sm px-2 py-1 font-mono text-sm">
                {`const k = 0.40; // JetBrains Mono`}
              </code>
            </div>
          </section>

          {/* 3 ─────────── Color tokens ──────────────────────── */}
          <section className="flex flex-col gap-4">
            <SectionHeader id="colors" title="3. Color tokens" />
            <p className="text-fg-muted text-sm">
              Контраст обчислюється до <code className="font-mono">--color-bg</code> (для тексту) і
              до <code className="font-mono">--color-fg</code> (для surface-fg pair-ів) через{" "}
              <code className="font-mono">contrastRatio()</code> з @flatcraft/ui.
            </p>
            <div className="border-border bg-bg-elevated overflow-x-auto rounded-md border">
              <table className="w-full min-w-[640px] border-collapse text-sm">
                <thead className="bg-surface-muted text-fg-muted text-left text-xs uppercase tracking-wide">
                  <tr>
                    <th className="px-3 py-2">Swatch</th>
                    <th className="px-3 py-2">Token</th>
                    <th className="px-3 py-2">OKLCH</th>
                    <th className="px-3 py-2">Usage</th>
                    <th className="px-3 py-2">vs bg</th>
                    <th className="px-3 py-2">vs fg</th>
                  </tr>
                </thead>
                <tbody>
                  {COLOR_TOKENS.map(({ name, value, usage }) => {
                    const color = oklch(value);
                    const vsBg = contrastRatio(color, bgColor);
                    const vsFg = contrastRatio(color, oklch("0.22 0.015 50"));
                    return (
                      <tr key={name} className="border-border border-t">
                        <td className="px-3 py-2">
                          <span
                            className="rounded-xs ring-border block h-6 w-12 ring-1"
                            style={{ background: color }}
                          />
                        </td>
                        <td className="text-fg px-3 py-2 font-mono text-xs">{name}</td>
                        <td className="text-fg-muted px-3 py-2 font-mono text-xs">{value}</td>
                        <td className="text-fg-muted px-3 py-2">{usage}</td>
                        <td className="px-3 py-2">
                          <ContrastBadge ratio={vsBg} />
                        </td>
                        <td className="px-3 py-2">
                          <ContrastBadge ratio={vsFg} />
                        </td>
                      </tr>
                    );
                  })}
                  {HEX_TOKENS.map(({ name, hex, usage }) => {
                    const vsBg = contrastRatio(hex, bgColor);
                    const vsFg = contrastRatio(hex, elevatedColor);
                    return (
                      <tr key={name} className="border-border border-t">
                        <td className="px-3 py-2">
                          <span
                            className="rounded-xs ring-border block h-6 w-12 ring-1"
                            style={{ background: hex }}
                          />
                        </td>
                        <td className="text-fg px-3 py-2 font-mono text-xs">{name}</td>
                        <td className="text-fg-muted px-3 py-2 font-mono text-xs">{hex}</td>
                        <td className="text-fg-muted px-3 py-2">{usage}</td>
                        <td className="px-3 py-2">
                          <ContrastBadge ratio={vsBg} />
                        </td>
                        <td className="px-3 py-2">
                          <ContrastBadge ratio={vsFg} />
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </section>

          {/* 4 ─────────── Buttons ───────────────────────────── */}
          <section className="flex flex-col gap-4">
            <SectionHeader id="buttons" title="4. Buttons" />
            <p className="text-fg-muted text-sm">
              Усі варіанти мають <code className="font-mono">min-h-tap min-w-tap</code> (44×44 —
              WCAG 2.5.5).
            </p>
            <div className="border-border bg-bg-elevated grid gap-6 rounded-md border p-6">
              {(["default", "secondary", "outline", "ghost", "destructive", "zsu"] as const).map(
                (variant) => (
                  <div key={variant} className="flex flex-col gap-3">
                    <h3 className="text-fg-muted text-sm font-semibold uppercase tracking-wide">
                      {variant}
                    </h3>
                    <div className="flex flex-wrap items-center gap-3">
                      <Button variant={variant} size="sm">
                        Small
                      </Button>
                      <Button variant={variant} size="md">
                        Default
                      </Button>
                      <Button variant={variant} size="lg">
                        Large
                      </Button>
                      <Button variant={variant} size="icon" aria-label="icon">
                        <Plus className="h-4 w-4" />
                      </Button>
                      <Button variant={variant} disabled>
                        Disabled
                      </Button>
                    </div>
                  </div>
                ),
              )}
            </div>
          </section>

          {/* 5 ─────────── Forms ─────────────────────────────── */}
          <section className="flex flex-col gap-4">
            <SectionHeader id="forms" title="5. Forms" />
            <div className="border-border bg-bg-elevated grid gap-4 rounded-md border p-6 md:grid-cols-2">
              <Field label="Text input">
                <input type="text" className={INPUT_BASE} placeholder="placeholder" />
              </Field>
              <Field label="Disabled">
                <input type="text" className={INPUT_BASE} placeholder="disabled" disabled />
              </Field>
              <Field label="Invalid">
                <input
                  type="text"
                  defaultValue="800"
                  aria-invalid
                  className={`${INPUT_BASE} border-danger`}
                />
                <span className="text-danger text-xs">
                  Значення поза дозволеним діапазоном (0.5–8 мм)
                </span>
              </Field>
              <Field label="Select">
                <select className={INPUT_BASE} defaultValue="304">
                  <option value="304">Нержавійка AISI 304</option>
                  <option value="430">Нержавійка AISI 430</option>
                  <option value="amg5">Алюміній АМг5</option>
                </select>
              </Field>
              <Field label="Slider">
                <input
                  type="range"
                  min={0.5}
                  max={8}
                  step={0.1}
                  defaultValue={2}
                  className="h-tap accent-primary w-full"
                />
              </Field>
              <Field label="Textarea">
                <textarea
                  rows={3}
                  className={`${INPUT_BASE} resize-y py-2`}
                  placeholder="Нотатки до замовлення"
                />
              </Field>
              <label className="flex items-center gap-2">
                <input
                  type="checkbox"
                  className="border-border-strong accent-primary h-5 w-5 rounded-sm"
                  defaultChecked
                />
                <span className="text-sm">Я погоджуюсь з обробкою даних</span>
              </label>
              <fieldset className="flex flex-col gap-2">
                <legend className="text-sm font-medium">Орієнтація гиба</legend>
                <label className="flex items-center gap-2 text-sm">
                  <input type="radio" name="bend" defaultChecked className="accent-primary" />
                  Вгору
                </label>
                <label className="flex items-center gap-2 text-sm">
                  <input type="radio" name="bend" className="accent-primary" />
                  Вниз
                </label>
              </fieldset>
            </div>
          </section>

          {/* 6 ─────────── Cards & Surfaces ──────────────────── */}
          <section className="flex flex-col gap-4">
            <SectionHeader id="cards" title="6. Cards & Surfaces" />
            <div className="grid gap-4 md:grid-cols-2">
              <div className="bg-bg-elevated rounded-md p-4 shadow-sm">
                <p className="font-semibold">bg-elevated · shadow-sm · rounded-md</p>
                <p className="text-fg-muted text-sm">Базова картка шаблону.</p>
              </div>
              <div className="bg-bg-elevated rounded-lg p-4 shadow-md">
                <p className="font-semibold">shadow-md · rounded-lg</p>
                <p className="text-fg-muted text-sm">Hero / dialog.</p>
              </div>
              <div className="bg-surface-sunken rounded-md p-4">
                <p className="font-semibold">surface-sunken</p>
                <p className="text-fg-muted text-sm">Input field background.</p>
              </div>
              <div className="bg-surface-muted rounded-md p-4">
                <p className="font-semibold">surface-muted</p>
                <p className="text-fg-muted text-sm">Code / table stripes.</p>
              </div>
            </div>
          </section>

          {/* 7 ─────────── Badges ────────────────────────────── */}
          <section className="flex flex-col gap-4">
            <SectionHeader id="badges" title="7. Badges & Tags" />
            <div className="border-border bg-bg-elevated flex flex-wrap gap-3 rounded-md border p-6">
              <span className="rounded-xs bg-surface-muted text-fg inline-flex items-center gap-1 px-2 py-1 text-xs font-medium">
                neutral
              </span>
              <span className="rounded-xs bg-success-surface text-success inline-flex items-center gap-1 px-2 py-1 text-xs font-medium">
                <Check className="h-3 w-3" /> success
              </span>
              <span className="rounded-xs bg-warning-surface text-warning-foreground inline-flex items-center gap-1 px-2 py-1 text-xs font-medium">
                <AlertCircle className="h-3 w-3" /> warning
              </span>
              <span className="rounded-xs bg-danger-surface text-danger inline-flex items-center gap-1 px-2 py-1 text-xs font-medium">
                <XCircle className="h-3 w-3" /> danger
              </span>
              <span className="rounded-xs bg-info-surface text-info inline-flex items-center gap-1 px-2 py-1 text-xs font-medium">
                <Info className="h-3 w-3" /> info
              </span>
            </div>
          </section>

          {/* 8 ─────────── Overlays ──────────────────────────── */}
          <section className="flex flex-col gap-4">
            <SectionHeader id="overlays" title="8. Overlays" />
            <div className="border-border bg-bg-elevated flex flex-col gap-4 rounded-md border p-6">
              <div className="flex flex-col gap-2">
                <p className="text-sm font-semibold">Dialog (Radix, інтерактивний)</p>
                <DialogDemo />
              </div>
              <div className="flex flex-col gap-2">
                <p className="text-sm font-semibold">Toast (статична візуалка)</p>
                <div className="bg-fg text-bg-elevated flex items-start gap-3 rounded-md p-4 text-sm shadow-lg">
                  <Check className="text-success mt-0.5 h-4 w-4" />
                  <div>
                    <p className="font-semibold">Експорт готовий</p>
                    <p className="text-fg-subtle">l-bracket_v3.dxf — 18 KB</p>
                  </div>
                </div>
              </div>
              <div className="flex flex-col gap-2">
                <p className="text-sm font-semibold">Tooltip (статична візуалка)</p>
                <span className="bg-fg text-bg-elevated inline-flex w-fit items-center rounded-sm px-2 py-1 text-xs shadow-md">
                  K-фактор: 0.40 для м'яких сталей
                </span>
              </div>
            </div>
          </section>

          {/* 9 ─────────── Icons ─────────────────────────────── */}
          <section className="flex flex-col gap-4">
            <SectionHeader id="icons" title="9. Icons (lucide-react)" />
            <div className="border-border bg-bg-elevated flex flex-wrap gap-3 rounded-md border p-6">
              {ICONS.map(({ Icon, name }) => (
                <div
                  key={name}
                  className="text-fg-muted flex h-16 w-20 flex-col items-center justify-center gap-1 rounded-sm"
                >
                  <Icon className="h-5 w-5" />
                  <span className="font-mono text-[10px]">{name}</span>
                </div>
              ))}
            </div>
          </section>

          {/* 10 ────────── Motion ────────────────────────────── */}
          <section className="flex flex-col gap-4">
            <SectionHeader id="motion" title="10. Motion" />
            <div className="border-border bg-bg-elevated rounded-md border p-6">
              <MotionDemo />
            </div>
          </section>

          {/* 11 ────────── Footer & UA stripe ────────────────── */}
          <section className="flex flex-col gap-4">
            <SectionHeader id="footer" title="11. Footer & UA stripe" />
            <div className="border-border overflow-hidden rounded-md border">
              <div className="bg-bg-elevated text-fg-muted p-4 text-sm">
                ↓ UkraineStripe + Footer препорно вирівняні у нижній частині сторінок
              </div>
              <UkraineStripe />
              <div className="bg-bg-elevated">
                <Footer />
              </div>
            </div>
          </section>

          {/* 12 ────────── Viewport switcher info ────────────── */}
          <section className="flex flex-col gap-4">
            <SectionHeader id="viewport" title="12. Viewport switcher" />
            <p className="border-border bg-bg-elevated text-fg-muted rounded-md border p-6 text-sm">
              Кнопки <code className="font-mono">360 / 768 / 1280 / full</code> у нижньому правому
              куті обмежують ширину <code className="font-mono">&lt;body&gt;</code> і додають
              dashed-border, щоб одразу бачити, як токени adapt-яться. На production-build кнопок
              немає — сторінка доступна лише з{" "}
              <code className="font-mono">NEXT_PUBLIC_ENV=dev</code>.
            </p>
          </section>
        </main>
      </div>
      <ViewportSwitcher />
    </div>
  );
}
