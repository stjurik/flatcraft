/**
 * Pure debounce primitive — без React, тестується з vi.useFakeTimers.
 *
 * Reuse-кейс: будь-яке оновлення, де клавіш-події генерують stream,
 * а downstream-споживач (R3F mesh rebuild, API search) — heavyweight.
 */

export interface Debouncer<T> {
  schedule(value: T): void;
  cancel(): void;
}

export function createDebouncer<T>(delayMs: number, onFire: (value: T) => void): Debouncer<T> {
  if (delayMs < 0) throw new Error(`delayMs must be >= 0, got ${delayMs}`);
  let timer: ReturnType<typeof setTimeout> | null = null;
  let pending: T | null = null;
  let hasPending = false;

  return {
    schedule(value: T) {
      pending = value;
      hasPending = true;
      if (timer !== null) clearTimeout(timer);
      timer = setTimeout(() => {
        timer = null;
        if (hasPending) {
          hasPending = false;
          // Захоплюємо значення локально перед викликом — onFire може
          // тригернути ще schedule, який знов виставить pending.
          const v = pending as T;
          pending = null;
          onFire(v);
        }
      }, delayMs);
    },
    cancel() {
      if (timer !== null) {
        clearTimeout(timer);
        timer = null;
      }
      pending = null;
      hasPending = false;
    },
  };
}
