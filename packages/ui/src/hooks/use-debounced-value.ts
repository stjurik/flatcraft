"use client";

import { useEffect, useState } from "react";

/**
 * Повертає `value` зі затримкою `delayMs` після останньої зміни.
 *
 * Сценарій: input оновлюється на кожен keystroke, але heavy consumer
 * (R3F mesh rebuild) має тригеритися лише коли користувач зупинився.
 * 100мс — стандартний поріг CLAUDE.md §9 (Update параметра → mesh).
 *
 * Pure-debouncer (createDebouncer) живе у debounce.ts і покривається
 * unit-тестами; цей хук — тонкий React-wrapper.
 */
export function useDebouncedValue<T>(value: T, delayMs: number): T {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const id = setTimeout(() => setDebounced(value), delayMs);
    return () => clearTimeout(id);
  }, [value, delayMs]);
  return debounced;
}
