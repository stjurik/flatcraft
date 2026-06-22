"use client";

import { SegmentedControl, type SegmentedControlOption } from "@flatcraft/ui";
import { useRouter, useSearchParams } from "next/navigation";
import { useTransition } from "react";

type TabValue = "products" | "parts";

interface CatalogToggleProps {
  readonly value: TabValue;
  readonly counts: {
    readonly products: number;
    readonly parts: number;
  };
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
 * Це робить початковий URL `/templates` чистим.
 */
export function CatalogToggle({ value, counts }: CatalogToggleProps) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [, startTransition] = useTransition();

  const options: ReadonlyArray<SegmentedControlOption<TabValue>> = [
    {
      value: "products",
      label: `Вироби · ${counts.products}`,
      ariaLabel: `Готові вироби (${counts.products})`,
    },
    {
      value: "parts",
      label: `Деталі · ${counts.parts}`,
      ariaLabel: `Параметричні шаблони деталей (${counts.parts})`,
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
    const url = query ? `/templates?${query}` : "/templates";
    startTransition(() => {
      router.replace(url, { scroll: false });
    });
  };

  return (
    <SegmentedControl<TabValue>
      value={value}
      onValueChange={handleChange}
      options={options}
      ariaLabel="Вид каталогу"
      testId="catalog-toggle"
      className="mt-4"
    />
  );
}
