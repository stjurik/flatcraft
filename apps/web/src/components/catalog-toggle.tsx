"use client";

import { SegmentedControl, type SegmentedControlOption } from "@flatcraft/ui";
import { useRouter, useSearchParams } from "next/navigation";
import { useEffect, useRef, useTransition } from "react";

import { dictionaries } from "../i18n/dictionaries";
import { DEFAULT_LOCALE, type Locale } from "../i18n/locale";
import { track } from "../lib/analytics";

type TabValue = "products" | "parts";

interface CatalogToggleProps {
  readonly value: TabValue;
  readonly counts: {
    readonly products: number;
    readonly parts: number;
  };
  readonly locale?: Locale;
}

/**
 * Client toggle для `/templates?tab=products|parts` (Phase 3.0 PR 3).
 *
 * Чому окремий client-component, а не inline у page.tsx: page.tsx — server
 * component (server-side fetch), потрібен useRouter/useSearchParams хук для
 * navigation. Server-side обчислюється `value` (з searchParams), а нaс
 * хвилює лише transition при кліку.
 *
 * `?tab=products` — default (не зберігається у URL), `?tab=parts` — explicit.
 * Це робить початковий URL `/templates` чистим. `locale` (ADR-037 §2)
 * будує URL на `/en/templates` замість `/templates`.
 */
export function CatalogToggle({ value, counts, locale = DEFAULT_LOCALE }: CatalogToggleProps) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [, startTransition] = useTransition();
  const dict = dictionaries[locale].catalog;
  const basePath = locale === "en" ? "/en/templates" : "/templates";

  // Воронка docs/11 §8: перший крок — перегляд каталогу (fire-once на mount).
  // CatalogToggle рендериться на кожному вигляді `/templates`.
  const catalogFiredRef = useRef(false);
  useEffect(() => {
    if (catalogFiredRef.current) return;
    catalogFiredRef.current = true;
    track("catalog");
  }, []);

  const options: ReadonlyArray<SegmentedControlOption<TabValue>> = [
    {
      value: "products",
      label: dict.toggleProductsLabel(counts.products),
      ariaLabel: dict.toggleProductsAria(counts.products),
    },
    {
      value: "parts",
      label: dict.togglePartsLabel(counts.parts),
      ariaLabel: dict.togglePartsAria(counts.parts),
    },
  ];

  const handleChange = (next: TabValue) => {
    const params = new URLSearchParams(searchParams?.toString() ?? "");
    if (next === "products") {
      // Default — прибираємо з URL для чистоти.
      params.delete("tab");
    } else {
      params.set("tab", next);
    }
    const query = params.toString();
    const url = query ? `${basePath}?${query}` : basePath;
    startTransition(() => {
      router.replace(url, { scroll: false });
    });
  };

  return (
    <SegmentedControl<TabValue>
      value={value}
      onValueChange={handleChange}
      options={options}
      ariaLabel={dict.toggleAria}
      testId="catalog-toggle"
      className="mt-4"
    />
  );
}
