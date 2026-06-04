import Link from "next/link";

interface LinkItem {
  readonly label: string;
  readonly href: string;
  readonly external?: boolean;
}

interface ColumnDef {
  readonly title: string;
  readonly items: ReadonlyArray<LinkItem>;
}

const GITHUB_URL = "https://github.com/stjurik/flatcraft";

const COLUMNS: ReadonlyArray<ColumnDef> = [
  {
    title: "Продукт",
    items: [
      { label: "Шаблони", href: "/templates" },
      { label: "Про проєкт", href: "/about" },
      { label: "Розблокувати", href: "/soon" },
    ],
  },
  {
    title: "Спільнота",
    items: [
      { label: "GitHub ↗", href: GITHUB_URL, external: true },
      { label: "Discord", href: "/soon" },
      { label: "Telegram", href: "/soon" },
    ],
  },
  {
    title: "Юридичне",
    items: [
      { label: "Privacy", href: "/soon" },
      { label: "Terms", href: "/soon" },
      { label: "Cookies", href: "/soon" },
    ],
  },
];

/**
 * App-local site-links: контент-залежний (маршрути цього застосунку,
 * а не reusable UI primitive). Споживається у layout.tsx як `linksSlot`
 * футера. Tap-target ≥44px — через мінімальний padding по вертикалі.
 */
export function SiteLinks() {
  return (
    <nav
      data-testid="site-links"
      aria-label="Карта сайту"
      className="grid grid-cols-1 gap-6 sm:grid-cols-3 sm:gap-8"
    >
      {COLUMNS.map((col) => (
        <div key={col.title} className="flex flex-col gap-2">
          <h2 className="text-fg text-sm font-semibold uppercase tracking-wide">{col.title}</h2>
          <ul className="flex flex-col gap-1">
            {col.items.map((item) => (
              <li key={`${col.title}-${item.label}`}>
                {item.external ? (
                  <a
                    href={item.href}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-fg-muted hover:text-fg min-h-tap inline-flex items-center text-sm"
                  >
                    {item.label}
                  </a>
                ) : (
                  <Link
                    href={item.href}
                    className="text-fg-muted hover:text-fg min-h-tap inline-flex items-center text-sm"
                  >
                    {item.label}
                  </Link>
                )}
              </li>
            ))}
          </ul>
        </div>
      ))}
    </nav>
  );
}
